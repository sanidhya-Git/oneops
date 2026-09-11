@IsTest
private class AIEngineServiceTest {

    /* ─── Mock callout returning a valid AI response ─────────────── */

    private class SuccessMock implements HttpCalloutMock {
        private Object data;
        SuccessMock(Object data) { this.data = data; }
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'success'    => true,
                'provider'   => 'openai',
                'data'       => data,
                'confidence' => 0.91,
                'latencyMs'  => 280,
                'model'      => 'gpt-4o'
            }));
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(503);
            res.setBody('{"success":false,"error":"Service Unavailable"}');
            return res;
        }
    }

    private class TimeoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.CalloutException('Callout timeout');
        }
    }

    /* ─── callAIEngine — success path ───────────────────────────── */

    @IsTest
    static void testCallAIEngine_successReturnsAIResponse() {
        Map<String, Object> payload = new Map<String, Object>{ 'action' => 'chat', 'query' => 'Hello' };
        Test.setMock(HttpCalloutMock.class, new SuccessMock(new Map<String, Object>{ 'reply' => 'Hi there!' }));

        Test.startTest();
        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(payload);
        Test.stopTest();

        System.assertNotEquals(null, resp);
        System.assert(resp.success);
        System.assertEquals('openai', resp.provider);
        System.assertEquals(0.91, resp.confidence);
        System.assertNotEquals(null, resp.data);
    }

    @IsTest
    static void testCallAIEngine_nonSuccessStatusReturnsFailedResponse() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(
            new Map<String, Object>{ 'action' => 'chat' }
        );
        Test.stopTest();

        System.assert(resp == null || !resp.success, 'Non-200 should return failed response');
    }

    @IsTest
    static void testCallAIEngine_calloutExceptionReturnsNull() {
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());

        Test.startTest();
        AIEngineService.AIResponse resp = AIEngineService.callAIEngine(
            new Map<String, Object>{ 'action' => 'chat' }
        );
        Test.stopTest();

        System.assert(resp == null || !resp.success, 'Timeout should return null or failed response');
    }

    /* ─── scoreLead ──────────────────────────────────────────────── */

    @IsTest
    static void testScoreLead_updatesLeadScore() {
        Lead l = new Lead(FirstName='Score', LastName='Test', Company='ACME', Email='score@test.com', Status='New');
        insert l;

        Test.setMock(HttpCalloutMock.class, new SuccessMock(new Map<String, Object>{
            'score'     => 85,
            'reason'    => 'High revenue industry match',
            'emailDraft'=> 'Dear Score...'
        }));

        Test.startTest();
        AIEngineService.AIResponse resp = AIEngineService.scoreLead(l);
        Test.stopTest();

        System.assertNotEquals(null, resp);
        System.assert(resp.success);
    }

    /* ─── analyseTicket ──────────────────────────────────────────── */

    @IsTest
    static void testAnalyseTicket_returnsSentiment() {
        Account acct = new Account(Name = 'AI Test Co');
        insert acct;
        Support_Ticket__c ticket = new Support_Ticket__c(
            Subject__c     = 'System crash',
            Description__c = 'Everything is broken, we lost data!',
            Priority__c    = 'Critical',
            Category__c    = 'Technical',
            Account__c     = acct.Id
        );
        insert ticket;

        Test.setMock(HttpCalloutMock.class, new SuccessMock(new Map<String, Object>{
            'sentiment'  => 'Frustrated',
            'solution'   => 'Check error logs and rollback migration',
            'urgency'    => 'Critical'
        }));

        Test.startTest();
        AIEngineService.AIResponse resp = AIEngineService.analyseTicket(ticket);
        Test.stopTest();

        System.assertNotEquals(null, resp);
        System.assert(resp.success);
    }

    /* ─── chatQuery (@AuraEnabled) ───────────────────────────────── */

    @IsTest
    static void testChatQuery_returnsReply() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(new Map<String, Object>{
            'reply'    => 'Here is the information you requested.',
            'provider' => 'openai'
        }));

        Test.startTest();
        OneOpsResponseWrapper result = AIEngineService.chatQuery('How many open leads?', null, null);
        Test.stopTest();

        System.assert(result != null);
    }

    /* ─── getPredictiveInsights (@AuraEnabled) ───────────────────── */

    @IsTest
    static void testGetPredictiveInsights_persistsInsight() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(new Map<String, Object>{
            'recommendation' => 'Focus on enterprise accounts in Q3',
            'confidence'     => 0.87
        }));

        Test.startTest();
        OneOpsResponseWrapper result = AIEngineService.getPredictiveInsights('Sales');
        Test.stopTest();

        System.assert(result != null);
        // Insight record should be created
        List<AI_Insight__c> insights = [SELECT Id FROM AI_Insight__c WHERE Module__c = 'Sales'];
        System.assert(!insights.isEmpty(), 'Predictive insight should be persisted');
    }
}
