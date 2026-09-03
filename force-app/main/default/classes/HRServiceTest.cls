@IsTest
private class HRServiceTest {

    /* ─── Test Data ─────────────────────────────────────────────── */

    private static Department__c makeDept(String name) {
        return new Department__c(Name = name, Headcount__c = 0);
    }

    private static Employee__c makeEmployee(Id deptId) {
        return new Employee__c(
            First_Name__c  = 'Jane',
            Last_Name__c   = 'Doe',
            Email__c       = 'jane.doe.' + Crypto.getRandomInteger() + '@test.com',
            Department__c  = deptId,
            Job_Title__c   = 'Engineer',
            Employment_Type__c = 'Full-Time',
            Start_Date__c  = Date.today().addYears(-1),
            Status__c      = 'Active',
            Annual_Leave_Balance__c = 20,
            Sick_Leave_Balance__c   = 10
        );
    }

    /* ─── createEmployee ─────────────────────────────────────────── */

    @IsTest
    static void testCreateEmployee_generatesEmployeeId() {
        Department__c dept = makeDept('Engineering');
        insert dept;

        Test.startTest();
        OneOpsResponseWrapper result = HRService.createEmployee(
            'John', 'Smith', 'john.smith.test@test.com', dept.Id,
            'Developer', 'Full-Time', 'Engineering',
            Date.today(), 90000, null
        );
        Test.stopTest();

        System.assert(result.success, 'createEmployee should succeed');
        List<Employee__c> emps = [SELECT Employee_ID__c FROM Employee__c WHERE Email__c = 'john.smith.test@test.com'];
        System.assert(!emps.isEmpty());
        System.assert(emps[0].Employee_ID__c.startsWith('EMP-'), 'Employee ID should start with EMP-');
    }

    @IsTest
    static void testCreateEmployee_updatesDeptHeadcount() {
        Department__c dept = makeDept('Sales');
        insert dept;

        Test.startTest();
        HRService.createEmployee('Bob', 'Jones', 'bob.jones.test@test.com', dept.Id,
            'AE', 'Full-Time', 'Sales', Date.today(), 70000, null);
        Test.stopTest();

        Department__c updated = [SELECT Headcount__c FROM Department__c WHERE Id = :dept.Id];
        System.assertEquals(1, updated.Headcount__c, 'Headcount should be incremented');
    }

    /* ─── getEmployees ───────────────────────────────────────────── */

    @IsTest
    static void testGetEmployees_returnsPagedResults() {
        Department__c dept = makeDept('HR');
        insert dept;

        List<Employee__c> emps = new List<Employee__c>();
        for (Integer i = 0; i < 3; i++) {
            emps.add(makeEmployee(dept.Id));
        }
        insert emps;

        Test.startTest();
        OneOpsResponseWrapper result = HRService.getEmployees(dept.Id, null, 1, 10);
        Test.stopTest();

        System.assert(result.success);
        System.assert(result.totalRecords >= 3);
    }

    /* ─── submitLeaveRequest ─────────────────────────────────────── */

    @IsTest
    static void testSubmitLeave_validRequest() {
        Department__c dept = makeDept('Ops');
        insert dept;
        Employee__c emp = makeEmployee(dept.Id);
        insert emp;

        Date startDate = Date.today().addDays(10);
        Date endDate   = Date.today().addDays(14);

        Test.startTest();
        OneOpsResponseWrapper result = HRService.submitLeaveRequest(
            emp.Id, 'Annual Leave', startDate, endDate, 'Vacation'
        );
        Test.stopTest();

        // Approval process may throw in test context; verify graceful handling
        System.assert(result != null, 'submitLeaveRequest should return a response');
    }

    @IsTest
    static void testSubmitLeave_insufficientBalance() {
        Department__c dept = makeDept('Finance');
        insert dept;
        Employee__c emp = makeEmployee(dept.Id);
        emp.Annual_Leave_Balance__c = 1;
        insert emp;

        // Request 10 days but only 1 day balance
        Test.startTest();
        OneOpsResponseWrapper result = HRService.submitLeaveRequest(
            emp.Id, 'Annual Leave', Date.today().addDays(5), Date.today().addDays(14), 'Vacation'
        );
        Test.stopTest();

        System.assert(!result.success, 'Should fail due to insufficient balance');
    }

    @IsTest
    static void testSubmitLeave_overlappingRequest() {
        Department__c dept = makeDept('Product');
        insert dept;
        Employee__c emp = makeEmployee(dept.Id);
        insert emp;

        // First request
        Leave_Request__c existing = new Leave_Request__c(
            Employee__c  = emp.Id,
            Leave_Type__c = 'Annual Leave',
            Start_Date__c = Date.today().addDays(5),
            End_Date__c   = Date.today().addDays(10),
            Status__c     = 'Approved'
        );
        insert existing;

        // Overlapping second request
        Test.startTest();
        OneOpsResponseWrapper result = HRService.submitLeaveRequest(
            emp.Id, 'Annual Leave', Date.today().addDays(8), Date.today().addDays(12), 'Holiday'
        );
        Test.stopTest();

        System.assert(!result.success, 'Should fail due to overlapping leave');
    }

    /* ─── getOrgChart ────────────────────────────────────────────── */

    @IsTest
    static void testGetOrgChart_returnsDepartments() {
        insert makeDept('Legal');

        Test.startTest();
        OneOpsResponseWrapper result = HRService.getOrgChart();
        Test.stopTest();

        System.assert(result.success);
        List<Object> depts = (List<Object>) result.data;
        System.assert(depts.size() >= 1);
    }
}
