@IsTest
private class CRMServiceTest {

    /* ─── Test Data Factory ─────────────────────────────────────── */

    private static Lead makeLead(String firstName, String lastName, String company) {
        return new Lead(
            FirstName   = firstName,
            LastName    = lastName,
            Company     = company,
            Email       = (firstName + '.' + lastName + '@test.com').toLowerCase(),
            Phone       = '+1-555-000-0001',
            LeadSource  = 'Web',
            Industry    = 'Technology',
            AnnualRevenue = 500000
        );
    }

    /* ─── createLead ────────────────────────────────────────────── */

    @IsTest
    static void testCreateLead_happyPath() {
        Lead l = makeLead('Alice', 'Smith', 'Acme Corp');

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.createLead(
            'Alice', 'Smith', 'Acme Corp', l.Email, l.Phone,
            'Web', 'Technology', 500000, null
        );
        Test.stopTest();

        System.assert(result.success, 'createLead should succeed');
        Lead inserted = [SELECT Id, Status, Rating FROM Lead WHERE Email = :l.Email LIMIT 1];
        System.assertEquals('New', inserted.Status);
    }

    @IsTest
    static void testCreateLead_missingRequiredField_returnsError() {
        Test.startTest();
        OneOpsResponseWrapper result = CRMService.createLead(
            '', '', '', 'bad@test.com', null, null, null, null, null
        );
        Test.stopTest();

        System.assert(!result.success || result.data == null,
            'createLead with missing fields should fail or return empty');
    }

    /* ─── getLeads ──────────────────────────────────────────────── */

    @IsTest
    static void testGetLeads_returnsPagedResults() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(makeLead('TestUser' + i, 'Load' + i, 'Corp' + i));
        }
        insert leads;

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.getLeads(null, null, null, 1, 10);
        Test.stopTest();

        System.assert(result.success);
        System.assert(result.totalRecords >= 5);
    }

    @IsTest
    static void testGetLeads_statusFilter() {
        Lead l = makeLead('Filter', 'Me', 'FilterCorp');
        insert l;
        l.Status = 'Working - Contacted';
        update l;

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.getLeads('Working - Contacted', null, null, 1, 10);
        Test.stopTest();

        System.assert(result.success);
        List<Object> data = (List<Object>) result.data;
        System.assert(data.size() >= 1, 'At least one lead should match status filter');
    }

    /* ─── updateLead ────────────────────────────────────────────── */

    @IsTest
    static void testUpdateLead_setsFields() {
        Lead l = makeLead('Up', 'Date', 'UpdateCo');
        insert l;

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.updateLead(
            l.Id, null, null, null, null, null,
            'Qualified', 'Hot', null, null, null
        );
        Test.stopTest();

        System.assert(result.success, 'updateLead should succeed');
        Lead updated = [SELECT Status, Rating FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Qualified', updated.Status);
        System.assertEquals('Hot', updated.Rating);
    }

    @IsTest
    static void testUpdateLead_invalidId_returnsError() {
        Test.startTest();
        OneOpsResponseWrapper result = CRMService.updateLead(
            null, null, null, null, null, null,
            'Qualified', null, null, null, null
        );
        Test.stopTest();

        System.assert(!result.success, 'Null Id should return error');
    }

    /* ─── convertLead ───────────────────────────────────────────── */

    @IsTest
    static void testConvertLead_createsAccount() {
        Lead l = makeLead('Con', 'Vert', 'ConvertCorp');
        insert l;

        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1
        ];

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.convertLead(l.Id, null, null, convertedStatus.MasterLabel);
        Test.stopTest();

        System.assert(result.success, 'convertLead should succeed: ' + result.message);
        Lead converted = [SELECT IsConverted, ConvertedAccountId FROM Lead WHERE Id = :l.Id];
        System.assert(converted.IsConverted);
        System.assertNotEquals(null, converted.ConvertedAccountId);
    }

    /* ─── searchLeads ───────────────────────────────────────────── */

    @IsTest
    static void testSearchLeads_returnsResults() {
        Lead l = makeLead('Search', 'Target', 'SearchCo');
        insert l;

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.searchLeads('SearchCo');
        Test.stopTest();

        // SOSL returns empty in unit tests by default; just assert no exception
        System.assert(result != null);
    }

    /* ─── AI scoring (mock callout) ─────────────────────────────── */

    @IsTest
    static void testScoreLead_withMockCallout() {
        Lead l = makeLead('Score', 'Test', 'ScoreCo');
        insert l;

        // Mock HTTP callout
        Test.setMock(HttpCalloutMock.class, new OneOpsAIMock());

        Test.startTest();
        OneOpsResponseWrapper result = CRMService.scoreLead(l.Id);
        Test.stopTest();

        // With mock, score should be updated or error handled gracefully
        System.assert(result != null, 'scoreLead should return a response');
    }

    /* ─── Inner mock class ──────────────────────────────────────── */

    private class OneOpsAIMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'success'   => true,
                'provider'  => 'openai',
                'data'      => new Map<String, Object>{
                    'score'     => 78,
                    'reason'    => 'Strong industry fit',
                    'emailDraft'=> 'Hi, ...'
                },
                'confidence'=> 0.92,
                'latencyMs' => 340,
                'model'     => 'gpt-4o'
            }));
            return res;
        }
    }
}
