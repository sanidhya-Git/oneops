/**
 * Base REST class — shared auth, JSON response serialization, and request parsing.
 * All REST controllers extend this class.
 */
global abstract with sharing class OneOpsRestBase {

    protected static final String CONTENT_TYPE_JSON = 'application/json';

    // ── Auth Helper ────────────────────────────────────────────────────────

    protected static void requirePermission(String permSetName) {
        if (!OneopsSecurity.hasPermissionSet(permSetName)) {
            sendError(403, OneOpsException.ERR_FORBIDDEN, 'Insufficient permissions.');
        }
    }

    // ── Response Helpers ───────────────────────────────────────────────────

    protected static void sendSuccess(OneOpsResponseWrapper wrapper) {
        RestContext.response.statusCode    = wrapper.statusCode;
        RestContext.response.addHeader('Content-Type', CONTENT_TYPE_JSON);
        RestContext.response.responseBody  = Blob.valueOf(wrapper.toJson());
    }

    protected static void sendError(Integer status, String errorCode, String message) {
        RestContext.response.statusCode   = status;
        RestContext.response.addHeader('Content-Type', CONTENT_TYPE_JSON);
        RestContext.response.responseBody = Blob.valueOf(
            OneOpsResponseWrapper.error(message, errorCode, status).toJson()
        );
    }

    // ── Request Parsing ────────────────────────────────────────────────────

    protected static Map<String, Object> parseBody() {
        try {
            if (RestContext.request.requestBody == null) return new Map<String, Object>();
            String body = RestContext.request.requestBody.toString();
            if (String.isBlank(body)) return new Map<String, Object>();
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception ex) {
            sendError(400, OneOpsException.ERR_VALIDATION, 'Invalid JSON request body.');
            return null;
        }
    }

    protected static String getPathParam(String paramName) {
        return RestContext.request.requestURI
            .substringAfterLast('/' + paramName + '/')
            .substringBefore('/');
    }

    protected static String getQueryParam(String name) {
        return RestContext.request.params.get(name);
    }

    protected static Integer getIntParam(String name, Integer defaultVal) {
        String v = RestContext.request.params.get(name);
        return String.isNotBlank(v) ? Integer.valueOf(v) : defaultVal;
    }

    protected static Id getIdParam(String name) {
        String v = RestContext.request.params.get(name);
        if (String.isBlank(v)) return null;
        try { return (Id) v; } catch (Exception ex) { return null; }
    }
}
