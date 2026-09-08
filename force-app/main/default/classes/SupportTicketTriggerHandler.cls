/**
 * Support Ticket Trigger Handler — SLA enforcement, escalation, status transitions.
 */
public with sharing class SupportTicketTriggerHandler {

    public void onBeforeInsert(List<Support_Ticket__c> newTickets) {
        DateTime now = DateTime.now();
        for (Support_Ticket__c t : newTickets) {
            if (t.SLA_Due_Date__c == null) {
                t.SLA_Due_Date__c = calculateSLADueDate(t.Priority__c, now);
            }
        }
    }

    public void onBeforeUpdate(List<Support_Ticket__c> newTickets, Map<Id, Support_Ticket__c> oldMap) {
        for (Support_Ticket__c t : newTickets) {
            Support_Ticket__c old = oldMap.get(t.Id);

            // When priority escalated, recalculate SLA
            if (t.Priority__c != old.Priority__c) {
                if (isSLAPriorityEscalation(old.Priority__c, t.Priority__c)) {
                    t.SLA_Due_Date__c = calculateSLADueDate(t.Priority__c, DateTime.now());
                }
            }

            // Record resolution timestamp
            if (t.Status__c == 'Resolved' && old.Status__c != 'Resolved') {
                t.Resolved_Date__c = DateTime.now();
            }
        }
    }

    public void onAfterInsert(List<Support_Ticket__c> newTickets) {
        for (Support_Ticket__c t : newTickets) {
            if (!Test.isRunningTest()) {
                System.enqueueJob(new TicketAIQueueable(t.Id));
            }
        }
    }

    public void onAfterUpdate(List<Support_Ticket__c> newTickets, Map<Id, Support_Ticket__c> oldMap) {
        for (Support_Ticket__c t : newTickets) {
            Support_Ticket__c old = oldMap.get(t.Id);

            // Notify agent on assignment
            if (t.Assigned_Agent__c != old.Assigned_Agent__c && t.Assigned_Agent__c != null) {
                NotificationService.notify(
                    t.Assigned_Agent__c,
                    'Ticket Assigned: ' + t.Name,
                    'Ticket ' + t.Name + ' (Priority: ' + t.Priority__c + ') has been assigned to you.',
                    OneOpsConstants.MODULE_SUPPORT,
                    t.Id
                );
            }

            // SLA breach alert
            if (t.Is_SLA_Breached__c && !old.Is_SLA_Breached__c) {
                OneOpsLogger.warn(OneOpsConstants.MODULE_SUPPORT, 'SLA breached: Ticket ' + t.Name + ' (Priority: ' + t.Priority__c + ')');
            }
        }
    }

    private static DateTime calculateSLADueDate(String priority, DateTime from) {
        Integer hours;
        if (priority == OneOpsConstants.PRIORITY_CRITICAL) hours = OneOpsConstants.SLA_CRITICAL_HOURS;
        else if (priority == OneOpsConstants.PRIORITY_HIGH)  hours = OneOpsConstants.SLA_HIGH_HOURS;
        else if (priority == OneOpsConstants.PRIORITY_LOW)   hours = OneOpsConstants.SLA_LOW_HOURS;
        else                                                   hours = OneOpsConstants.SLA_MEDIUM_HOURS;
        return from.addHours(hours);
    }

    private static Boolean isSLAPriorityEscalation(String oldPriority, String newPriority) {
        List<String> order = new List<String>{ 'Low', 'Medium', 'High', 'Critical' };
        return order.indexOf(newPriority) > order.indexOf(oldPriority);
    }
}
