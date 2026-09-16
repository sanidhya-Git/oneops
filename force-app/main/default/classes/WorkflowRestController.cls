@RestResource(urlMapping='/oneops/v1/workflow/*')
global with sharing class WorkflowRestController extends OneOpsRestBase {

    /**
     * GET /oneops/v1/workflow/logs          — paginated workflow log list
     * GET /oneops/v1/workflow/logs/{id}     — single log
     * GET /oneops/v1/workflow/stats         — execution statistics
     */
    @HttpGet
    global static void doGet() {
        try {
            requirePermission('WorkflowEngine');
            RestRequest  req  = RestContext.request;
            String path = req.requestURI.substringAfter('/oneops/v1/workflow/');

            if (path.startsWith('logs/')) {
                String rawId = path.substringAfter('logs/').substringBefore('/');
                Id logId = (String.isBlank(rawId) || rawId.length() < 15) ? null : (Id) rawId;
                if (logId == null) { sendError(400, OneOpsException.ERR_VALIDATION, 'Invalid log ID'); return; }

                List<Workflow_Log__c> logs = [
                    SELECT Id, Workflow_Name__c, Trigger_Type__c, Action_Type__c,
                           Target_Object__c, Target_Record_Id__c, Status__c,
                           Module__c, Duration_Ms__c, Error_Message__c, CreatedDate
                    FROM Workflow_Log__c
                    WHERE Id = :logId
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (logs.isEmpty()) { sendError(404, OneOpsException.ERR_NOT_FOUND, 'Log not found'); return; }
                sendSuccess(OneOpsResponseWrapper.success(logs[0]));

            } else if (path == 'stats') {
                getStats();

            } else {
                // List with optional filters
                String statusFilter = getQueryParam('status');
                String moduleFilter = getQueryParam('module');
                Integer pageNum     = getIntParam('page', 1);
                Integer pageSize    = Math.min(getIntParam('pageSize', 25), 100);
                Integer offset      = (pageNum - 1) * pageSize;

                String whereClause = 'WHERE Id != null';
                if (!String.isBlank(statusFilter)) whereClause += ' AND Status__c = :statusFilter';
                if (!String.isBlank(moduleFilter)) whereClause += ' AND Module__c = :moduleFilter';

                List<Workflow_Log__c> logs = Database.query(
                    'SELECT Id, Workflow_Name__c, Trigger_Type__c, Action_Type__c, ' +
                    '       Status__c, Module__c, Duration_Ms__c, CreatedDate ' +
                    'FROM Workflow_Log__c ' + whereClause +
                    ' WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
                );
                Integer total = Database.countQuery(
                    'SELECT COUNT() FROM Workflow_Log__c ' + whereClause + ' WITH USER_MODE'
                );
                OneOpsResponseWrapper wrapper = OneOpsResponseWrapper.success(logs);
                wrapper.totalRecords = total;
                wrapper.pageNumber   = pageNum;
                wrapper.pageSize     = pageSize;
                sendSuccess(wrapper);
            }
        } catch (Exception e) {
            OneOpsLogger.error('WorkflowRestController.doGet', e.getMessage());
            sendError(500, OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /**
     * POST /oneops/v1/workflow/trigger       — manual trigger
     * POST /oneops/v1/workflow/run/scheduled — run scheduled batch now
     */
    @HttpPost
    global static void doPost() {
        try {
            requirePermission('WorkflowEngine');
            RestRequest req  = RestContext.request;
            String path = req.requestURI.substringAfter('/oneops/v1/workflow/');
            Map<String, Object> body = parseBody();

            if (path == 'run/scheduled') {
                Integer count = WorkflowEngine.runScheduledWorkflows();
                sendSuccess(OneOpsResponseWrapper.success(new Map<String, Object>{ 'executed' => count }));

            } else if (path == 'trigger' || path.startsWith('trigger')) {
                String rawRecId   = (String) body.get('recordId');
                Id recordId       = (String.isBlank(rawRecId) || rawRecId.length() < 15) ? null : (Id) rawRecId;
                String workflowName = (String) body.get('workflowName');
                if (String.isBlank(workflowName)) { sendError(400, OneOpsException.ERR_VALIDATION, 'workflowName is required'); return; }
                OneOpsResponseWrapper result = WorkflowEngine.manualTrigger(recordId, workflowName);
                sendSuccess(result);

            } else {
                sendError(404, OneOpsException.ERR_NOT_FOUND, 'Unknown endpoint: ' + path);
            }
        } catch (Exception e) {
            OneOpsLogger.error('WorkflowRestController.doPost', e.getMessage());
            sendError(500, OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private static void getStats() {
        AggregateResult[] results = [
            SELECT Status__c status, COUNT(Id) cnt, AVG(Duration_Ms__c) avgMs
            FROM Workflow_Log__c
            WHERE CreatedDate = LAST_N_DAYS:7
            WITH USER_MODE
            GROUP BY Status__c
        ];

        Map<String, Object> stats = new Map<String, Object>();
        Integer total = 0;
        for (AggregateResult ar : results) {
            String status = (String) ar.get('status');
            Integer count = Integer.valueOf(ar.get('cnt'));
            total += count;
            stats.put(status, new Map<String, Object>{
                'count'  => count,
                'avgMs'  => ar.get('avgMs')
            });
        }
        stats.put('totalLast7Days', total);
        sendSuccess(OneOpsResponseWrapper.success(stats));
    }
}
