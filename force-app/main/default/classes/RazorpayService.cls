/**
 * RazorpayService — Razorpay payment gateway integration.
 * Named Credential: OneOps_Razorpay
 * Supports: create order, verify payment, capture, refund.
 */
public with sharing class RazorpayService {

    private static final String NC_BASE     = 'callout:OneOps_Razorpay';
    private static final String ORDERS_PATH = '/v1/orders';
    private static final String PAY_PATH    = '/v1/payments';

    /* ─── Create Razorpay order for an Invoice ───────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper createOrder(Id invoiceId) {
        try {
            Invoice__c inv = [
                SELECT Id, Name, Balance_Due__c, Account__r.Name, Account__r.Phone
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH USER_MODE
                LIMIT 1
            ];

            if (inv.Balance_Due__c == null || inv.Balance_Due__c <= 0) {
                return OneOpsResponseWrapper.error('Invoice has no outstanding balance.',
                    OneOpsException.ERR_VALIDATION, 400);
            }

            // Razorpay amounts are in paise (INR × 100) or cents
            Integer amountInPaise = Integer.valueOf(inv.Balance_Due__c * 100);

            Map<String, Object> payload = new Map<String, Object>{
                'amount'          => amountInPaise,
                'currency'        => 'INR',
                'receipt'         => inv.Name,
                'partial_payment' => false,
                'notes'           => new Map<String, Object>{
                    'invoice_id'  => inv.Id,
                    'account'     => inv.Account__r.Name
                }
            };

            HttpResponse res = post(ORDERS_PATH, payload);
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                return OneOpsResponseWrapper.error('Razorpay error: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            Map<String, Object> order = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            OneOpsLogger.audit('RazorpayService', 'Order created: ' + order.get('id') + ' for invoice ' + inv.Name);
            return OneOpsResponseWrapper.success(order);

        } catch (Exception e) {
            OneOpsLogger.error('RazorpayService.createOrder', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Capture payment & record in Salesforce ─────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper capturePayment(String razorpayPaymentId, Id invoiceId, Decimal amount) {
        try {
            HttpResponse res = post(PAY_PATH + '/' + razorpayPaymentId + '/capture',
                new Map<String, Object>{ 'amount' => Integer.valueOf(amount * 100), 'currency' => 'INR' });

            if (res.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Capture failed: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            // Record payment in Salesforce
            OneOpsResponseWrapper payResult = FinanceService.recordPayment(
                invoiceId, amount, 'Razorpay', razorpayPaymentId
            );

            OneOpsLogger.audit('RazorpayService', 'Captured $' + amount + ' for invoice ' + invoiceId);
            return payResult;

        } catch (Exception e) {
            OneOpsLogger.error('RazorpayService.capturePayment', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Refund ─────────────────────────────────────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper refund(String razorpayPaymentId, Decimal amount, String reason) {
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'amount' => Integer.valueOf(amount * 100),
                'notes'  => new Map<String, Object>{ 'reason' => reason }
            };
            HttpResponse res = post(PAY_PATH + '/' + razorpayPaymentId + '/refund', payload);

            if (res.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Refund failed: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            OneOpsLogger.audit('RazorpayService', 'Refunded $' + amount + ' for payment ' + razorpayPaymentId);
            return OneOpsResponseWrapper.success(
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody())
            );
        } catch (Exception e) {
            OneOpsLogger.error('RazorpayService.refund', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private static HttpResponse post(String path, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_BASE + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);
        req.setBody(JSON.serialize(body));
        return new Http().send(req);
    }
}
