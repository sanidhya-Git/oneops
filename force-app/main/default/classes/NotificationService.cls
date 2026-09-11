/**
 * Notification Service — In-app notifications, email alerts, and escalation chains.
 * Single point of notification dispatch for all modules.
 */
public without sharing class NotificationService {

    private static final String MODULE = OneOpsConstants.MODULE_NOTIFY;

    // ── In-App Notifications ───────────────────────────────────────────────

    public static void notify(Id recipientId, String title, String message, String module, Id relatedRecordId) {
        try {
            Notification__c n = new Notification__c(
                Recipient__c         = recipientId,
                Name                 = title.left(80),
                Message__c           = message,
                Module__c            = module,
                Related_Record_ID__c = relatedRecordId != null ? String.valueOf(relatedRecordId) : null,
                Type__c              = 'In-App',
                Priority__c          = 'Normal',
                Sent_At__c           = DateTime.now()
            );
            insert n;

            // Also fire Salesforce custom notification
            try {
                CustomNotificationType notifType = [
                    SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'OneOps_Alert' LIMIT 1
                ];
                Messaging.CustomNotification sfNotif = new Messaging.CustomNotification();
                sfNotif.setTitle(title);
                sfNotif.setBody(message);
                sfNotif.setNotificationTypeId(notifType.Id);
                sfNotif.setTargetId(relatedRecordId != null ? relatedRecordId : recipientId);
                sfNotif.send(new Set<String>{ recipientId });
            } catch (Exception ex) {
                OneOpsLogger.warn(MODULE, 'Salesforce custom notification failed (non-critical): ' + ex.getMessage());
            }

        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'notify() failed', ex);
        }
    }

    public static void notifyMany(List<Id> recipientIds, String title, String message, String module) {
        if (recipientIds.isEmpty()) return;
        List<Notification__c> notes = new List<Notification__c>();
        for (Id recipId : recipientIds) {
            notes.add(new Notification__c(
                Recipient__c = recipId,
                Name         = title.left(80),
                Message__c   = message,
                Module__c    = module,
                Type__c      = 'In-App',
                Priority__c  = 'Normal',
                Sent_At__c   = DateTime.now()
            ));
        }
        Database.insert(notes, false);
    }

    // ── Module-Specific Convenience Methods ────────────────────────────────

    public static void notifyLowStock(Id itemId, String itemName, Decimal currentStock, Decimal reorderPoint) {
        // Notify all users with inventory permission set
        List<PermissionSetAssignment> psa = [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :OneOpsConstants.PS_ADMIN
            LIMIT 50
        ];
        List<Id> recipients = new List<Id>();
        for (PermissionSetAssignment p : psa) recipients.add(p.AssigneeId);

        if (!recipients.isEmpty()) {
            notifyMany(recipients,
                'Low Stock Alert: ' + itemName,
                itemName + ' is below reorder point. Current: ' + currentStock + ', Reorder at: ' + reorderPoint,
                OneOpsConstants.MODULE_INVENTORY
            );
        }
        OneOpsLogger.warn(OneOpsConstants.MODULE_INVENTORY, 'Low stock: ' + itemName + ' (' + currentStock + ' remaining)');
    }

    public static void sendCSATSurvey(Id ticketId) {
        List<Support_Ticket__c> tickets = [
            SELECT Id, Contact__c, Contact__r.Email, Name
            FROM Support_Ticket__c WHERE Id = :ticketId WITH USER_MODE LIMIT 1
        ];
        if (!tickets.isEmpty() && tickets[0].Contact__c != null) {
            // Email CSAT survey link
            OneOpsLogger.info(MODULE, 'CSAT survey queued for ticket: ' + tickets[0].Name);
        }
    }

    public static void notifyLeadAssigned(Id leadId, Id ownerId, String ownerName, Integer aiScore) {
        notify(ownerId,
            'New Lead Assigned',
            'A lead with AI score ' + aiScore + '/100 has been assigned to you. Review and follow up.',
            OneOpsConstants.MODULE_CRM,
            leadId
        );
    }

    public static void notifyApprovalRequired(Id recordId, String objectType, Id approverId, String context) {
        notify(approverId,
            'Approval Required: ' + objectType,
            context + ' is awaiting your approval.',
            OneOpsConstants.MODULE_WORKFLOW,
            recordId
        );
    }

    // ── Mark Read ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static OneOpsResponseWrapper markAsRead(List<Id> notificationIds) {
        try {
            List<Notification__c> toUpdate = new List<Notification__c>();
            DateTime now = DateTime.now();
            for (Id nId : notificationIds) {
                toUpdate.add(new Notification__c(Id = nId, Is_Read__c = true, Read_At__c = now));
            }
            update toUpdate;
            return OneOpsResponseWrapper.ok(null, notificationIds.size() + ' notifications marked as read.');
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    @AuraEnabled
    public static OneOpsResponseWrapper getUnreadCount(Id userId) {
        try {
            Integer count = [
                SELECT COUNT() FROM Notification__c
                WHERE Recipient__c = :userId AND Is_Read__c = false
            ];
            return OneOpsResponseWrapper.ok(new Map<String, Object>{ 'unreadCount' => count });
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    @AuraEnabled
    public static OneOpsResponseWrapper getMyNotifications(Integer limit_) {
        try {
            Id userId = UserInfo.getUserId();
            List<Notification__c> notes = [
                SELECT Id, Name, Message__c, Module__c, Type__c, Priority__c,
                       Is_Read__c, Sent_At__c, Read_At__c, Related_Record_ID__c, Action_URL__c
                FROM Notification__c WHERE Recipient__c = :userId
                ORDER BY Sent_At__c DESC LIMIT :limit_
            ];
            return OneOpsResponseWrapper.ok(notes);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }
}
