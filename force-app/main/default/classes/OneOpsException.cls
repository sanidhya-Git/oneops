/**
 * Typed exception hierarchy for OneOps AI.
 * Carry structured error codes, HTTP status codes, and module context
 * so REST controllers can respond consistently without additional mapping.
 */
public class OneOpsException extends Exception {

    public String  errorCode     { get; private set; }
    public String  module        { get; private set; }
    public String  context       { get; private set; }
    public Integer httpStatus    { get; private set; }

    // ── Standard Error Codes ───────────────────────────────────────────────
    public static final String ERR_VALIDATION   = 'VALIDATION_ERROR';
    public static final String ERR_NOT_FOUND    = 'RECORD_NOT_FOUND';
    public static final String ERR_UNAUTHORIZED = 'UNAUTHORIZED';
    public static final String ERR_FORBIDDEN    = 'FORBIDDEN';
    public static final String ERR_AI_FAILURE   = 'AI_ENGINE_FAILURE';
    public static final String ERR_CALLOUT      = 'CALLOUT_FAILURE';
    public static final String ERR_LIMIT        = 'GOVERNOR_LIMIT_EXCEEDED';
    public static final String ERR_DUPLICATE    = 'DUPLICATE_RECORD';
    public static final String ERR_WORKFLOW     = 'WORKFLOW_ERROR';
    public static final String ERR_DML          = 'DML_ERROR';
    public static final String ERR_SYSTEM       = 'INTERNAL_ERROR';

    // ── Primary Constructor ────────────────────────────────────────────────
    public OneOpsException(String message, String errorCode, String module, String context, Integer httpStatus) {
        this.setMessage(message);
        this.errorCode  = errorCode;
        this.module     = module;
        this.context    = context;
        this.httpStatus = httpStatus;
    }

    public OneOpsException(String message, String errorCode, String module) {
        this(message, errorCode, module, null, 400);
    }

    // ── Static Factory Methods ─────────────────────────────────────────────

    public static OneOpsException notFound(String objectType, Id recordId) {
        return new OneOpsException(
            objectType + ' with Id ' + recordId + ' was not found or you do not have access.',
            ERR_NOT_FOUND, 'SYSTEM',
            'SObjectType: ' + objectType + ', Id: ' + recordId,
            404
        );
    }

    public static OneOpsException notFound(String objectType, String queryParam) {
        return new OneOpsException(
            objectType + ' matching "' + queryParam + '" was not found.',
            ERR_NOT_FOUND, 'SYSTEM', null, 404
        );
    }

    public static OneOpsException unauthorized(String reason) {
        return new OneOpsException(reason, ERR_UNAUTHORIZED, 'SECURITY', null, 401);
    }

    public static OneOpsException forbidden(String resource) {
        return new OneOpsException(
            'You do not have permission to access: ' + resource,
            ERR_FORBIDDEN, 'SECURITY', 'Resource: ' + resource, 403
        );
    }

    public static OneOpsException validation(String fieldName, String reason) {
        return new OneOpsException(
            'Validation failed for field "' + fieldName + '": ' + reason,
            ERR_VALIDATION, 'VALIDATION',
            'Field: ' + fieldName,
            422
        );
    }

    public static OneOpsException validation(String reason) {
        return new OneOpsException(reason, ERR_VALIDATION, 'VALIDATION', null, 422);
    }

    public static OneOpsException aiFailure(String service, String reason) {
        return new OneOpsException(
            'AI Engine error in service "' + service + '": ' + reason,
            ERR_AI_FAILURE, OneOpsConstants.MODULE_AI,
            'Service: ' + service,
            503
        );
    }

    public static OneOpsException calloutFailure(String endpoint, Integer statusCode, String body) {
        return new OneOpsException(
            'External callout to ' + endpoint + ' returned status ' + statusCode + '.',
            ERR_CALLOUT, 'INTEGRATION',
            'Endpoint: ' + endpoint + ' | Status: ' + statusCode + ' | Body: ' + (body != null ? body.left(500) : 'null'),
            502
        );
    }

    public static OneOpsException duplicate(String objectType, String uniqueField, String value) {
        return new OneOpsException(
            'A ' + objectType + ' with ' + uniqueField + ' = "' + value + '" already exists.',
            ERR_DUPLICATE, 'SYSTEM',
            'Field: ' + uniqueField + ', Value: ' + value,
            409
        );
    }

    public static OneOpsException dmlError(List<Database.Error> errors) {
        List<String> msgs = new List<String>();
        for (Database.Error e : errors) {
            msgs.add(e.getStatusCode() + ': ' + e.getMessage());
        }
        return new OneOpsException(
            'DML operation failed: ' + String.join(msgs, '; '),
            ERR_DML, 'SYSTEM', null, 500
        );
    }

    public static OneOpsException system(String message, Exception cause) {
        OneOpsException ex = new OneOpsException(
            message + (cause != null ? ' Caused by: ' + cause.getMessage() : ''),
            ERR_SYSTEM, 'SYSTEM', null, 500
        );
        return ex;
    }

    public static OneOpsException limitExceeded(String limitName) {
        return new OneOpsException(
            'Governor limit exceeded: ' + limitName + '. Try processing in smaller batches.',
            ERR_LIMIT, 'SYSTEM', 'Limit: ' + limitName, 429
        );
    }
}
