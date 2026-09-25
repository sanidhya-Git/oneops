/**
 * Centralised logging for OneOps AI.
 * - DEBUG/INFO go to the Apex debug log only.
 * - ERROR/CRITICAL are persisted to Audit_Log__c for support and compliance.
 * - AUDIT writes a structured action record for every significant data change.
 * Uses without sharing so log writes always succeed regardless of user context.
 */
public without sharing class OneOpsLogger {

    public enum Level { DEBUG_LVL, INFO, WARN, ERROR, CRITICAL }

    private static List<Audit_Log__c> buffer = new List<Audit_Log__c>();
    private static Boolean batchMode = false;

    // ── Public API ─────────────────────────────────────────────────────────

    public static void debug(String module, String message) {
        emit(Level.DEBUG_LVL, module, message, null);
    }

    public static void info(String module, String message) {
        emit(Level.INFO, module, message, null);
    }

    public static void warn(String module, String message) {
        emit(Level.WARN, module, message, null);
    }

    public static void error(String module, String message, Exception ex) {
        emit(Level.ERROR, module, message, ex);
    }

    public static void critical(String module, String message, Exception ex) {
        emit(Level.CRITICAL, module, message, ex);
    }

    /**
     * Write a structured audit record — every create/update/delete of
     * business data should call this so compliance queries work.
     */
    public static void audit(
        String module,
        String action,
        Id     recordId,
        String objectType,
        String details
    ) {
        Audit_Log__c log = new Audit_Log__c(
            Module__c      = module.left(50),
            Action__c      = action.left(100),
            Record_ID__c   = recordId != null ? String.valueOf(recordId) : null,
            Object_Type__c = objectType != null ? objectType.left(100) : null,
            Details__c     = details,
            User__c        = UserInfo.getUserId(),
            Level__c       = 'AUDIT',
            Timestamp__c   = DateTime.now()
        );
        buffer.add(log);
        if (!batchMode) flush();
    }

    // ── Batch Mode (call in Batch/Queueable to group inserts) ─────────────

    public static void enableBatchMode() {
        batchMode = true;
    }

    public static void flush() {
        if (buffer.isEmpty()) return;
        List<Audit_Log__c> toInsert = buffer.clone();
        buffer.clear();
        try {
            Database.insert(toInsert, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[OneOpsLogger.flush] Failed: ' + ex.getMessage());
        }
    }

    // ── Internal ───────────────────────────────────────────────────────────

    private static void emit(Level level, String module, String message, Exception ex) {
        String prefix = '[OneOps][' + level.name() + '][' + module + '] ';
        String fullMsg = ex != null
            ? message + ' | Exception: ' + ex.getMessage()
            : message;

        System.debug(LoggingLevel.DEBUG, prefix + fullMsg);

        if (level == Level.ERROR || level == Level.CRITICAL) {
            Audit_Log__c log = new Audit_Log__c(
                Module__c      = module.left(50),
                Action__c      = 'SYSTEM_LOG',
                Details__c     = fullMsg.left(131072),
                Stack_Trace__c = ex != null ? ex.getStackTraceString().left(131072) : null,
                User__c        = UserInfo.getUserId(),
                Level__c       = level.name(),
                Timestamp__c   = DateTime.now()
            );
            buffer.add(log);
            if (!batchMode) flush();
        }
    }
}
