/**
 * WhatsAppService — sends WhatsApp Business API messages via Meta Graph API.
 * Named Credential: OneOps_WhatsApp_API
 * Docs: https://developers.facebook.com/docs/whatsapp/cloud-api
 */
public with sharing class WhatsAppService {

    private static final String NC_NAME  = 'callout:OneOps_WhatsApp_API';
    private static final String API_PATH = '/messages';
    private static final String TIMEOUT  = '10000';

    /* ─── Public API ─────────────────────────────────────────────── */

    /**
     * Send a plain text message.
     */
    public static OneOpsResponseWrapper sendText(String toPhone, String message) {
        if (String.isBlank(toPhone) || String.isBlank(message)) {
            return OneOpsResponseWrapper.error('Phone and message are required.', OneOpsException.ERR_VALIDATION, 400);
        }
        Map<String, Object> payload = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'to'                => sanitizePhone(toPhone),
            'type'              => 'text',
            'text'              => new Map<String, Object>{ 'body' => message }
        };
        return callApi(payload, 'sendText');
    }

    /**
     * Send a template message (pre-approved WhatsApp template).
     */
    public static OneOpsResponseWrapper sendTemplate(String toPhone, String templateName,
                                                      String languageCode, List<String> components) {
        if (String.isBlank(toPhone) || String.isBlank(templateName)) {
            return OneOpsResponseWrapper.error('Phone and templateName are required.', OneOpsException.ERR_VALIDATION, 400);
        }

        List<Map<String, Object>> compList = new List<Map<String, Object>>();
        if (components != null && !components.isEmpty()) {
            List<Map<String, Object>> params = new List<Map<String, Object>>();
            for (String val : components) {
                params.add(new Map<String, Object>{ 'type' => 'text', 'text' => val });
            }
            compList.add(new Map<String, Object>{ 'type' => 'body', 'parameters' => params });
        }

        Map<String, Object> payload = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'to'                => sanitizePhone(toPhone),
            'type'              => 'template',
            'template'          => new Map<String, Object>{
                'name'       => templateName,
                'language'   => new Map<String, Object>{ 'code' => (languageCode != null ? languageCode : 'en_US') },
                'components' => compList
            }
        };
        return callApi(payload, 'sendTemplate');
    }

    /**
     * Notify a customer when their support ticket status changes.
     */
    @AuraEnabled
    public static OneOpsResponseWrapper notifyTicketUpdate(Id ticketId) {
        try {
            Support_Ticket__c ticket = [
                SELECT Subject__c, Status__c, Account__r.Phone, Name
                FROM Support_Ticket__c
                WHERE Id = :ticketId
                WITH USER_MODE
                LIMIT 1
            ];
            if (String.isBlank(ticket.Account__r.Phone)) {
                return OneOpsResponseWrapper.error('No phone on account.', OneOpsException.ERR_VALIDATION, 400);
            }
            String msg = 'OneOps Update — Ticket ' + ticket.Name + ': Your support ticket "'
                + ticket.Subject__c + '" is now ' + ticket.Status__c + '.';
            return sendText(ticket.Account__r.Phone, msg);
        } catch (Exception e) {
            OneOpsLogger.error('WhatsAppService.notifyTicketUpdate', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_SYSTEM, 500);
        }
    }

    /**
     * Send invoice payment reminder via WhatsApp.
     */
    @AuraEnabled
    public static OneOpsResponseWrapper sendInvoiceReminder(Id invoiceId) {
        try {
            Invoice__c inv = [
                SELECT Name, Total_Amount__c, Due_Date__c, Account__r.Phone, Balance_Due__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH USER_MODE
                LIMIT 1
            ];
            if (String.isBlank(inv.Account__r.Phone)) {
                return OneOpsResponseWrapper.error('No phone on account.', OneOpsException.ERR_VALIDATION, 400);
            }
            String msg = 'OneOps Finance — Invoice ' + inv.Name + ' for $'
                + inv.Balance_Due__c.format() + ' is due on '
                + inv.Due_Date__c.format() + '. Please arrange payment.';
            return sendText(inv.Account__r.Phone, msg);
        } catch (Exception e) {
            OneOpsLogger.error('WhatsAppService.sendInvoiceReminder', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_SYSTEM, 500);
        }
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private static OneOpsResponseWrapper callApi(Map<String, Object> payload, String action) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_NAME + API_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);
            req.setBody(JSON.serialize(payload));

            HttpResponse res  = new Http().send(req);
            Boolean success   = (res.getStatusCode() == 200 || res.getStatusCode() == 201);

            OneOpsLogger.audit('WhatsAppService.' + action,
                success ? 'Message sent.' : 'Error: ' + res.getBody());

            if (!success) {
                return OneOpsResponseWrapper.error('WhatsApp API error: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }
            return OneOpsResponseWrapper.success(
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody())
            );
        } catch (Exception e) {
            OneOpsLogger.error('WhatsAppService.' + action, e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    private static String sanitizePhone(String phone) {
        return phone.replaceAll('[^0-9+]', '');
    }
}
