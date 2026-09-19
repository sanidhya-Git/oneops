/**
 * Async job: score one or more leads with AI after DML commits.
 * Fired from CRMService.createLead and LeadTriggerHandler.
 */
public class LeadScoringQueueable implements Queueable, Database.AllowsCallouts {

    private final List<Id> leadIds;

    public LeadScoringQueueable(List<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext ctx) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Company, Industry,
                   AnnualRevenue, NumberOfEmployees, LeadSource, Status, Email
            FROM Lead WHERE Id IN :leadIds AND IsConverted = false
        ];

        List<Lead> toUpdate  = new List<Lead>();
        List<AI_Insight__c> insights = new List<AI_Insight__c>();

        for (Lead lead : leads) {
            AIEngineService.AIResponse aiResp = AIEngineService.scoreLead(lead);
            if (!aiResp.success) continue;

            Integer score = Integer.valueOf(aiResp.data.get('score'));
            String  reason = (String) aiResp.data.get('reason');
            String  emailDraft = (String) aiResp.data.get('emailDraft');

            Lead update_ = new Lead(
                Id = lead.Id,
                AI_Score__c = score,
                AI_Assignment_Reason__c = reason,
                AI_Email_Draft__c = emailDraft
            );

            if (score >= OneOpsConstants.AI_SCORE_HOT) {
                update_.Rating = 'Hot';
            } else if (score >= OneOpsConstants.AI_SCORE_WARM) {
                update_.Rating = 'Warm';
            } else {
                update_.Rating = 'Cold';
            }

            toUpdate.add(update_);

            insights.add(new AI_Insight__c(
                Name                 = 'Lead Score: ' + lead.FirstName + ' ' + lead.LastName,
                Module__c            = OneOpsConstants.MODULE_CRM,
                Insight_Type__c      = 'Prediction',
                Content__c           = 'Score: ' + score + '/100 — ' + reason,
                Related_Record_ID__c = lead.Id,
                Related_Object_Type__c = 'Lead',
                AI_Provider__c       = aiResp.provider,
                Confidence_Score__c  = aiResp.confidence,
                Severity__c          = score >= 80 ? 'High' : (score >= 50 ? 'Medium' : 'Low')
            ));
        }

        if (!toUpdate.isEmpty())  Database.update(toUpdate, false);
        if (!insights.isEmpty())  Database.insert(insights, false);

        OneOpsLogger.info(OneOpsConstants.MODULE_CRM, 'LeadScoringQueueable: scored ' + toUpdate.size() + '/' + leads.size() + ' leads.');
    }
}
