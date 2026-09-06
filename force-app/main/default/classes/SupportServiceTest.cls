@IsTest
private class SupportServiceTest {

    private static Account makeAccount() {
        Account a = new Account(Name = 'Test Account');
        insert a;
        return a;
    }

    private static Support_Ticket__c makeTicket(Id accountId, String priority) {
        return new Support_Ticket__c(
            Subject__c    = 'Test Ticket',
            Description__c = 'This is a test support ticket',
            Priority__c   = priority,
            Category__c   = 'Technical',
            Account__c    = accountId
        );
    }

    /* ─── createTicket ───────────────────────────────────────────── */

    @IsTest
    static void testCreateTicket_setsSLADueDate() {
        Account acct = makeAccount();

        Test.startTest();
        OneOpsResponseWrapper result = SupportService.createTicket(
            'Login issue', 'Cannot log in after password reset', 'High', 'Technical', acct.Id
        );
        Test.stopTest();

        System.assert(result.success, 'createTicket should succeed');
        Support_Ticket__c t = [SELECT SLA_Due_Date__c, Status__c FROM Support_Ticket__c WHERE Account__c = :acct.Id LIMIT 1];
        System.assertNotEquals(null, t.SLA_Due_Date__c, 'SLA due date should be set');
        System.assertEquals('New', t.Status__c);
    }

    @IsTest
    static void testCreateTicket_criticalPriorityShortSLA() {
        Account acct = makeAccount();

        Test.startTest();
        OneOpsResponseWrapper result = SupportService.createTicket(
            'System down', 'Production is completely unavailable', 'Critical', 'Technical', acct.Id
        );
        Test.stopTest();

        System.assert(result.success);
        Support_Ticket__c t = [SELECT SLA_Due_Date__c, CreatedDate FROM Support_Ticket__c WHERE Account__c = :acct.Id LIMIT 1];
        // Critical SLA = 4 hours; due date should be well within 24 hours
        Decimal hoursUntilDue = (t.SLA_Due_Date__c.getTime() - Datetime.now().getTime()) / 3600000.0;
        System.assert(hoursUntilDue <= 5, 'Critical ticket SLA should be <= 5 hours from now');
    }

    /* ─── resolveTicket ──────────────────────────────────────────── */

    @IsTest
    static void testResolveTicket_setsResolvedDate() {
        Account acct = makeAccount();
        Support_Ticket__c t = makeTicket(acct.Id, 'Medium');
        insert t;

        Test.startTest();
        OneOpsResponseWrapper result = SupportService.resolveTicket(t.Id, 'Resolved by rebooting the service.');
        Test.stopTest();

        System.assert(result.success);
        Support_Ticket__c resolved = [SELECT Status__c, Resolved_Date__c FROM Support_Ticket__c WHERE Id = :t.Id];
        System.assertEquals('Resolved', resolved.Status__c);
        System.assertNotEquals(null, resolved.Resolved_Date__c);
    }

    /* ─── addComment ─────────────────────────────────────────────── */

    @IsTest
    static void testAddComment_setsFirstResponseDate() {
        Account acct = makeAccount();
        Support_Ticket__c t = makeTicket(acct.Id, 'Low');
        insert t;

        Test.startTest();
        OneOpsResponseWrapper result = SupportService.addComment(t.Id, 'We are investigating this issue.', false);
        Test.stopTest();

        System.assert(result.success);
        Support_Ticket__c updated = [SELECT First_Response_Date__c FROM Support_Ticket__c WHERE Id = :t.Id];
        System.assertNotEquals(null, updated.First_Response_Date__c, 'First response date should be set');
    }

    /* ─── getSLAMetrics ──────────────────────────────────────────── */

    @IsTest
    static void testGetSLAMetrics_returnsMap() {
        Account acct = makeAccount();
        Support_Ticket__c t = makeTicket(acct.Id, 'High');
        insert t;

        Test.startTest();
        OneOpsResponseWrapper result = SupportService.getSLAMetrics();
        Test.stopTest();

        System.assert(result.success);
        Map<String, Object> data = (Map<String, Object>) result.data;
        System.assert(data.containsKey('openTickets'));
        System.assert(data.containsKey('slaCompliance'));
    }
}
