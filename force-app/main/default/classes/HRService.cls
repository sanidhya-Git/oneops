/**
 * HR Service — Employee management, department operations, and leave workflow.
 * Handles all business logic for the HR module.
 */
public with sharing class HRService {

    private static final String MODULE = OneOpsConstants.MODULE_HR;

    // ── Employee Management ────────────────────────────────────────────────

    public static OneOpsResponseWrapper getEmployees(Integer pageNum, Integer pageSize, String statusFilter, String deptId) {
        try {
            OneopsSecurity.requireRead(Employee__c.SObjectType);

            Integer offset = (pageNum - 1) * pageSize;
            String baseQuery =
                'SELECT Id, Name, Employee_ID__c, Job_Title__c, Department__c, Department__r.Name, ' +
                '       Manager__c, Manager__r.Name, Employment_Status__c, Employment_Type__c, ' +
                '       Work_Email__c, Phone__c, Office_Location__c, AI_Performance_Score__c, ' +
                '       Annual_Leave_Balance__c, Sick_Leave_Balance__c, Date_of_Joining__c, Photo_URL__c ' +
                'FROM Employee__c WHERE Id != null ';

            if (String.isNotBlank(statusFilter)) {
                baseQuery += 'AND Employment_Status__c = \'' + OneopsSecurity.sanitise(statusFilter) + '\' ';
            }
            if (String.isNotBlank(deptId)) {
                baseQuery += 'AND Department__c = \'' + OneopsSecurity.sanitise(deptId) + '\' ';
            }

            baseQuery += 'ORDER BY Name ASC LIMIT :pageSize OFFSET :offset';
            List<Employee__c> employees = Database.query(baseQuery);

            String countQ = 'SELECT COUNT() FROM Employee__c WHERE Id != null';
            if (String.isNotBlank(statusFilter)) countQ += ' AND Employment_Status__c = \'' + OneopsSecurity.sanitise(statusFilter) + '\'';
            Integer total = Database.countQuery(countQ);

            return OneOpsResponseWrapper.paginated(employees, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'getEmployees failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getEmployeeById(Id empId) {
        try {
            OneopsSecurity.requireRead(Employee__c.SObjectType);
            List<Employee__c> emps = [
                SELECT Id, Name, Employee_ID__c, Job_Title__c,
                       Department__c, Department__r.Name,
                       Manager__c, Manager__r.Name,
                       Salesforce_User__c,
                       Employment_Status__c, Employment_Type__c,
                       Work_Email__c, Personal_Email__c, Phone__c,
                       Annual_Salary__c, Annual_Leave_Balance__c, Sick_Leave_Balance__c,
                       Office_Location__c, Skills__c, AI_Performance_Score__c,
                       Date_of_Joining__c, Date_of_Birth__c,
                       LinkedIn_URL__c, Photo_URL__c,
                       Emergency_Contact_Name__c, Emergency_Contact_Phone__c
                FROM Employee__c WHERE Id = :empId WITH USER_MODE LIMIT 1
            ];
            if (emps.isEmpty()) throw OneOpsException.notFound('Employee', empId);

            // Fetch direct reports count
            Integer directReports = [SELECT COUNT() FROM Employee__c WHERE Manager__c = :empId WITH USER_MODE];

            Map<String, Object> result = new Map<String, Object>{
                'employee'      => emps[0],
                'directReports' => directReports
            };

            return OneOpsResponseWrapper.ok(result).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'getEmployeeById failed for ' + empId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper createEmployee(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Employee__c.SObjectType);
            validateEmployeeFields(fields);

            // Ensure unique employee ID
            String empId = generateEmployeeId();

            Employee__c emp = new Employee__c(
                FirstName            = (String)  fields.get('firstName'),
                LastName             = (String)  fields.get('lastName'),
                Employee_ID__c       = empId,
                Job_Title__c         = (String)  fields.get('jobTitle'),
                Department__c        = (Id)      fields.get('departmentId'),
                Manager__c           = (Id)      fields.get('managerId'),
                Work_Email__c        = (String)  fields.get('workEmail'),
                Employment_Status__c = OneOpsConstants.STATUS_ACTIVE,
                Employment_Type__c   = (String)  fields.get('employmentType'),
                Date_of_Joining__c   = Date.valueOf((String) fields.get('dateOfJoining')),
                Office_Location__c   = (String)  fields.get('officeLocation')
            );

            if (fields.containsKey('salary')) {
                emp.Annual_Salary__c = Decimal.valueOf(String.valueOf(fields.get('salary')));
            }

            insert emp;

            // Update department headcount
            if (emp.Department__c != null) updateDepartmentHeadcount(emp.Department__c);

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, emp.Id, 'Employee__c',
                'Employee created: ' + emp.Name + ' (ID: ' + empId + ')');

            return OneOpsResponseWrapper.created(emp).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createEmployee failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        } catch (DmlException ex) {
            if (ex.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                return OneOpsResponseWrapper.error(
                    'An employee with this email already exists.',
                    OneOpsException.ERR_DUPLICATE, 409
                );
            }
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Leave Management ───────────────────────────────────────────────────

    public static OneOpsResponseWrapper submitLeaveRequest(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Leave_Request__c.SObjectType);

            Id empId = (Id) fields.get('employeeId');
            Date startDate = Date.valueOf((String) fields.get('startDate'));
            Date endDate   = Date.valueOf((String) fields.get('endDate'));
            String leaveType = (String) fields.get('leaveType');

            if (startDate > endDate) {
                throw OneOpsException.validation('endDate', 'End date must be on or after start date.');
            }
            if (startDate < Date.today()) {
                throw OneOpsException.validation('startDate', 'Cannot request leave in the past.');
            }

            // Check leave balance
            checkLeaveBalance(empId, leaveType, startDate, endDate);

            // Check for overlapping requests
            checkLeaveOverlap(empId, startDate, endDate);

            Leave_Request__c req = new Leave_Request__c(
                Employee__c  = empId,
                Leave_Type__c = leaveType,
                Start_Date__c = startDate,
                End_Date__c   = endDate,
                Reason__c     = (String) fields.get('reason'),
                Status__c     = OneOpsConstants.STATUS_PENDING,
                Is_Half_Day__c = fields.containsKey('isHalfDay') && (Boolean) fields.get('isHalfDay')
            );

            insert req;

            // Trigger approval process via Approval.process
            Approval.ProcessSubmitRequest approvalReq = new Approval.ProcessSubmitRequest();
            approvalReq.setObjectId(req.Id);
            approvalReq.setSubmitterId(UserInfo.getUserId());
            approvalReq.setComments('Leave request submitted by employee.');
            Approval.process(approvalReq);

            OneOpsLogger.audit(MODULE, 'LEAVE_SUBMIT', req.Id, 'Leave_Request__c',
                'Leave request: ' + leaveType + ' (' + startDate + ' to ' + endDate + ')');

            return OneOpsResponseWrapper.created(req).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'submitLeaveRequest failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getLeaveRequests(Id empId, String status) {
        try {
            OneopsSecurity.requireRead(Leave_Request__c.SObjectType);
            String q = 'SELECT Id, Name, Employee__c, Employee__r.Name, Leave_Type__c, ' +
                       'Start_Date__c, End_Date__c, Number_of_Days__c, Status__c, Reason__c, ' +
                       'Approved_By__c, Approved_Date__c, Rejection_Reason__c ' +
                       'FROM Leave_Request__c WHERE Id != null ';
            if (empId != null) q += 'AND Employee__c = \'' + empId + '\' ';
            if (String.isNotBlank(status)) q += 'AND Status__c = \'' + OneopsSecurity.sanitise(status) + '\' ';
            q += 'ORDER BY CreatedDate DESC LIMIT 200';

            return OneOpsResponseWrapper.ok(Database.query(q)).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getOrgChart(Id rootDeptId) {
        try {
            OneopsSecurity.requireRead(Department__c.SObjectType);
            List<Department__c> depts = [
                SELECT Id, Name, Department_Code__c, Parent_Department__c,
                       Head_of_Department__c, Head_of_Department__r.Name, Headcount__c
                FROM Department__c WHERE Is_Active__c = true WITH USER_MODE
                ORDER BY Name
            ];
            return OneOpsResponseWrapper.ok(depts).withModule(MODULE);
        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void validateEmployeeFields(Map<String, Object> fields) {
        if (String.isBlank((String) fields.get('lastName'))) {
            throw OneOpsException.validation('lastName', 'Last name is required.');
        }
        if (String.isBlank((String) fields.get('workEmail'))) {
            throw OneOpsException.validation('workEmail', 'Work email is required.');
        }
        if (String.isBlank((String) fields.get('jobTitle'))) {
            throw OneOpsException.validation('jobTitle', 'Job title is required.');
        }
        if (String.isBlank((String) fields.get('dateOfJoining'))) {
            throw OneOpsException.validation('dateOfJoining', 'Date of joining is required.');
        }
    }

    private static String generateEmployeeId() {
        Integer count = [SELECT COUNT() FROM Employee__c] + 1;
        return 'EMP-' + String.valueOf(count).leftPad(5, '0');
    }

    private static void checkLeaveBalance(Id empId, String leaveType, Date startDate, Date endDate) {
        List<Employee__c> emps = [
            SELECT Annual_Leave_Balance__c, Sick_Leave_Balance__c
            FROM Employee__c WHERE Id = :empId WITH USER_MODE LIMIT 1
        ];
        if (emps.isEmpty()) return;

        Integer days = startDate.daysBetween(endDate) + 1;
        Employee__c emp = emps[0];

        if (leaveType == 'Annual Leave' && (emp.Annual_Leave_Balance__c == null || emp.Annual_Leave_Balance__c < days)) {
            throw OneOpsException.validation('leaveType',
                'Insufficient annual leave balance. Available: ' + emp.Annual_Leave_Balance__c + ' days, Requested: ' + days + ' days.');
        }
        if (leaveType == 'Sick Leave' && (emp.Sick_Leave_Balance__c == null || emp.Sick_Leave_Balance__c < days)) {
            throw OneOpsException.validation('leaveType',
                'Insufficient sick leave balance. Available: ' + emp.Sick_Leave_Balance__c + ' days, Requested: ' + days + ' days.');
        }
    }

    private static void checkLeaveOverlap(Id empId, Date startDate, Date endDate) {
        List<Leave_Request__c> overlaps = [
            SELECT Id FROM Leave_Request__c
            WHERE Employee__c = :empId
            AND   Status__c IN ('Pending', 'Approved')
            AND   Start_Date__c <= :endDate
            AND   End_Date__c   >= :startDate
            WITH USER_MODE LIMIT 1
        ];
        if (!overlaps.isEmpty()) {
            throw OneOpsException.validation('startDate',
                'A leave request already exists for the selected date range.');
        }
    }

    private static void updateDepartmentHeadcount(Id deptId) {
        Integer count = [SELECT COUNT() FROM Employee__c WHERE Department__c = :deptId AND Employment_Status__c = 'Active'];
        update new Department__c(Id = deptId, Headcount__c = count);
    }
}
