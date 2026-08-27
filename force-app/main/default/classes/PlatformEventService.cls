/**
 * PlatformEventService — publishes OneOps platform events for cross-module
 * and cross-system event-driven communication.
 *
 * Listeners (Flow Builder / Process Automation) subscribe to these events.
 */
public without sharing class PlatformEventService {

    /* ─── Publish Workflow Event ─────────────────────────────────── */

    public static void publishWorkflowEvent(String eventType, String module,
                                             Id recordId, Map<String, Object> payload) {
        Workflow_Event__e event = new Workflow_Event__e(
            Event_Type__c   = eventType,
            Module__c       = module,
            Record_Id__c    = recordId != null ? String.valueOf(recordId) : null,
            Payload_JSON__c = payload != null ? JSON.serialize(payload) : null,
            User_Id__c      = String.valueOf(UserInfo.getUserId())
        );
        Database.SaveResult result = EventBus.publish(event);
        if (!result.isSuccess()) {
            OneOpsLogger.error('PlatformEventService', 'Failed to publish Workflow_Event__e: '
                + result.getErrors()[0].getMessage());
        }
    }

    /* ─── Publish AI Action Event ────────────────────────────────── */

    public static void publishAIActionEvent(String action, String module, Id recordId,
                                             String provider, Decimal confidence,
                                             Map<String, Object> result) {
        AI_Action_Event__e event = new AI_Action_Event__e(
            Action__c      = action,
            Module__c      = module,
            Record_Id__c   = recordId != null ? String.valueOf(recordId) : null,
            AI_Provider__c = provider,
            Confidence__c  = confidence,
            Result_JSON__c = result != null ? JSON.serialize(result) : null
        );
        Database.SaveResult sr = EventBus.publish(event);
        if (!sr.isSuccess()) {
            OneOpsLogger.error('PlatformEventService', 'Failed to publish AI_Action_Event__e: '
                + sr.getErrors()[0].getMessage());
        }
    }

    /* ─── Convenience methods ────────────────────────────────────── */

    public static void onLeadCreated(Id leadId)         { publishWorkflowEvent('Lead_Created',       'CRM',     leadId, null); }
    public static void onTicketCreated(Id ticketId)     { publishWorkflowEvent('Ticket_Created',     'Support', ticketId, null); }
    public static void onPOApproved(Id poId)            { publishWorkflowEvent('PO_Approved',        'Vendor',  poId, null); }
    public static void onInvoiceSent(Id invoiceId)      { publishWorkflowEvent('Invoice_Sent',       'Finance', invoiceId, null); }
    public static void onLeaveApproved(Id leaveId)      { publishWorkflowEvent('Leave_Approved',     'HR',      leaveId, null); }
    public static void onLowStockAlert(Id itemId, Decimal qty) {
        publishWorkflowEvent('Low_Stock_Alert', 'Inventory', itemId, new Map<String, Object>{ 'qty' => qty });
    }
    public static void onTaskMoved(Id taskId, String newStatus) {
        publishWorkflowEvent('Task_Status_Changed', 'PM', taskId, new Map<String, Object>{ 'status' => newStatus });
    }
}
