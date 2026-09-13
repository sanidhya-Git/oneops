/**
 * Platform-wide constants for OneOps AI.
 * All magic strings and configuration values go here.
 * No business logic — just constants.
 */
public class OneOpsConstants {

    // ── Platform Metadata ──────────────────────────────────────────────────
    public static final String PLATFORM_NAME    = 'OneOps AI';
    public static final String PLATFORM_VERSION = '1.0.0';
    public static final String API_VERSION      = '59.0';

    // ── Module Identifiers ─────────────────────────────────────────────────
    public static final String MODULE_CRM        = 'CRM';
    public static final String MODULE_SALES      = 'SALES';
    public static final String MODULE_HR         = 'HR';
    public static final String MODULE_PM         = 'PROJECT_MANAGEMENT';
    public static final String MODULE_INVENTORY  = 'INVENTORY';
    public static final String MODULE_VENDOR     = 'VENDOR';
    public static final String MODULE_FINANCE    = 'FINANCE';
    public static final String MODULE_SUPPORT    = 'SUPPORT';
    public static final String MODULE_AI         = 'AI_ENGINE';
    public static final String MODULE_WORKFLOW   = 'WORKFLOW';
    public static final String MODULE_ANALYTICS  = 'ANALYTICS';
    public static final String MODULE_NOTIFY     = 'NOTIFICATIONS';

    // ── AI Lead Score Thresholds ───────────────────────────────────────────
    public static final Integer AI_SCORE_HOT     = 80;  // Hot lead: assign immediately
    public static final Integer AI_SCORE_WARM    = 50;  // Warm lead: nurture sequence
    public static final Integer AI_SCORE_COLD    = 0;   // Cold lead: disqualify

    // ── Generic Status Values ──────────────────────────────────────────────
    public static final String STATUS_ACTIVE      = 'Active';
    public static final String STATUS_INACTIVE    = 'Inactive';
    public static final String STATUS_PENDING     = 'Pending';
    public static final String STATUS_APPROVED    = 'Approved';
    public static final String STATUS_REJECTED    = 'Rejected';
    public static final String STATUS_CANCELLED   = 'Cancelled';
    public static final String STATUS_COMPLETED   = 'Completed';
    public static final String STATUS_IN_PROGRESS = 'In Progress';
    public static final String STATUS_DRAFT       = 'Draft';
    public static final String STATUS_CLOSED      = 'Closed';
    public static final String STATUS_SENT        = 'Sent';
    public static final String STATUS_PAID        = 'Paid';
    public static final String STATUS_OVERDUE     = 'Overdue';

    // ── Priority Values ────────────────────────────────────────────────────
    public static final String PRIORITY_CRITICAL = 'Critical';
    public static final String PRIORITY_HIGH     = 'High';
    public static final String PRIORITY_MEDIUM   = 'Medium';
    public static final String PRIORITY_LOW      = 'Low';

    // ── Lead Status Values ─────────────────────────────────────────────────
    public static final String LEAD_STATUS_NEW         = 'New';
    public static final String LEAD_STATUS_WORKING     = 'Working';
    public static final String LEAD_STATUS_NURTURING   = 'Nurturing';
    public static final String LEAD_STATUS_HOT         = 'Hot';
    public static final String LEAD_STATUS_QUALIFIED   = 'Qualified';
    public static final String LEAD_STATUS_UNQUALIFIED = 'Unqualified';
    public static final String LEAD_STATUS_CONVERTED   = 'Converted';

    // ── Ticket SLA Hours by Priority ──────────────────────────────────────
    public static final Integer SLA_CRITICAL_HOURS = 4;
    public static final Integer SLA_HIGH_HOURS     = 8;
    public static final Integer SLA_MEDIUM_HOURS   = 24;
    public static final Integer SLA_LOW_HOURS      = 72;

    // ── Inventory Defaults ─────────────────────────────────────────────────
    public static final Integer INVENTORY_DEFAULT_REORDER_POINT = 10;
    public static final Integer INVENTORY_DEFAULT_REORDER_QTY   = 50;

    // ── Named Credentials (must match Setup > Named Credentials) ──────────
    public static final String NC_AI_ENGINE    = 'OneOps_AI_Engine';
    public static final String NC_EMAIL_SVC    = 'OneOps_Email_Service';
    public static final String NC_SMS_SVC      = 'OneOps_SMS_Service';
    public static final String NC_PAYMENT_GW   = 'OneOps_Payment_Gateway';

