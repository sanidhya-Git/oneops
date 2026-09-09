/**
 * AI Engine Service — Salesforce-side bridge to the external Node.js AI microservice.
 * Provides a typed interface for all AI operations with provider abstraction,
 * response caching metadata, and full audit trail.
 *
 * All callouts go through the Named Credential 'OneOps_AI_Engine' which
 * stores the auth token and base URL.
 */
public with sharing class AIEngineService {

    private static final String MODULE  = OneOpsConstants.MODULE_AI;
    private static final String NC_PATH = 'callout:' + OneOpsConstants.NC_AI_ENGINE;

    // ── Response Wrapper ───────────────────────────────────────────────────

    public class AIResponse {
        public Boolean success      { get; set; }
        public String  provider     { get; set; }
        public Map<String, Object> data { get; set; }
        public Decimal confidence   { get; set; }
        public String  errorMessage { get; set; }
        public Long    latencyMs    { get; set; }
        public String  model        { get; set; }

        public AIResponse() {
            this.data      = new Map<String, Object>();
            this.confidence = 0;
        }
    }

    // ── Core Callout ───────────────────────────────────────────────────────

    public static AIResponse callAIEngine(Map<String, Object> payload) {
        AIResponse response = new AIResponse();
        Long start = DateTime.now().getTime();

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_PATH + '/api/v1/process');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('X-OneOps-Org', UserInfo.getOrganizationId());
            req.setHeader('X-Request-Id', 'SF-' + String.valueOf(DateTime.now().getTime()));
            req.setBody(JSON.serialize(payload));
            req.setTimeout(OneOpsConstants.AI_TIMEOUT_SECONDS * 1000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            response.latencyMs = DateTime.now().getTime() - start;

            if (res.getStatusCode() == 200) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                response.success    = true;
                response.provider   = (String) parsed.get('provider');
                response.model      = (String) parsed.get('model');
                response.confidence = parsed.get('confidence') != null
                    ? Decimal.valueOf(String.valueOf(parsed.get('confidence'))) : 0;
                response.data       = (Map<String, Object>) parsed.get('data');

                OneOpsLogger.info(MODULE, 'AI call success | Provider: ' + response.provider +
                    ' | Latency: ' + response.latencyMs + 'ms | Action: ' + payload.get('action'));
            } else {
                response.success      = false;
                response.errorMessage = 'AI engine returned status ' + res.getStatusCode() + ': ' + res.getBody().left(200);
                OneOpsLogger.warn(MODULE, 'AI call failed: ' + response.errorMessage);
            }

        } catch (CalloutException ex) {
            response.success      = false;
            response.latencyMs    = DateTime.now().getTime() - start;
            response.errorMessage = 'Callout exception: ' + ex.getMessage();
            OneOpsLogger.error(MODULE, 'AI Engine callout failed', ex);
        }

        return response;
    }

    // ── Lead Scoring ───────────────────────────────────────────────────────

    public static AIResponse scoreLead(Lead lead) {
        Map<String, Object> payload = new Map<String, Object>{
            'action'            => 'score_lead',
            'leadId'            => lead.Id,
            'company'           => lead.Company,
            'industry'          => lead.Industry,
            'annualRevenue'     => lead.AnnualRevenue,
            'numberOfEmployees' => lead.NumberOfEmployees,
            'leadSource'        => lead.LeadSource,
            'currentStatus'     => lead.Status,
            'email'             => lead.Email
        };
        return callAIEngine(payload);
    }

    // ── Email Generation ───────────────────────────────────────────────────

    public static AIResponse generateFollowUpEmail(Id leadId, String context, String tone) {
        List<Lead> leads = [
            SELECT FirstName, LastName, Company, Industry, Email, Status, AI_Score__c
            FROM Lead WHERE Id = :leadId WITH USER_MODE LIMIT 1
        ];
        if (leads.isEmpty()) {
            AIResponse r = new AIResponse();
            r.success = false;
            r.errorMessage = 'Lead not found: ' + leadId;
            return r;
        }
        Lead lead = leads[0];

        Map<String, Object> payload = new Map<String, Object>{
            'action'      => 'generate_email',
            'recipientName' => lead.FirstName + ' ' + lead.LastName,
            'company'     => lead.Company,
            'industry'    => lead.Industry,
            'emailAddr'   => lead.Email,
            'context'     => context,
            'tone'        => String.isNotBlank(tone) ? tone : 'professional',
            'aiScore'     => lead.AI_Score__c
        };
        return callAIEngine(payload);
    }

    // ── Ticket AI Analysis ─────────────────────────────────────────────────

    public static AIResponse analyseTicket(Id ticketId) {
        List<Support_Ticket__c> tickets = [
            SELECT Subject, Description__c, Category__c, Priority__c
            FROM Support_Ticket__c WHERE Id = :ticketId WITH USER_MODE LIMIT 1
        ];
        if (tickets.isEmpty()) {
            AIResponse r = new AIResponse();
            r.success = false;
            r.errorMessage = 'Ticket not found: ' + ticketId;
            return r;
        }

        Map<String, Object> payload = new Map<String, Object>{
            'action'      => 'analyse_ticket',
            'ticketId'    => ticketId,
            'subject'     => tickets[0].Subject,
            'description' => tickets[0].Description__c,
            'category'    => tickets[0].Category__c,
            'priority'    => tickets[0].Priority__c
        };
        return callAIEngine(payload);
    }

    // ── Chat Assistant ─────────────────────────────────────────────────────

    @AuraEnabled
    public static OneOpsResponseWrapper chatQuery(String userMessage, String conversationContext) {
        try {
            if (String.isBlank(userMessage)) {
                throw OneOpsException.validation('userMessage', 'Message cannot be empty.');
            }

            Map<String, Object> payload = new Map<String, Object>{
                'action'      => 'chat',
                'message'     => userMessage,
                'userId'      => UserInfo.getUserId(),
                'userName'    => UserInfo.getName(),
                'orgId'       => UserInfo.getOrganizationId(),
                'context'     => conversationContext
            };

            AIResponse aiResp = callAIEngine(payload);

            if (aiResp.success) {
                return OneOpsResponseWrapper.ok(aiResp.data)
                    .withModule(MODULE)
                    .withAIProvider(aiResp.provider)
                    .withMeta('latencyMs', aiResp.latencyMs);
            } else {
                throw OneOpsException.aiFailure('ChatAssistant', aiResp.errorMessage);
            }

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'chatQuery failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Document Summarization ─────────────────────────────────────────────

    @AuraEnabled
    public static OneOpsResponseWrapper summarizeDocument(String documentText, String summaryType) {
        try {
            if (String.isBlank(documentText)) {
                throw OneOpsException.validation('documentText', 'Document text is required.');
            }
            if (documentText.length() > 100000) {
                throw OneOpsException.validation('documentText', 'Document exceeds maximum length of 100,000 characters.');
            }

            Map<String, Object> payload = new Map<String, Object>{
                'action'       => 'summarize',
                'text'         => documentText,
                'summaryType'  => String.isNotBlank(summaryType) ? summaryType : 'executive'
            };

            AIResponse aiResp = callAIEngine(payload);
            if (aiResp.success) {
                return OneOpsResponseWrapper.ok(aiResp.data).withModule(MODULE);
            } else {
                throw OneOpsException.aiFailure('DocumentSummarization', aiResp.errorMessage);
            }

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Predictive Analytics ───────────────────────────────────────────────

    @AuraEnabled
    public static OneOpsResponseWrapper getPredictiveInsights(String module, Map<String, Object> contextData) {
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'action'  => 'predict',
                'module'  => module,
                'context' => contextData
            };

            AIResponse aiResp = callAIEngine(payload);
            if (!aiResp.success) {
                throw OneOpsException.aiFailure('PredictiveAnalytics', aiResp.errorMessage);
            }

            // Persist as AI_Insight__c
            AI_Insight__c insight = new AI_Insight__c(
                Name             = 'Prediction: ' + module + ' ' + Date.today(),
                Module__c        = module,
                Insight_Type__c  = 'Prediction',
                Content__c       = JSON.serialize(aiResp.data),
                AI_Provider__c   = aiResp.provider,
                Confidence_Score__c = aiResp.confidence,
                Expiry_Date__c   = DateTime.now().addDays(7)
            );
            insert insight;

            return OneOpsResponseWrapper.ok(aiResp.data).withModule(MODULE).withAIProvider(aiResp.provider);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Workflow Suggestions ───────────────────────────────────────────────

    @AuraEnabled
    public static OneOpsResponseWrapper suggestWorkflow(String triggerEvent, String objectType, Map<String, Object> recordContext) {
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'action'        => 'suggest_workflow',
                'triggerEvent'  => triggerEvent,
                'objectType'    => objectType,
                'recordContext' => recordContext
            };

            AIResponse aiResp = callAIEngine(payload);
            if (aiResp.success) {
                return OneOpsResponseWrapper.ok(aiResp.data).withModule(MODULE);
            } else {
                throw OneOpsException.aiFailure('WorkflowSuggestion', aiResp.errorMessage);
            }

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }
}
