/**
 * JiraService — Jira Cloud REST API integration.
 * Named Credential: OneOps_Jira (Basic Auth / API token)
 * Syncs Project Tasks with Jira issues bidirectionally.
 */
public with sharing class JiraService {

    private static final String NC_BASE = 'callout:OneOps_Jira';
    private static final String ISSUES  = '/rest/api/3/issue';

    /* ─── Create Jira issue from Project Task ────────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper createIssue(Id taskId) {
        try {
            Project_Task__c task = [
                SELECT Subject__c, Description__c, Priority__c, Project__r.Name,
                       Assigned_To__r.Email, Status__c
                FROM Project_Task__c
                WHERE Id = :taskId
                WITH USER_MODE
                LIMIT 1
            ];

            String priority = mapPriority(task.Priority__c);

            Map<String, Object> fields = new Map<String, Object>{
                'summary'     => task.Subject__c,
                'description' => buildAdfBody(task.Description__c),
                'issuetype'   => new Map<String, Object>{ 'name' => 'Task' },
                'priority'    => new Map<String, Object>{ 'name' => priority },
                'labels'      => new List<String>{ 'oneops', task.Project__r.Name }
            };

            Map<String, Object> payload = new Map<String, Object>{ 'fields' => fields };
            HttpResponse res = post(ISSUES, payload);

            if (res.getStatusCode() != 201) {
                return OneOpsResponseWrapper.error('Jira error: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            Map<String, Object> issue = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String jiraKey = (String) issue.get('key');

            // Store Jira key on the task
            update new Project_Task__c(Id = taskId, External_ID__c = jiraKey);

            OneOpsLogger.audit('JiraService', 'Issue created: ' + jiraKey + ' for task ' + task.Subject__c);
            return OneOpsResponseWrapper.success(issue);

        } catch (Exception e) {
            OneOpsLogger.error('JiraService.createIssue', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Update Jira issue status ───────────────────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper transitionIssue(String jiraKey, String targetStatus) {
        try {
            // Get available transitions
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_BASE + ISSUES + '/' + jiraKey + '/transitions');
            req.setMethod('GET');
            req.setTimeout(10000);
            HttpResponse transRes = new Http().send(req);

            if (transRes.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Could not retrieve transitions.',
                    OneOpsException.ERR_CALLOUT, transRes.getStatusCode());
            }

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(transRes.getBody());
            List<Object> transitions = (List<Object>) body.get('transitions');
            String transitionId      = null;

            for (Object t : transitions) {
                Map<String, Object> tMap = (Map<String, Object>) t;
                Map<String, Object> to   = (Map<String, Object>) tMap.get('to');
                if (((String) to.get('name')).equalsIgnoreCase(targetStatus)) {
                    transitionId = (String) tMap.get('id');
                    break;
                }
            }

            if (transitionId == null) {
                return OneOpsResponseWrapper.error('No transition found to status: ' + targetStatus,
                    OneOpsException.ERR_VALIDATION, 400);
            }

            Map<String, Object> transPayload = new Map<String, Object>{
                'transition' => new Map<String, Object>{ 'id' => transitionId }
            };
            HttpResponse res = post(ISSUES + '/' + jiraKey + '/transitions', transPayload);

            OneOpsLogger.audit('JiraService', 'Transitioned ' + jiraKey + ' → ' + targetStatus);
            return OneOpsResponseWrapper.success(new Map<String, Object>{ 'key' => jiraKey, 'newStatus' => targetStatus });

        } catch (Exception e) {
            OneOpsLogger.error('JiraService.transitionIssue', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Get issue details ──────────────────────────────────────── */

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getIssue(String jiraKey) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_BASE + ISSUES + '/' + jiraKey);
            req.setMethod('GET');
            req.setTimeout(10000);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Issue not found: ' + jiraKey,
                    OneOpsException.ERR_NOT_FOUND, 404);
            }
            return OneOpsResponseWrapper.success(
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody())
            );
        } catch (Exception e) {
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private static HttpResponse post(String path, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_BASE + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(10000);
        req.setBody(JSON.serialize(body));
        return new Http().send(req);
    }

    private static String mapPriority(String sfPriority) {
        if (sfPriority == 'Critical') return 'Highest';
        if (sfPriority == 'High')     return 'High';
        if (sfPriority == 'Low')      return 'Low';
        return 'Medium';
    }

    // Jira uses Atlassian Document Format for description
    private static Map<String, Object> buildAdfBody(String text) {
        return new Map<String, Object>{
            'type'    => 'doc',
            'version' => 1,
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type'    => 'paragraph',
                    'content' => new List<Object>{
                        new Map<String, Object>{ 'type' => 'text', 'text' => (text != null ? text : '') }
                    }
                }
            }
        };
    }
}
