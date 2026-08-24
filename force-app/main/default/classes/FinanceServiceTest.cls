@IsTest
private class FinanceServiceTest {

    private static Account makeAccount() {
        Account a = new Account(Name = 'Finance Test Account', BillingCity = 'San Francisco');
        insert a;
        return a;
    }

    /* ─── createInvoice ──────────────────────────────────────────── */

    @IsTest
    static void testCreateInvoice_happyPath() {
        Account acct = makeAccount();

        List<Map<String, Object>> lines = new List<Map<String, Object>>{
            new Map<String, Object>{ 'description' => 'Consulting', 'quantity' => 10, 'unitPrice' => 150 },
            new Map<String, Object>{ 'description' => 'Support',    'quantity' => 5,  'unitPrice' => 100 }
        };

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.createInvoice(
            acct.Id, Date.today().addDays(30), lines
        );
        Test.stopTest();

        System.assert(result.success, 'createInvoice should succeed');
        List<Invoice__c> invoices = [SELECT Total_Amount__c, Status__c FROM Invoice__c WHERE Account__c = :acct.Id];
        System.assert(!invoices.isEmpty());
        System.assertEquals('Draft', invoices[0].Status__c);
        System.assertEquals(2000, invoices[0].Total_Amount__c);
    }

    @IsTest
    static void testCreateInvoice_noLines_returnsError() {
        Account acct = makeAccount();

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.createInvoice(
            acct.Id, Date.today().addDays(30), new List<Map<String, Object>>()
        );
        Test.stopTest();

        System.assert(!result.success, 'createInvoice with no lines should fail');
    }

    /* ─── recordPayment ──────────────────────────────────────────── */

    @IsTest
    static void testRecordPayment_fullPayment_marksInvoicePaid() {
        Account acct = makeAccount();
        Invoice__c inv = new Invoice__c(
            Account__c  = acct.Id,
            Due_Date__c = Date.today().addDays(30),
            Status__c   = 'Sent',
            Total_Amount__c = 1500
        );
        insert inv;

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.recordPayment(
            inv.Id, 1500, 'Bank Transfer', 'REF-001'
        );
        Test.stopTest();

        System.assert(result.success, 'recordPayment should succeed');
        Invoice__c updated = [SELECT Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Paid', updated.Status__c);
    }

    @IsTest
    static void testRecordPayment_partialPayment_marksPartiallyPaid() {
        Account acct = makeAccount();
        Invoice__c inv = new Invoice__c(
            Account__c  = acct.Id,
            Due_Date__c = Date.today().addDays(30),
            Status__c   = 'Sent',
            Total_Amount__c = 2000
        );
        insert inv;

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.recordPayment(
            inv.Id, 500, 'Credit Card', 'REF-002'
        );
        Test.stopTest();

        System.assert(result.success);
        Invoice__c updated = [SELECT Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Partially Paid', updated.Status__c);
    }

    /* ─── getBudgetStatus ────────────────────────────────────────── */

    @IsTest
    static void testGetBudgetStatus_returnsData() {
        Budget__c budget = new Budget__c(
            Name             = 'Q1 Budget',
            Department__c    = 'Engineering',
            Fiscal_Year__c   = '2026',
            Total_Budget__c  = 100000,
            Spent_Amount__c  = 40000
        );
        insert budget;

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.getBudgetStatus(null, null);
        Test.stopTest();

        System.assert(result.success);
        List<Object> budgets = (List<Object>) result.data;
        System.assert(budgets.size() >= 1);
    }

    /* ─── getRevenueAnalytics ────────────────────────────────────── */

    @IsTest
    static void testGetRevenueAnalytics_returnsMonthBreakdown() {
        Account acct = makeAccount();
        Invoice__c inv = new Invoice__c(
            Account__c      = acct.Id,
            Due_Date__c     = Date.today(),
            Status__c       = 'Paid',
            Total_Amount__c = 5000
        );
        insert inv;

        Test.startTest();
        OneOpsResponseWrapper result = FinanceService.getRevenueAnalytics(
            Date.today().toStartOfMonth(), Date.today().addDays(1)
        );
        Test.stopTest();

        System.assert(result.success);
    }
}
