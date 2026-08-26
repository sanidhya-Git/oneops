/**
 * GitHubService — GitHub REST API v3 integration.
 * Creates issues from PM tasks, syncs PR status, links commits to records.
 * NC: OneOps_GitHub (Personal Access Token, Bearer scheme)
 */
public with sharing class GitHubService {

    private static final String NC          = 'callout:OneOps_GitHub';
    private static final String API_VERSION = 'v3';
    private static final Integer TIMEOUT    = 15000;

    /* ─────────────────────────────────────────────────────────────────
     * Inner DTOs
     * ──────────────────────────────────────────────────────────────── */

    public class GitHubIssue {
        @AuraEnabled public Integer number;
        @AuraEnabled public String  htmlUrl;
        @AuraEnabled public String  state;
        @AuraEnabled public String  title;
        @AuraEnabled public String  body;
        @AuraEnabled public String  createdAt;
    }

    public class GitHubPR {
        @AuraEnabled public Integer number;
        @AuraEnabled public String  htmlUrl;
        @AuraEnabled public String  state;
        @AuraEnabled public String  title;
        @AuraEnabled public String  headRef;
        @AuraEnabled public String  baseRef;
        @AuraEnabled public Boolean merged;
        @AuraEnabled public String  mergedAt;
    }

    public class GitHubCommit {
        @AuraEnabled public String sha;
        @AuraEnabled public String htmlUrl;
        @AuraEnabled public String message;
        @AuraEnabled public String authorName;
        @AuraEnabled public String committedAt;
    }

    /* ─────────────────────────────────────────────────────────────────
     * Issue management
     * ──────────────────────────────────────────────────────────────── */

    /**
     * Creates a GitHub issue from a Project_Task__c record.
     * Stores the issue URL in External_ID__c on the task.
     */
    @AuraEnabled
    public static OneOpsResponseWrapper createIssueFromTask(Id taskId) {
        try {
            Project_Task__c task = [
                SELECT Id, Name, Description__c, Priority__c, Assigned_To__c,
                       Assigned_To__r.Name, Status__c, GitHub_Repo__c
                FROM   Project_Task__c
                WHERE  Id = :taskId
                WITH   USER_MODE
                LIMIT  1
            ];

            String repo = String.isBlank(task.GitHub_Repo__c)
                ? getDefaultRepo()
                : task.GitHub_Repo__c;

            Map<String, Object> body = new Map<String, Object>{
                'title'  => task.Name,
                'body'   => buildIssueBody(task),
                'labels' => getLabelsForPriority(task.Priority__c)
            };

            Map<String, Object> response = doPost('/repos/' + repo + '/issues', body);
            String issueUrl = (String) response.get('html_url');
            Integer issueNum = ((Decimal) response.get('number')).intValue();

            task.External_ID__c = 'GH-' + issueNum;
            Security.stripInaccessible(AccessType.UPDATABLE, new List<Project_Task__c>{ task });
            Database.update(task, false);

            GitHubIssue dto = new GitHubIssue();
            dto.number    = issueNum;
            dto.htmlUrl   = issueUrl;
            dto.state     = (String) response.get('state');
            dto.title     = (String) response.get('title');
            dto.createdAt = (String) response.get('created_at');

            PlatformEventService.publishWorkflowEvent(
                'GitHub_Issue_Created', 'PM', taskId,
                new Map<String, Object>{ 'issue_number' => issueNum, 'repo' => repo }
            );

            return OneOpsResponseWrapper.success(dto, 'GitHub issue #' + issueNum + ' created');
        } catch (Exception e) {
            OneOpsLogger.error('GitHubService.createIssueFromTask', e.getMessage());
            return OneOpsResponseWrapper.error(OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /**
     * Updates the state of an existing GitHub issue (open / closed).
     */
    @AuraEnabled
    public static OneOpsResponseWrapper updateIssueState(String repo, Integer issueNumber,
                                                          String state) {
        try {
            Map<String, Object> body = new Map<String, Object>{ 'state' => state };
            Map<String, Object> response = doPatch(
                '/repos/' + repo + '/issues/' + issueNumber, body
            );
            return OneOpsResponseWrapper.success(
                new Map<String, Object>{ 'state' => response.get('state') },
                'Issue state updated to ' + state
            );
        } catch (Exception e) {
            OneOpsLogger.error('GitHubService.updateIssueState', e.getMessage());
            return OneOpsResponseWrapper.error(OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /* ─────────────────────────────────────────────────────────────────
     * Pull request queries
     * ──────────────────────────────────────────────────────────────── */

    /**
     * Returns open PRs for a repository.
     */
    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getOpenPRs(String repo) {
        try {
            String path = '/repos/' + repo + '/pulls?state=open&per_page=25';
            List<Object> raw = doGetList(path);
            List<GitHubPR> prs = new List<GitHubPR>();
            for (Object item : raw) {
                Map<String, Object> m = (Map<String, Object>) item;
                GitHubPR pr = new GitHubPR();
                pr.number  = ((Decimal) m.get('number')).intValue();
                pr.htmlUrl = (String) m.get('html_url');
                pr.state   = (String) m.get('state');
                pr.title   = (String) m.get('title');
                pr.merged  = (Boolean) (m.get('merged') != null ? m.get('merged') : false);
                Map<String, Object> head = (Map<String, Object>) m.get('head');
                Map<String, Object> base = (Map<String, Object>) m.get('base');
                if (head != null) pr.headRef = (String) head.get('ref');
                if (base != null) pr.baseRef = (String) base.get('ref');
                prs.add(pr);
            }
            return OneOpsResponseWrapper.success(prs, null);
        } catch (Exception e) {
            OneOpsLogger.error('GitHubService.getOpenPRs', e.getMessage());
            return OneOpsResponseWrapper.error(OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /**
     * Returns recent commits for a repository branch.
     */
    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getRecentCommits(String repo, String branch,
                                                          Integer maxResults) {
        try {
            Integer limit = maxResults != null && maxResults > 0 ? Math.min(maxResults, 50) : 10;
            String path = '/repos/' + repo + '/commits?sha=' + branch + '&per_page=' + limit;
            List<Object> raw = doGetList(path);
            List<GitHubCommit> commits = new List<GitHubCommit>();
            for (Object item : raw) {
                Map<String, Object> m      = (Map<String, Object>) item;
                Map<String, Object> commit = (Map<String, Object>) m.get('commit');
                Map<String, Object> author = commit != null
                    ? (Map<String, Object>) commit.get('author')
                    : null;
                GitHubCommit dto      = new GitHubCommit();
                dto.sha               = (String) m.get('sha');
                dto.htmlUrl           = (String) m.get('html_url');
                dto.message           = commit != null ? (String) commit.get('message') : '';
                dto.authorName        = author != null ? (String) author.get('name')  : '';
                dto.committedAt       = author != null ? (String) author.get('date')  : '';
                commits.add(dto);
            }
            return OneOpsResponseWrapper.success(commits, null);
        } catch (Exception e) {
            OneOpsLogger.error('GitHubService.getRecentCommits', e.getMessage());
            return OneOpsResponseWrapper.error(OneOpsException.ERR_SYSTEM, e.getMessage());
        }
    }

    /* ─────────────────────────────────────────────────────────────────
     * Webhook receiver (REST endpoint)
     * ──────────────────────────────────────────────────────────────── */

    /**
     * Called by GitHub webhook → Salesforce inbound site/endpoint.
     * Handles push, pull_request, issues events.
     */
    public static void handleWebhookEvent(String eventType, String payloadJson) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);

        if (eventType == 'pull_request') {
            handlePREvent(payload);
        } else if (eventType == 'issues') {
            handleIssueEvent(payload);
        } else if (eventType == 'push') {
            handlePushEvent(payload);
        }
    }

    /* ─────────────────────────────────────────────────────────────────
     * Private helpers
     * ──────────────────────────────────────────────────────────────── */

    private static void handlePREvent(Map<String, Object> payload) {
        String action = (String) payload.get('action');
        Map<String, Object> pr = (Map<String, Object>) payload.get('pull_request');
        if (pr == null) return;

        Integer prNum = ((Decimal) pr.get('number')).intValue();
        String  state = (String)  pr.get('state');

        // Find task with matching External_ID and update its status
        String extId = 'GH-PR-' + prNum;
        List<Project_Task__c> tasks = [
            SELECT Id, Status__c, External_ID__c
            FROM   Project_Task__c
            WHERE  External_ID__c = :extId
            WITH   USER_MODE
            LIMIT  1
        ];
        if (!tasks.isEmpty() && action == 'closed') {
            Boolean merged = (Boolean) pr.get('merged');
            tasks[0].Status__c = merged == true ? 'Done' : 'Blocked';
            Database.update(tasks, false);
        }

        PlatformEventService.publishWorkflowEvent(
            'GitHub_PR_' + action.capitalize(), 'PM', null,
            new Map<String, Object>{ 'pr_number' => prNum, 'state' => state }
        );
    }

    private static void handleIssueEvent(Map<String, Object> payload) {
        String action = (String) payload.get('action');
        Map<String, Object> issue = (Map<String, Object>) payload.get('issue');
        if (issue == null) return;

        Integer issueNum = ((Decimal) issue.get('number')).intValue();
        String  extId    = 'GH-' + issueNum;

        if (action == 'closed') {
            List<Project_Task__c> tasks = [
                SELECT Id, Status__c
                FROM   Project_Task__c
                WHERE  External_ID__c = :extId
                WITH   USER_MODE
                LIMIT  1
            ];
            if (!tasks.isEmpty()) {
                tasks[0].Status__c = 'Done';
                Database.update(tasks, false);
            }
        }
    }

    private static void handlePushEvent(Map<String, Object> payload) {
        List<Object> commits    = (List<Object>) payload.get('commits');
        Map<String, Object> repo = (Map<String, Object>) payload.get('repository');
        String repoName = repo != null ? (String) repo.get('full_name') : '';
        Integer count   = commits != null ? commits.size() : 0;

        PlatformEventService.publishWorkflowEvent(
            'GitHub_Push', 'PM', null,
            new Map<String, Object>{ 'repo' => repoName, 'commit_count' => count }
        );
    }

    private static String buildIssueBody(Project_Task__c task) {
        String body = '## OneOps Task\n\n';
        if (String.isNotBlank(task.Description__c)) {
            body += task.Description__c + '\n\n';
        }
        body += '**Priority:** ' + (task.Priority__c != null ? task.Priority__c : 'Normal') + '\n';
        body += '**Status:** '   + (task.Status__c   != null ? task.Status__c   : 'Open')   + '\n';
        if (task.Assigned_To__r != null) {
            body += '**Assigned To:** ' + task.Assigned_To__r.Name + '\n';
        }
        body += '\n---\n_Created automatically from OneOps AI Platform_';
        return body;
    }

    private static List<String> getLabelsForPriority(String priority) {
        if (priority == 'Critical') return new List<String>{ 'priority: critical', 'oneops' };
        if (priority == 'High')     return new List<String>{ 'priority: high',     'oneops' };
        if (priority == 'Low')      return new List<String>{ 'priority: low',      'oneops' };
        return new List<String>{ 'oneops' };
    }

    private static String getDefaultRepo() {
        // Falls back to org-wide custom metadata if task has no repo field set
        List<OneOps_Config__mdt> cfg = [
            SELECT Value__c FROM OneOps_Config__mdt
            WHERE DeveloperName = 'GitHub_Default_Repo' LIMIT 1
        ];
        return cfg.isEmpty() ? 'oneops-ai/platform' : cfg[0].Value__c;
    }

    /* ─── HTTP helpers ─────────────────────────────────────────────── */

    private static Map<String, Object> doPost(String path, Map<String, Object> body) {
        HttpResponse res = sendRequest('POST', path, JSON.serialize(body));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static Map<String, Object> doPatch(String path, Map<String, Object> body) {
        HttpResponse res = sendRequest('PATCH', path, JSON.serialize(body));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static List<Object> doGetList(String path) {
        HttpResponse res = sendRequest('GET', path, null);
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static HttpResponse sendRequest(String method, String path, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC + path);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/vnd.github.' + API_VERSION + '+json');
        req.setTimeout(TIMEOUT);
        if (String.isNotBlank(body)) req.setBody(body);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() > 299) {
            throw new OneOpsException(
                OneOpsException.ERR_SYSTEM,
                'GitHub API error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }
        return res;
    }
}
