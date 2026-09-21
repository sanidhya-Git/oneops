/**
 * Async job: analyse a support ticket with AI for sentiment and suggested solution.
 * Fired immediately after ticket creation so the callout runs outside the DML transaction.
 */
public class TicketAIQueueable implements Queueable, Database.AllowsCallouts {

    private final Id ticketId;

    public TicketAIQueueable(Id ticketId) {
        this.ticketId = ticketId;
    }

    public void execute(QueueableContext ctx) {
        AIEngineService.AIResponse aiResp = AIEngineService.analyseTicket(ticketId);
        if (!aiResp.success) {
            OneOpsLogger.warn(OneOpsConstants.MODULE_SUPPORT, 'TicketAIQueueable: AI analysis failed for ' + ticketId);
            return;
        }

        String sentiment  = (String) aiResp.data.get('sentiment');   // Positive / Neutral / Negative / Frustrated
        String suggestion = (String) aiResp.data.get('suggestion');
        String aiComment  = (String) aiResp.data.get('agentNote');

        Support_Ticket__c update_ = new Support_Ticket__c(
            Id                      = ticketId,
            AI_Sentiment__c         = sentiment,
            AI_Suggested_Solution__c = suggestion
        );
        update update_;

        // Add AI-generated internal comment
        if (String.isNotBlank(aiComment)) {
            insert new Ticket_Comment__c(
                Support_Ticket__c = ticketId,
                Body__c           = '[AI] ' + aiComment,
                Author_Type__c    = 'AI',
                Is_Internal__c    = true,
                Is_AI_Generated__c = true
            );
        }

        OneOpsLogger.info(OneOpsConstants.MODULE_SUPPORT, 'TicketAI: sentiment=' + sentiment + ' for ticket ' + ticketId);
    }
}
