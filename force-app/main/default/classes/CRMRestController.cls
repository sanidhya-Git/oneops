/**
 * REST endpoint: /services/apexrest/oneops/v1/crm/*
 *
 * Routes:
 *   GET    /crm/leads                  → paginated lead list
 *   GET    /crm/leads/{id}             → single lead
 *   POST   /crm/leads                  → create lead
 *   PATCH  /crm/leads/{id}             → update lead
 *   POST   /crm/leads/{id}/score       → trigger AI scoring
 *   POST   /crm/leads/{id}/convert     → convert lead
 *   GET    /crm/leads/search?q=text    → SOSL search
 */
@RestResource(urlMapping='/oneops/v1/crm/*')
global with sharing class CRMRestController extends OneOpsRestBase {

    @HttpGet
    global static void doGet() {
        try {
            String uri = RestContext.request.requestURI;
            String[] segments = uri.split('/');

            // /crm/leads/search
            if (uri.contains('/leads/search')) {
                String q = getQueryParam('q');
                sendSuccess(CRMService.searchLeads(q));
                return;
            }

            // /crm/leads/{id}
            if (segments.size() >= 6 && String.isNotBlank(segments[5])) {
                Id leadId;
                try { leadId = (Id) segments[5]; } catch (Exception ex) {
                    sendError(400, OneOpsException.ERR_VALIDATION, 'Invalid lead ID.');
                    return;
                }
                sendSuccess(CRMService.getLeadById(leadId));
                return;
            }

            // /crm/leads
            Integer page      = getIntParam('page', 1);
            Integer pageSize  = Math.min(getIntParam('pageSize', 20), 100);
            String  status    = getQueryParam('status');
            String  search    = getQueryParam('search');
            sendSuccess(CRMService.getLeads(page, pageSize, status, search));

        } catch (Exception ex) {
            OneOpsLogger.error(OneOpsConstants.MODULE_CRM, 'CRMRestController.doGet error', ex);
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }

    @HttpPost
    global static void doPost() {
        try {
            String uri = RestContext.request.requestURI;

            // /crm/leads/{id}/score
            if (uri.endsWith('/score')) {
                String idStr = uri.substringBeforeLast('/score').substringAfterLast('/');
                sendSuccess(CRMService.scoreLeadWithAI((Id) idStr));
                return;
            }

            // /crm/leads/{id}/convert
            if (uri.endsWith('/convert')) {
                String idStr = uri.substringBeforeLast('/convert').substringAfterLast('/');
                Map<String, Object> body = parseBody();
                sendSuccess(CRMService.convertLead(
                    (Id) idStr,
                    (String) body.get('opportunityName'),
                    body.containsKey('createOpportunity') ? (Boolean) body.get('createOpportunity') : true
                ));
                return;
            }

            // /crm/leads — create
            Map<String, Object> body = parseBody();
            if (body == null) return;
            sendSuccess(CRMService.createLead(body));

        } catch (Exception ex) {
            OneOpsLogger.error(OneOpsConstants.MODULE_CRM, 'CRMRestController.doPost error', ex);
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }

    @HttpPatch
    global static void doPatch() {
        try {
            String uri  = RestContext.request.requestURI;
            String idStr = uri.substringAfterLast('/');
            Map<String, Object> body = parseBody();
            if (body == null) return;
            sendSuccess(CRMService.updateLead((Id) idStr, body));
        } catch (Exception ex) {
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }
}
