@IsTest
private class GitHubServiceTest {

    /* ─── HTTP Mocks ─────────────────────────────────────────────── */

    private class CreateIssueMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{
                'number'     => 42,
                'html_url'   => 'https://github.com/oneops-ai/platform/issues/42',
                'state'      => 'open',
                'title'      => 'Test Task',
                'created_at' => '2026-01-01T00:00:00Z'
            }));
            return res;
        }
    }

    private class PatchIssueMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'state' => 'closed' }));
            return res;
        }
    }

    private class ListPRsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'number'   => 7,
                    'html_url' => 'https://github.com/oneops-ai/platform/pull/7',
                    'state'    => 'open',
                    'title'    => 'feature/ai-chatbot',
                    'merged'   => false,
                    'head'     => new Map<String, Object>{ 'ref' => 'feature/ai-chatbot' },
                    'base'     => new Map<String, Object>{ 'ref' => 'develop' }
                }
            }));
            return res;
        }
    }

    private class ListCommitsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'sha'      => 'abc1234',
                    'html_url' => 'https://github.com/oneops-ai/platform/commit/abc1234',
                    'commit'   => new Map<String, Object>{
                        'message' => 'feat: add AI chatbot LWC',
                        'author'  => new Map<String, Object>{
                            'name' => 'Chandrapal',
                            'date' => '2026-01-15T10:00:00Z'
                        }
                    }
                }
            }));
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(422);
            res.setBody('{"message":"Validation Failed"}');
            return res;
        }
    }

    /* ─── Test setup ─────────────────────────────────────────────── */

    @TestSetup
    static void setup() {
        Project__c proj = new Project__c(Name = 'Test Project');
        insert proj;
        Project_Task__c task = new Project_Task__c(
            Name       = 'Test Task',
            Project__c = proj.Id,
            Status__c  = 'To Do',
            Priority__c = 'High'
        );
        insert task;
    }

    /* ─── Tests ──────────────────────────────────────────────────── */

    @IsTest
    static void testCreateIssueFromTask_Success() {
        Project_Task__c task = [SELECT Id FROM Project_Task__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new CreateIssueMock());

        Test.startTest();
        OneOpsResponseWrapper result = GitHubService.createIssueFromTask(task.Id);
        Test.stopTest();

        System.assert(result.success, 'Expected success');
        Project_Task__c updated = [SELECT External_ID__c FROM Project_Task__c WHERE Id = :task.Id];
        System.assertEquals('GH-42', updated.External_ID__c, 'External ID should store GH-42');
    }

    @IsTest
    static void testCreateIssueFromTask_APIError() {
        Project_Task__c task = [SELECT Id FROM Project_Task__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        OneOpsResponseWrapper result = GitHubService.createIssueFromTask(task.Id);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure on 422');
    }

    @IsTest
    static void testUpdateIssueState() {
        Test.setMock(HttpCalloutMock.class, new PatchIssueMock());

        Test.startTest();
        OneOpsResponseWrapper result = GitHubService.updateIssueState(
            'oneops-ai/platform', 42, 'closed'
        );
        Test.stopTest();

        System.assert(result.success, 'Expected success');
    }

    @IsTest
    static void testGetOpenPRs() {
        Test.setMock(HttpCalloutMock.class, new ListPRsMock());

        Test.startTest();
        OneOpsResponseWrapper result = GitHubService.getOpenPRs('oneops-ai/platform');
        Test.stopTest();

        System.assert(result.success, 'Expected success');
    }

    @IsTest
    static void testGetRecentCommits() {
        Test.setMock(HttpCalloutMock.class, new ListCommitsMock());

        Test.startTest();
        OneOpsResponseWrapper result = GitHubService.getRecentCommits(
            'oneops-ai/platform', 'develop', 5
        );
        Test.stopTest();

        System.assert(result.success, 'Expected success');
    }

    @IsTest
    static void testHandleWebhookEvent_PR_Closed() {
        Project_Task__c task = [SELECT Id FROM Project_Task__c LIMIT 1];
        task.External_ID__c = 'GH-PR-99';
        update task;

        Map<String, Object> payload = new Map<String, Object>{
            'action'       => 'closed',
            'pull_request' => new Map<String, Object>{
                'number' => 99,
                'state'  => 'closed',
                'merged' => true
            }
        };

        Test.startTest();
        GitHubService.handleWebhookEvent('pull_request', JSON.serialize(payload));
        Test.stopTest();

        Project_Task__c updated = [SELECT Status__c FROM Project_Task__c WHERE Id = :task.Id];
        System.assertEquals('Done', updated.Status__c, 'Merged PR should set status to Done');
    }

    @IsTest
    static void testHandleWebhookEvent_Issue_Closed() {
        Project_Task__c task = [SELECT Id FROM Project_Task__c LIMIT 1];
        task.External_ID__c = 'GH-55';
        update task;

        Map<String, Object> payload = new Map<String, Object>{
            'action' => 'closed',
            'issue'  => new Map<String, Object>{ 'number' => 55, 'state' => 'closed' }
        };

        Test.startTest();
        GitHubService.handleWebhookEvent('issues', JSON.serialize(payload));
        Test.stopTest();

        Project_Task__c updated = [SELECT Status__c FROM Project_Task__c WHERE Id = :task.Id];
        System.assertEquals('Done', updated.Status__c, 'Closed issue should set status to Done');
    }

    @IsTest
    static void testHandleWebhookEvent_Push() {
        Map<String, Object> payload = new Map<String, Object>{
            'repository' => new Map<String, Object>{ 'full_name' => 'oneops-ai/platform' },
            'commits'    => new List<Object>{
                new Map<String, Object>{ 'id' => 'abc123', 'message' => 'fix: patch' }
            }
        };

        Test.startTest();
        GitHubService.handleWebhookEvent('push', JSON.serialize(payload));
        Test.stopTest();
        // No assertion needed — verifies no unhandled exception
    }
}
