/**
 * REST endpoint: /services/apexrest/oneops/v1/dashboard/*
 *
 * Routes:
 *   GET /dashboard/summary           → executive KPI summary
 *   GET /dashboard/revenue?months=6  → revenue trend
 *   GET /dashboard/lead-funnel       → lead stage funnel
 *   GET /dashboard/support-trends    → ticket analytics
 *   GET /dashboard/activity          → recent audit trail
 */
@RestResource(urlMapping='/oneops/v1/dashboard/*')
global with sharing class DashboardRestController extends OneOpsRestBase {

    @HttpGet
    global static void doGet() {
        try {
            String uri = RestContext.request.requestURI;

            if (uri.endsWith('/summary')) {
                sendSuccess(DashboardService.getExecutiveSummary());
                return;
            }

            if (uri.endsWith('/revenue')) {
                Integer months = getIntParam('months', 6);
                sendSuccess(DashboardService.getRevenueTrend(months));
                return;
            }

            if (uri.endsWith('/lead-funnel')) {
                sendSuccess(DashboardService.getLeadFunnel());
                return;
            }

            if (uri.endsWith('/support-trends')) {
                Integer days = getIntParam('days', 30);
                sendSuccess(DashboardService.getSupportTrends(days));
                return;
            }

            if (uri.endsWith('/activity')) {
                sendSuccess(DashboardService.getRecentActivity());
                return;
            }

            if (uri.contains('/insights')) {
                String module = getQueryParam('module');
                sendSuccess(DashboardService.getAIInsightsFeed(module));
                return;
            }

            sendError(404, OneOpsException.ERR_NOT_FOUND, 'Dashboard endpoint not found.');

        } catch (Exception ex) {
            OneOpsLogger.error(OneOpsConstants.MODULE_ANALYTICS, 'DashboardRestController.doGet error', ex);
            sendError(500, OneOpsException.ERR_SYSTEM, ex.getMessage());
        }
    }
}
