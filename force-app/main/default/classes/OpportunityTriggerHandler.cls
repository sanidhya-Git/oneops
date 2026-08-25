public with sharing class OpportunityTriggerHandler {

    /* ─── Before Insert ──────────────────────────────────────────── */

    public void onBeforeInsert(List<Opportunity> newList) {
        for (Opportunity opp : newList) {
            setDefaults(opp);
        }
    }

    /* ─── Before Update ──────────────────────────────────────────── */

    public void onBeforeUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newList) {
            Opportunity old = oldMap.get(opp.Id);
            // Stamp close date on won/lost
            if (opp.StageName != old.StageName) {
                if (opp.StageName == 'Closed Won' || opp.StageName == 'Closed Lost') {
                    opp.CloseDate = Date.today();
                }
            }
        }
    }

    /* ─── After Insert ───────────────────────────────────────────── */

    public void onAfterInsert(List<Opportunity> newList) {
        notifyOnHighValue(newList);
    }

    /* ─── After Update ───────────────────────────────────────────── */

    public void onAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> wonOpps  = new List<Opportunity>();
        List<Opportunity> lostOpps = new List<Opportunity>();

        for (Opportunity opp : newList) {
            Opportunity old = oldMap.get(opp.Id);
            if (opp.StageName != old.StageName) {
                if (opp.StageName == 'Closed Won')  wonOpps.add(opp);
                if (opp.StageName == 'Closed Lost') lostOpps.add(opp);
            }
        }

        if (!wonOpps.isEmpty())  handleClosedWon(wonOpps);
        if (!lostOpps.isEmpty()) handleClosedLost(lostOpps);
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private void setDefaults(Opportunity opp) {
        if (String.isBlank(opp.StageName)) {
            opp.StageName = 'Prospecting';
        }
        if (opp.CloseDate == null) {
            opp.CloseDate = Date.today().addDays(30);
        }
    }

    private void notifyOnHighValue(List<Opportunity> opps) {
        List<Id> ownerIds = new List<Id>();
        for (Opportunity opp : opps) {
            if (opp.Amount != null && opp.Amount >= 100000) {
                ownerIds.add(opp.OwnerId);
            }
        }
        if (ownerIds.isEmpty()) return;

        for (Opportunity opp : opps) {
            if (opp.Amount != null && opp.Amount >= 100000) {
                NotificationService.notify(
                    opp.OwnerId,
                    'High-Value Opportunity',
                    opp.Name + ' — $' + opp.Amount.format() + ' created.',
                    opp.Id,
                    'Sales',
                    'Info'
                );
            }
        }
    }

    private void handleClosedWon(List<Opportunity> opps) {
        for (Opportunity opp : opps) {
            OneOpsLogger.audit('OpportunityTrigger', 'Closed Won: ' + opp.Name + ' — $' + opp.Amount);
            NotificationService.notify(
                opp.OwnerId,
                'Deal Won!',
                opp.Name + ' closed at $' + (opp.Amount != null ? opp.Amount.format() : '0') + '.',
                opp.Id, 'Sales', 'Info'
            );
        }
    }

    private void handleClosedLost(List<Opportunity> opps) {
        for (Opportunity opp : opps) {
            OneOpsLogger.audit('OpportunityTrigger', 'Closed Lost: ' + opp.Name);
        }
    }
}
