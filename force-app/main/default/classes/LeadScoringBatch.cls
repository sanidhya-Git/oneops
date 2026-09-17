/**
 * LeadScoringBatch — bulk re-scores all unconverted leads via AI.
 * Run on demand or schedule weekly.
 *
 * Execute via anonymous Apex:
 *   Database.executeBatch(new LeadScoringBatch(), 25);
 */
global with sharing class LeadScoringBatch implements Database.Batchable<SObject>,
                                                      Database.AllowsCallouts,
                                                      Schedulable {

    private final String statusFilter;

    global LeadScoringBatch() { this.statusFilter = null; }
    global LeadScoringBatch(String statusFilter) { this.statusFilter = statusFilter; }

    global Database.QueryLocator start(Database.BatchableContext ctx) {
        String baseQuery =
            'SELECT Id, FirstName, LastName, Company, Industry, Title, ' +
            '       AnnualRevenue, NumberOfEmployees, LeadSource, Status, ' +
            '       Email, Phone, Lead_Score__c ' +
            'FROM Lead ' +
            'WHERE IsConverted = false ';

        if (!String.isBlank(statusFilter)) {
            baseQuery += ' AND Status = :statusFilter';
        }
        baseQuery += ' WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 50000';
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext ctx, List<SObject> records) {
        List<Lead> leads = (List<Lead>) records;
        if (leads.isEmpty()) return;

        // Build payload — batch of up to 25 leads per AI call
        List<Map<String, Object>> leadData = new List<Map<String, Object>>();
        for (Lead l : leads) {
            leadData.add(new Map<String, Object>{
                'id'        => l.Id,
                'company'   => l.Company,
                'industry'  => l.Industry,
                'title'     => l.Title,
                'revenue'   => l.AnnualRevenue,
                'employees' => l.NumberOfEmployees,
                'source'    => l.LeadSource,
                'status'    => l.Status
            });
        }

        Map<String, Object> payload = new Map<String, Object>{
            'action'  => 'score_lead',
            'leads'   => leadData
        };

        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(payload);
        if (resp == null || !resp.success) {
            OneOpsLogger.warn('LeadScoringBatch', 'AI callout failed for batch of ' + leads.size());
            return;
        }

        // Parse response — expect array of {id, score, reason}
        List<Lead> toUpdate     = new List<Lead>();
        List<AI_Insight__c> insights = new List<AI_Insight__c>();

        if (resp.data instanceof List<Object>) {
            for (Object item : (List<Object>) resp.data) {
                Map<String, Object> m = (Map<String, Object>) item;
                String leadId = (String) m.get('id');
                Object score  = m.get('score');
                String reason = (String) m.get('reason');

                if (String.isBlank(leadId) || score == null) continue;

                toUpdate.add(new Lead(
                    Id           = (Id) leadId,
                    Lead_Score__c = Decimal.valueOf(String.valueOf(score))
                ));

                insights.add(new AI_Insight__c(
                    Title__c            = 'Lead Score Update',
                    Summary__c          = reason,
                    Module__c           = 'CRM',
                    Source_Record_Id__c = (Id) leadId,
                    Confidence__c       = resp.confidence,
                    AI_Provider__c      = resp.provider,
                    Expires_At__c       = Datetime.now().addDays(14),
                    Severity__c         = 'Info'
                ));
            }
        }

        if (!toUpdate.isEmpty())  Database.update(toUpdate, false);
        if (!insights.isEmpty() && Schema.sObjectType.AI_Insight__c.isCreateable()) {
            Database.insert(insights, false);
        }

        OneOpsLogger.audit('LeadScoringBatch', 'Scored ' + toUpdate.size() + ' leads');
    }

    global void finish(Database.BatchableContext ctx) {
        OneOpsLogger.audit('LeadScoringBatch', 'Batch scoring complete.');
    }

    global void execute(SchedulableContext ctx) {
        Database.executeBatch(new LeadScoringBatch(), 25);
    }

    public static void scheduleWeekly() {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'OneOps Lead Scoring Weekly'
            WITH USER_MODE
        ]) {
            System.abortJob(ct.Id);
        }
        System.schedule('OneOps Lead Scoring Weekly', '0 0 3 ? * MON', new LeadScoringBatch());
    }
}
