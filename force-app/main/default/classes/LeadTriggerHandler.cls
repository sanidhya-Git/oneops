/**
 * Lead Trigger Handler — one class per trigger, all logic here.
 * Pattern: thin trigger → handler → service layer.
 */
public with sharing class LeadTriggerHandler {

    // ── Before Insert ──────────────────────────────────────────────────────

    public void onBeforeInsert(List<Lead> newLeads) {
        setDefaultStatus(newLeads);
        normalizePhonesAndEmails(newLeads);
    }

    // ── Before Update ──────────────────────────────────────────────────────

    public void onBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        for (Lead lead : newLeads) {
            Lead old = oldMap.get(lead.Id);
            // Auto-stamp status change for workflow auditing
            if (lead.Status != old.Status) {
                lead.Status_Changed_Date__c = Date.today();
            }
        }
    }

    // ── After Insert ───────────────────────────────────────────────────────

    public void onAfterInsert(List<Lead> newLeads) {
        List<Id> leadIds = new List<Id>();
        for (Lead l : newLeads) {
            if (!l.IsConverted) leadIds.add(l.Id);
        }
        if (!leadIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new LeadScoringQueueable(leadIds));
        }
    }

    // ── After Update ───────────────────────────────────────────────────────

    public void onAfterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        List<Id> reassigned = new List<Id>();

        for (Lead lead : newLeads) {
            Lead old = oldMap.get(lead.Id);

            // When owner changes, send notification
            if (lead.OwnerId != old.OwnerId) {
                reassigned.add(lead.Id);
            }
        }

        if (!reassigned.isEmpty()) {
            notifyReassignedLeads(reassigned, newLeads, oldMap);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void setDefaultStatus(List<Lead> leads) {
        for (Lead l : leads) {
            if (String.isBlank(l.Status)) l.Status = OneOpsConstants.LEAD_STATUS_NEW;
            if (String.isBlank(l.Rating)) l.Rating = 'Cold';
            if (String.isBlank(l.LeadSource)) l.LeadSource = 'Web';
        }
    }

    private static void normalizePhonesAndEmails(List<Lead> leads) {
        for (Lead l : leads) {
            if (String.isNotBlank(l.Email)) l.Email = l.Email.trim().toLowerCase();
        }
    }

    private static void notifyReassignedLeads(List<Id> leadIds, List<Lead> newLeads, Map<Id, Lead> oldMap) {
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, FirstName, LastName, Company, OwnerId, AI_Score__c
            FROM Lead WHERE Id IN :leadIds
        ]);

        for (Id leadId : leadIds) {
            Lead lead = leadMap.get(leadId);
            if (lead == null) continue;
            Integer score = lead.AI_Score__c != null ? Integer.valueOf(lead.AI_Score__c) : 0;
            NotificationService.notifyLeadAssigned(leadId, lead.OwnerId, '', score);
        }
    }
}
