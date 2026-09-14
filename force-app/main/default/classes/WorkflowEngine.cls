/**
 * WorkflowEngine — evaluates and executes OneOps workflow rules.
 *
 * Workflow rules are stored in Workflow_Log__c with Status = 'Pending'.
 * The scheduler polls for pending logs, evaluates conditions, and fires actions.
 *
 * Supported triggers:  Record_Created, Record_Updated, Schedule, Manual
 * Supported actions:   Send_Email, Create_Task, Notify_User, Update_Field, AI_Suggest
 */
public with sharing class WorkflowEngine {

    /* ─── Constants ─────────────────────────────────────────────── */

    private static final Integer MAX_RULES_PER_RUN = 200;

    /* ─── Entry points ───────────────────────────────────────────── */

    /**
     * Called by WorkflowScheduler for time-triggered rules.
     * Returns count of rules executed.
     */
    @AuraEnabled
    public static Integer runScheduledWorkflows() {
        List<Workflow_Log__c> pendingLogs = [
            SELECT Id, Workflow_Name__c, Trigger_Type__c, Action_Type__c,
                   Target_Object__c, Target_Record_Id__c, Conditions_JSON__c,
                   Action_Config_JSON__c, Status__c, Module__c, Duration_Ms__c
            FROM Workflow_Log__c
            WHERE Status__c = 'Pending'
              AND Trigger_Type__c = 'Schedule'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT :MAX_RULES_PER_RUN
        ];

        return executeRules(pendingLogs);
    }

    /**
     * Called by triggers / service classes to fire event-driven workflows.
     */
    public static void triggerWorkflow(String triggerType, String objectApiName,
                                       Id recordId, Map<String, Object> contextData) {
        if (String.isBlank(triggerType) || String.isBlank(objectApiName)) return;

        Workflow_Log__c log = new Workflow_Log__c(
            Workflow_Name__c    = 'Auto:' + objectApiName + ':' + triggerType,
            Trigger_Type__c     = triggerType,
            Target_Object__c    = objectApiName,
            Target_Record_Id__c = recordId,
            Conditions_JSON__c  = JSON.serialize(contextData),
            Status__c           = 'Pending',
            Module__c           = resolveModule(objectApiName)
        );

        if (!Schema.sObjectType.Workflow_Log__c.isCreateable()) return;
        insert log;

        // Execute inline if simple trigger type; defer heavy actions to queueable
        executeRules(new List<Workflow_Log__c>{ log });
    }

    /**
     * @AuraEnabled manual trigger from UI.
     */
    @AuraEnabled
    public static OneOpsResponseWrapper manualTrigger(Id recordId, String workflowName) {
        try {
            Workflow_Log__c log = new Workflow_Log__c(
                Workflow_Name__c    = workflowName,
                Trigger_Type__c     = 'Manual',
                Target_Record_Id__c = recordId,
                Status__c           = 'Pending'
            );
            insert log;
            Integer executed = executeRules(new List<Workflow_Log__c>{ log });
            return OneOpsResponseWrapper.success(new Map<String, Object>{
                'executed' => executed,
                'logId'    => log.Id
            });
        } catch (Exception e) {
            OneOpsLogger.error('WorkflowEngine.manualTrigger', e.getMessage());
            return OneOpsResponseWrapper.error('Workflow execution failed: ' + e.getMessage());
        }
    }

    /* ─── Core execution engine ──────────────────────────────────── */

    private static Integer executeRules(List<Workflow_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return 0;

        List<Workflow_Log__c> toUpdate = new List<Workflow_Log__c>();
        Integer successCount = 0;

        for (Workflow_Log__c log : logs) {
            Long startMs = System.currentTimeMillis();
            String status  = 'Completed';
            String errMsg  = null;

            try {
                executeAction(log);
                successCount++;
            } catch (Exception e) {
                status = 'Failed';
                errMsg = e.getMessage();
                OneOpsLogger.error('WorkflowEngine.executeRules', e.getMessage());
            }

            toUpdate.add(new Workflow_Log__c(
                Id           = log.Id,
                Status__c    = status,
                Duration_Ms__c = (Decimal)(System.currentTimeMillis() - startMs),
                Error_Message__c = errMsg
            ));
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }

        return successCount;
    }

    private static void executeAction(Workflow_Log__c log) {
        if (String.isBlank(log.Action_Type__c)) {
            // Default: persist AI suggestion
            if (log.Target_Record_Id__c != null) {
                requestAISuggestion(log);
            }
            return;
        }

        switch on log.Action_Type__c {
            when 'Send_Email' {
                fireEmailAction(log);
            }
            when 'Create_Task' {
                createTaskAction(log);
            }
            when 'Notify_User' {
                notifyUserAction(log);
            }
            when 'AI_Suggest' {
                requestAISuggestion(log);
            }
            when else {
                OneOpsLogger.warn('WorkflowEngine', 'Unknown action type: ' + log.Action_Type__c);
            }
        }
    }

    /* ─── Action implementations ─────────────────────────────────── */

    private static void fireEmailAction(Workflow_Log__c log) {
        Map<String, Object> cfg = parseConfig(log.Action_Config_JSON__c);
        String toAddress = (String) cfg.get('toAddress');
        String subject   = (String) cfg.get('subject');
        String body      = (String) cfg.get('body');

        if (String.isBlank(toAddress)) return;

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toAddress });
        email.setSubject(String.isBlank(subject) ? 'OneOps Workflow Notification' : subject);
        email.setHtmlBody(String.isBlank(body) ? 'A workflow action was triggered.' : body);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }

    private static void createTaskAction(Workflow_Log__c log) {
        if (!Schema.sObjectType.Task.isCreateable()) return;
        Map<String, Object> cfg = parseConfig(log.Action_Config_JSON__c);
        String subject   = (String) cfg.get('subject');
        String ownerId   = (String) cfg.get('ownerId');

        Task t = new Task(
            Subject     = String.isBlank(subject) ? 'Workflow Task: ' + log.Workflow_Name__c : subject,
            WhatId      = log.Target_Record_Id__c,
            OwnerId     = String.isBlank(ownerId) ? UserInfo.getUserId() : (Id) ownerId,
            ActivityDate = Date.today().addDays(1),
            Status      = 'Not Started',
            Priority    = 'Normal'
        );
        insert t;
    }

    private static void notifyUserAction(Workflow_Log__c log) {
        Map<String, Object> cfg     = parseConfig(log.Action_Config_JSON__c);
        String title  = (String) cfg.get('title');
        String body   = (String) cfg.get('body');
        String userId = (String) cfg.get('userId');

        NotificationService.notify(
            String.isBlank(userId) ? UserInfo.getUserId() : (Id) userId,
            String.isBlank(title)  ? log.Workflow_Name__c : title,
            String.isBlank(body)   ? 'A workflow action completed.' : body,
            log.Target_Record_Id__c,
            log.Module__c != null ? log.Module__c : 'System',
            'Info'
        );
    }

    private static void requestAISuggestion(Workflow_Log__c log) {
        Map<String, Object> payload = new Map<String, Object>{
            'action'   => 'suggest_workflow',
            'module'   => log.Module__c,
            'recordId' => log.Target_Record_Id__c,
            'trigger'  => log.Trigger_Type__c
        };
        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(payload);
        if (resp != null && resp.success) {
            AI_Insight__c insight = new AI_Insight__c(
                Title__c           = 'Workflow Suggestion: ' + log.Workflow_Name__c,
                Summary__c         = JSON.serialize(resp.data),
                Module__c          = log.Module__c,
                Source_Record_Id__c = log.Target_Record_Id__c,
                Confidence__c      = resp.confidence,
                AI_Provider__c     = resp.provider,
                Expires_At__c      = Datetime.now().addDays(7)
            );
            if (Schema.sObjectType.AI_Insight__c.isCreateable()) {
                insert insight;
            }
        }
    }

    /* ─── Helpers ────────────────────────────────────────────────── */

    private static Map<String, Object> parseConfig(String json) {
        if (String.isBlank(json)) return new Map<String, Object>();
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(json);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static String resolveModule(String objectApiName) {
        Map<String, String> mapping = new Map<String, String>{
            'Lead'               => 'CRM',
            'Opportunity'        => 'Sales',
            'Employee__c'        => 'HR',
            'Project__c'         => 'ProjectManagement',
            'Support_Ticket__c'  => 'Support',
            'Invoice__c'         => 'Finance',
            'Inventory_Item__c'  => 'Inventory',
            'Vendor__c'          => 'Vendor'
        };
        return mapping.containsKey(objectApiName) ? mapping.get(objectApiName) : 'System';
    }
}
