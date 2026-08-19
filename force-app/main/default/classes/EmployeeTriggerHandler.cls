public with sharing class EmployeeTriggerHandler {

    /* ─── Before Insert ──────────────────────────────────────────── */

    public void onBeforeInsert(List<Employee__c> newList) {
        for (Employee__c emp : newList) {
            if (emp.Status__c == null)           emp.Status__c = 'Active';
            if (emp.Annual_Leave_Balance__c == null) emp.Annual_Leave_Balance__c = 20;
            if (emp.Sick_Leave_Balance__c == null)   emp.Sick_Leave_Balance__c   = 10;
        }
    }

    /* ─── Before Update ──────────────────────────────────────────── */

    public void onBeforeUpdate(List<Employee__c> newList, Map<Id, Employee__c> oldMap) {
        for (Employee__c emp : newList) {
            Employee__c old = oldMap.get(emp.Id);
            // Stamp termination date when status changes to Terminated
            if (emp.Status__c != old.Status__c && emp.Status__c == 'Terminated') {
                emp.End_Date__c = Date.today();
            }
        }
    }

    /* ─── After Insert ───────────────────────────────────────────── */

    public void onAfterInsert(List<Employee__c> newList) {
        updateDeptHeadcounts(newList, null);
        notifyNewHire(newList);
    }

    /* ─── After Update ───────────────────────────────────────────── */

    public void onAfterUpdate(List<Employee__c> newList, Map<Id, Employee__c> oldMap) {
        List<Employee__c> deptChanges     = new List<Employee__c>();
        List<Employee__c> terminated      = new List<Employee__c>();

        for (Employee__c emp : newList) {
            Employee__c old = oldMap.get(emp.Id);
            if (emp.Department__c != old.Department__c) deptChanges.add(emp);
            if (emp.Status__c == 'Terminated' && old.Status__c != 'Terminated') terminated.add(emp);
        }

        if (!deptChanges.isEmpty()) updateDeptHeadcounts(deptChanges, oldMap);
        if (!terminated.isEmpty())  logTerminations(terminated);
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private void updateDeptHeadcounts(List<Employee__c> emps, Map<Id, Employee__c> oldMap) {
        Set<Id> deptIds = new Set<Id>();
        for (Employee__c emp : emps) {
            if (emp.Department__c != null) deptIds.add(emp.Department__c);
            if (oldMap != null) {
                Employee__c old = oldMap.get(emp.Id);
                if (old.Department__c != null) deptIds.add(old.Department__c);
            }
        }
        if (deptIds.isEmpty()) return;

        Map<Id, AggregateResult> counts = new Map<Id, AggregateResult>();
        for (AggregateResult ar : [
            SELECT Department__c deptId, COUNT(Id) cnt
            FROM Employee__c
            WHERE Department__c IN :deptIds AND Status__c = 'Active'
            WITH USER_MODE
            GROUP BY Department__c
        ]) {
            counts.put((Id) ar.get('deptId'), ar);
        }

        List<Department__c> toUpdate = new List<Department__c>();
        for (Id deptId : deptIds) {
            Integer headcount = counts.containsKey(deptId)
                ? Integer.valueOf(counts.get(deptId).get('cnt'))
                : 0;
            toUpdate.add(new Department__c(Id = deptId, Headcount__c = headcount));
        }
        if (!toUpdate.isEmpty()) Database.update(toUpdate, false);
    }

    private void notifyNewHire(List<Employee__c> emps) {
        for (Employee__c emp : emps) {
            OneOpsLogger.audit('EmployeeTrigger', 'New employee onboarded: ' + emp.Employee_ID__c);
        }
    }

    private void logTerminations(List<Employee__c> emps) {
        for (Employee__c emp : emps) {
            OneOpsLogger.audit('EmployeeTrigger', 'Employee terminated: ' + emp.Employee_ID__c);
        }
    }
}