    // ── Email Template API Names ───────────────────────────────────────────
    public static final String TMPL_LEAD_FOLLOWUP      = 'OneOps_Lead_Follow_Up';
    public static final String TMPL_INVOICE_DELIVERY   = 'OneOps_Invoice_Delivery';
    public static final String TMPL_LEAVE_APPROVAL     = 'OneOps_Leave_Approval';
    public static final String TMPL_LEAVE_REJECTION    = 'OneOps_Leave_Rejection';
    public static final String TMPL_TICKET_CREATED     = 'OneOps_Support_Ticket_Created';
    public static final String TMPL_TICKET_RESOLVED    = 'OneOps_Support_Ticket_Resolved';
    public static final String TMPL_PO_APPROVAL        = 'OneOps_PO_Approval_Request';
    public static final String TMPL_STOCK_ALERT        = 'OneOps_Low_Stock_Alert';

    // ── Platform Event Types ───────────────────────────────────────────────
    public static final String EVT_LEAD_CREATED        = 'Lead_Created';
    public static final String EVT_LEAD_SCORED         = 'Lead_Scored';
    public static final String EVT_LEAD_ASSIGNED       = 'Lead_Assigned';
    public static final String EVT_OPP_STAGE_CHANGED   = 'Opportunity_Stage_Changed';
    public static final String EVT_INVOICE_GENERATED   = 'Invoice_Generated';
    public static final String EVT_PAYMENT_RECEIVED    = 'Payment_Received';
    public static final String EVT_TICKET_CREATED      = 'Support_Ticket_Created';
    public static final String EVT_TICKET_ESCALATED    = 'Support_Ticket_Escalated';
    public static final String EVT_STOCK_LOW           = 'Inventory_Stock_Low';
    public static final String EVT_PO_APPROVED         = 'Purchase_Order_Approved';
    public static final String EVT_APPROVAL_NEEDED     = 'Approval_Needed';
    public static final String EVT_WORKFLOW_TRIGGERED  = 'Workflow_Triggered';

    // ── Permission Set Names (must match Salesforce Permission Set labels) ─
    public static final String PS_ADMIN         = 'OneOps_Admin';
    public static final String PS_SALES_MANAGER = 'OneOps_Sales_Manager';
    public static final String PS_SALES_REP     = 'OneOps_Sales_Rep';
    public static final String PS_HR_MANAGER    = 'OneOps_HR_Manager';
    public static final String PS_HR_STAFF      = 'OneOps_HR_Staff';
    public static final String PS_PM_MANAGER    = 'OneOps_PM_Manager';
    public static final String PS_FINANCE_USER  = 'OneOps_Finance_User';
    public static final String PS_SUPPORT_AGENT = 'OneOps_Support_Agent';
    public static final String PS_AI_USER       = 'OneOps_AI_User';

    // ── Governor Limit Buffers ─────────────────────────────────────────────
    public static final Integer MAX_BATCH_SIZE        = 200;
    public static final Integer MAX_SOQL_ROWS         = 49000;
    public static final Integer AI_TIMEOUT_SECONDS    = 30;
    public static final Integer MAX_EMAIL_RECIPIENTS  = 100;

    // ── AI Provider Names ──────────────────────────────────────────────────
    public static final String AI_PROVIDER_OPENAI  = 'OpenAI';
    public static final String AI_PROVIDER_CLAUDE  = 'Claude';
    public static final String AI_PROVIDER_GEMINI  = 'Gemini';

    // ── Audit Action Codes ─────────────────────────────────────────────────
    public static final String AUDIT_CREATE    = 'CREATE';
    public static final String AUDIT_UPDATE    = 'UPDATE';
    public static final String AUDIT_DELETE    = 'DELETE';
    public static final String AUDIT_VIEW      = 'VIEW';
    public static final String AUDIT_EXPORT    = 'EXPORT';
    public static final String AUDIT_LOGIN     = 'LOGIN';
    public static final String AUDIT_AI_CALL   = 'AI_CALLOUT';

    // ── Kanban Column Names ────────────────────────────────────────────────
    public static final String KANBAN_BACKLOG     = 'Backlog';
    public static final String KANBAN_TODO        = 'To Do';
    public static final String KANBAN_IN_PROGRESS = 'In Progress';
    public static final String KANBAN_IN_REVIEW   = 'In Review';
    public static final String KANBAN_DONE        = 'Done';
}
