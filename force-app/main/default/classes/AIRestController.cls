/**
 * REST endpoint: /services/apexrest/oneops/v1/ai/*
 *
 * Routes:
 *   POST /ai/chat                  → AI chat assistant
 *   POST /ai/summarize             → document summarization
 *   POST /ai/predict/{module}      → predictive insights
 *   POST /ai/workflow/suggest      → workflow suggestions
 *   POST /ai/email/generate/{id}   → generate follow-up email for lead
 */
@RestResource(urlMapping='/oneops/v1/ai/*')
global with sharing class AIRestController extends OneOpsRestBase {

    @HttpPost
    global static void doPost() {
        try {
            String uri = RestContext.request.requestURI;
            Map<String, Object> body = parseBody();
            if (body == null) return;

            if (uri.endsWith('/chat')) {
                sendSuccess(AIEngineService.chatQuery(
                    (String) body.get('message'),
                    (String) body.get('context')
                ));
                return;
            }

            if (uri.endsWith('/summarize')) {
                sendSuccess(AIEngineService.summarizeDocument(
                    (String) body.get('text'),
                    (String) body.get('summaryType')
                ));
                return;
            }

            if (uri.contains('/predict/')) {
                String module = uri.substringAfterLast('/predict/').substringBefore('/');
                Map<String, Object> ctx = body.containsKey('context')
                    ? (Map<String, Object>) body.get('context')
                    : new Map<String, Object>();
                sendSuccess(AIEngineService.getPredictiveInsights(module, ctx));
                return;
            }

            if (uri.endsWith('/workflow/suggest')) {
                sendSuccess(AIEngineService.suggestWorkflow(
                    (String) body.get('triggerEvent'),
                    (String) body.get('objectType'),
                    body.containsKey('context') ? (Map<String, Object>) body.get('context') : null
                ));
                return;
            }

            if (uri.contains('/email/generate/')) {
                String idStr = uri.substringAfterLast('/email/generate/');
                sendSuccess(OneOpsResponseWrapper.ok(new Map<String, Object>{
                    'result' => AIEngineService.generateFollowUpEmail((Id) idStr, (String) body.get('context'), (String) body.get('tone'))
                }));
                return;
            }

            sendError(404, OneOpsException.ERR_NOT_FOUND, 'AI endpoint not found: ' + uri);

        } catch (Exception ex) {
            OneOpsLogger.error(OneOpsConstants.MODULE_AI, 'AIRestController.doPost error', ex);
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }

    @HttpGet
    global static void doGet() {
        try {
            String uri = RestContext.request.requestURI;

            if (uri.endsWith('/insights')) {
                String module = getQueryParam('module');
                sendSuccess(DashboardService.getAIInsightsFeed(module));
                return;
            }

            sendError(404, OneOpsException.ERR_NOT_FOUND, 'AI GET endpoint not found.');
        } catch (Exception ex) {
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }
}
