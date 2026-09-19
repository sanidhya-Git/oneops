/**
 * Security utility layer for OneOps AI.
 * Wraps Salesforce CRUD/FLS checks, permission set queries,
 * and input sanitisation. Called from every service before DML.
 *
 * Using `with sharing` so Sharing Rules are respected.
 */
public with sharing class OneopsSecurity {

    // ── Object-Level CRUD ──────────────────────────────────────────────────

    public static void requireCreate(Schema.SObjectType obj) {
        if (!obj.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
            throw OneOpsException.unauthorized(
                'Insufficient privileges to create ' +
                obj.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel() + ' records.'
            );
        }
    }

    public static void requireRead(Schema.SObjectType obj) {
        if (!obj.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            throw OneOpsException.unauthorized(
                'Insufficient privileges to read ' +
                obj.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel() + ' records.'
            );
        }
    }

    public static void requireUpdate(Schema.SObjectType obj) {
        if (!obj.getDescribe(SObjectDescribeOptions.DEFERRED).isUpdateable()) {
            throw OneOpsException.unauthorized(
                'Insufficient privileges to update ' +
                obj.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel() + ' records.'
            );
        }
    }

    public static void requireDelete(Schema.SObjectType obj) {
        if (!obj.getDescribe(SObjectDescribeOptions.DEFERRED).isDeletable()) {
            throw OneOpsException.unauthorized(
                'Insufficient privileges to delete ' +
                obj.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel() + ' records.'
            );
        }
    }

    // ── Field-Level Security ───────────────────────────────────────────────

    /**
     * Returns only the field names from the provided list that the current
     * user can read. Used to build dynamic SOQL safely.
     */
    public static List<String> accessibleFields(Schema.SObjectType obj, List<String> fieldNames) {
        Map<String, Schema.SObjectField> fieldMap =
            obj.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
        List<String> accessible = new List<String>();
        for (String f : fieldNames) {
            Schema.SObjectField field = fieldMap.get(f.toLowerCase());
            if (field != null && field.getDescribe().isAccessible()) {
                accessible.add(f);
            }
        }
        return accessible;
    }

    public static void requireFieldWrite(Schema.SObjectType obj, List<String> fieldNames) {
        Map<String, Schema.SObjectField> fieldMap =
            obj.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
        List<String> blocked = new List<String>();
        for (String f : fieldNames) {
            Schema.SObjectField field = fieldMap.get(f.toLowerCase());
            if (field == null || !field.getDescribe().isUpdateable()) {
                blocked.add(f);
            }
        }
        if (!blocked.isEmpty()) {
            throw OneOpsException.unauthorized(
                'No write access to fields: ' + String.join(blocked, ', ')
            );
        }
    }

    // ── stripInaccessible helpers ──────────────────────────────────────────

    public static SObject strip(SObject record, AccessType mode) {
        SObjectAccessDecision decision =
            Security.stripInaccessible(mode, new List<SObject>{ record });
        List<SObject> stripped = decision.getRecords();
        return stripped.isEmpty() ? null : stripped[0];
    }

    public static List<SObject> stripList(List<SObject> records, AccessType mode) {
        if (records == null || records.isEmpty()) return records;
        return Security.stripInaccessible(mode, records).getRecords();
    }

    // ── Permission Sets ────────────────────────────────────────────────────

    public static Boolean hasPermissionSet(String permSetName) {
        return ![
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND   PermissionSet.Name = :permSetName
            WITH  USER_MODE
            LIMIT 1
        ].isEmpty();
    }

    public static void requirePermissionSet(String permSetName) {
        if (!hasPermissionSet(permSetName)) {
            throw OneOpsException.forbidden('Permission Set: ' + permSetName);
        }
    }

    // ── Input Sanitisation ─────────────────────────────────────────────────

    /**
     * Escapes single quotes to prevent SOQL injection.
     * Always call this before interpolating user input into a SOQL string.
     */
    public static String sanitise(String input) {
        if (String.isBlank(input)) return input;
        return String.escapeSingleQuotes(input.trim());
    }

    public static Boolean isOwner(Id ownerId) {
        return ownerId == UserInfo.getUserId();
    }

    // ── Utility ────────────────────────────────────────────────────────────

    public static Boolean isAdmin() {
        List<User> u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
        return !u.isEmpty() && u[0].Profile.Name == 'System Administrator';
    }
}
