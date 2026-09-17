/**
 * Standard API response envelope for all REST endpoints and LWC wire adapters.
 * Keeps every response consistent: same shape regardless of the module.
 */
public class OneOpsResponseWrapper {

    @AuraEnabled public Boolean success      { get; set; }
    @AuraEnabled public Object  data         { get; set; }
    @AuraEnabled public String  message      { get; set; }
    @AuraEnabled public String  errorCode    { get; set; }
    @AuraEnabled public Integer statusCode   { get; set; }
    @AuraEnabled public String  requestId    { get; set; }
    @AuraEnabled public Long    timestamp    { get; set; }

    // Pagination
    @AuraEnabled public Integer totalRecords { get; set; }
    @AuraEnabled public Integer pageSize     { get; set; }
    @AuraEnabled public Integer pageNumber   { get; set; }
    @AuraEnabled public Boolean hasMore      { get; set; }

    // Extensible metadata (module name, AI provider used, etc.)
    @AuraEnabled public Map<String, Object> meta { get; set; }

    private OneOpsResponseWrapper() {
        this.timestamp = DateTime.now().getTime();
        this.requestId = generateRequestId();
        this.meta      = new Map<String, Object>();
    }

    // ── Success Factories ──────────────────────────────────────────────────

    public static OneOpsResponseWrapper ok(Object data) {
        OneOpsResponseWrapper r = new OneOpsResponseWrapper();
        r.success    = true;
        r.data       = data;
        r.statusCode = 200;
        r.message    = 'Success';
        return r;
    }

    public static OneOpsResponseWrapper ok(Object data, String message) {
        OneOpsResponseWrapper r = ok(data);
        r.message = message;
        return r;
    }

    public static OneOpsResponseWrapper created(Object data) {
        OneOpsResponseWrapper r = new OneOpsResponseWrapper();
        r.success    = true;
        r.data       = data;
        r.statusCode = 201;
        r.message    = 'Record created successfully.';
        return r;
    }

    public static OneOpsResponseWrapper noContent() {
        OneOpsResponseWrapper r = new OneOpsResponseWrapper();
        r.success    = true;
        r.data       = null;
        r.statusCode = 204;
        r.message    = 'Operation completed.';
        return r;
    }

    public static OneOpsResponseWrapper paginated(
        Object  data,
        Integer total,
        Integer pageSize,
        Integer pageNumber
    ) {
        OneOpsResponseWrapper r = ok(data);
        r.totalRecords = total;
        r.pageSize     = pageSize;
        r.pageNumber   = pageNumber;
        r.hasMore      = (pageNumber * pageSize) < total;
        return r;
    }

    // ── Error Factories ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper error(String message, String errorCode, Integer statusCode) {
        OneOpsResponseWrapper r = new OneOpsResponseWrapper();
        r.success    = false;
        r.message    = message;
        r.errorCode  = errorCode;
        r.statusCode = statusCode;
        r.data       = null;
        return r;
    }

    public static OneOpsResponseWrapper fromException(OneOpsException ex) {
        return error(
            ex.getMessage(),
            ex.errorCode,
            ex.httpStatus != null ? ex.httpStatus : 500
        );
    }

    public static OneOpsResponseWrapper fromException(Exception ex) {
        return error(
            'An unexpected error occurred: ' + ex.getMessage(),
            OneOpsException.ERR_SYSTEM,
            500
        );
    }

    // ── Fluent Builder ─────────────────────────────────────────────────────

    public OneOpsResponseWrapper withMeta(String key, Object value) {
        this.meta.put(key, value);
        return this;
    }

    public OneOpsResponseWrapper withModule(String moduleName) {
        return withMeta('module', moduleName);
    }

    public OneOpsResponseWrapper withAIProvider(String providerName) {
        return withMeta('aiProvider', providerName);
    }

    // ── Serialization ──────────────────────────────────────────────────────

    public String toJson() {
        return JSON.serialize(this);
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static String generateRequestId() {
        // Deterministic prefix + timestamp for traceability
        return 'OOP-' + String.valueOf(DateTime.now().getTime()).right(10);
    }
}
