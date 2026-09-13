/**
 * AIInsightBatch — nightly batch that:
 * 1. Purges expired AI_Insight__c records
 * 2. Generates fresh predictive insights for active Leads, Opportunities, and Tickets
 *
 * Schedule via anonymous Apex:
 *   Database.executeBatch(new AIInsightBatch(), 50);
 *   System.schedule('OneOps AI Insights Nightly', '0 0 2 * * ?', new AIInsightBatch());
 */
global with sharing class AIInsightBatch implements Database.Batchable<SObject>,
                                                    Database.AllowsCallouts,
                                                    Schedulable {

    global Database.QueryLocator start(Database.BatchableContext ctx) {
        // Process high-value Leads without a recent insight
        Datetime cutoff = Datetime.now().addHours(-24);
        return Database.getQueryLocator([
            SELECT Id, FirstName, LastName, Company, Industry, Title,
                   AnnualRevenue, NumberOfEmployees, LeadSource,
                   Lead_Score__c, Status
            FROM Lead
            WHERE IsConverted = false
              AND (Lead_Score__c = null OR Lead_Score__c >= 30)
            WITH USER_MODE
            ORDER BY AnnualRevenue DESC NULLS LAST
            LIMIT 5000
        ]);
    }

    global void execute(Database.BatchableContext ctx, List<SObject> records) {
        // Purge expired insights at start of each chunk
        purgeExpiredInsights();

        List<Lead> leads = (List<Lead>) records;
        if (leads.isEmpty()) return;

        // Build AI payload
        List<Map<String, Object>> leadPayloads = new List<Map<String, Object>>();
        for (Lead l : leads) {
            leadPayloads.add(new Map<String, Object>{
                'id'          => l.Id,
                'company'     => l.Company,
                'industry'    => l.Industry,
                'title'       => l.Title,
                'revenue'     => l.AnnualRevenue,
                'employees'   => l.NumberOfEmployees,
                'source'      => l.LeadSource,
                'currentScore'=> l.Lead_Score__c
            });
        }

        Map<String, Object> payload = new Map<String, Object>{
            'action'  => 'predict',
            'module'  => 'CRM',
            'records' => leadPayloads
        };

        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(payload);
        if (resp == null || !resp.success) return;

        List<AI_Insight__c> insights = buildInsights(resp, 'CRM');
        if (!insights.isEmpty() && Schema.sObjectType.AI_Insight__c.isCreateable()) {
            Database.insert(insights, false);
        }
    }

    global void finish(Database.BatchableContext ctx) {
        OneOpsLogger.audit('AIInsightBatch', 'Nightly AI insight batch completed.');
    }

    global void execute(SchedulableContext ctx) {
        Database.executeBatch(new AIInsightBatch(), 50);
    }

    /* ─── Helpers ───────────────────────────────────────────────── */

    private static void purgeExpiredInsights() {
        List<AI_Insight__c> expired = [
            SELECT Id FROM AI_Insight__c
            WHERE Expires_At__c < :Datetime.now()
              AND Expires_At__c != null
            WITH USER_MODE
            LIMIT 1000
        ];
        if (!expired.isEmpty() && Schema.sObjectType.AI_Insight__c.isDeletable()) {
            Database.delete(expired, false);
        }
    }

    private static List<AI_Insight__c> buildInsights(AIEngineService.AIResponse resp, String module) {
        List<AI_Insight__c> results = new List<AI_Insight__c>();
        Object data = resp.data;
        if (!(data instanceof List<Object>)) return results;

        for (Object item : (List<Object>) data) {
            Map<String, Object> m = (Map<String, Object>) item;
            results.add(new AI_Insight__c(
                Title__c      = 'Predictive Insight: ' + module,
                Summary__c    = JSON.serialize(m),
                Module__c     = module,
                Confidence__c = resp.confidence,
                AI_Provider__c = resp.provider,
                Expires_At__c  = Datetime.now().addDays(7),
                Severity__c    = 'Info'
            ));
        }
        return results;
    }
}
