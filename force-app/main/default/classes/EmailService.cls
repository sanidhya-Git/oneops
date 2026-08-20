/**
 * Email Service — Template-based transactional email dispatch.
 * Uses OrgWideEmailAddress and Messaging.SingleEmailMessage.
 */
public without sharing class EmailService {

    private static final String MODULE = OneOpsConstants.MODULE_NOTIFY;

    // ── Invoice Email ──────────────────────────────────────────────────────

    public static void sendInvoiceEmail(Id invoiceId) {
        List<Invoice__c> invoices = [
            SELECT Id, Name, Account__c, Account__r.Name, Total_Amount__c,
                   Due_Date__c, Status__c, Balance_Due__c
            FROM Invoice__c WHERE Id = :invoiceId WITH USER_MODE LIMIT 1
        ];
        if (invoices.isEmpty()) return;
        Invoice__c inv = invoices[0];

        List<Contact> contacts = [
            SELECT Email FROM Contact WHERE AccountId = :inv.Account__c AND Email != null WITH USER_MODE LIMIT 5
        ];
        if (contacts.isEmpty()) return;

        List<String> toAddresses = new List<String>();
        for (Contact c : contacts) toAddresses.add(c.Email);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject('Invoice ' + inv.Name + ' — Amount Due: $' + inv.Total_Amount__c);
        email.setHtmlBody(buildInvoiceEmailBody(inv));

        setOrgWideAddress(email);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            OneOpsLogger.info(MODULE, 'Invoice email sent: ' + inv.Name + ' to ' + String.join(toAddresses, ', '));
        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'sendInvoiceEmail failed for ' + invoiceId, ex);
        }
    }

    // ── Lead Follow-Up Email ───────────────────────────────────────────────

    public static void sendLeadFollowUp(Id leadId, String emailBody) {
        List<Lead> leads = [
            SELECT FirstName, LastName, Email, Company, OwnerId, Owner.Email
            FROM Lead WHERE Id = :leadId AND Email != null WITH USER_MODE LIMIT 1
        ];
        if (leads.isEmpty() || String.isBlank(leads[0].Email)) return;
        Lead lead = leads[0];

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ lead.Email });
        email.setReplyTo(lead.Owner.Email);
        email.setSubject('Following up — How can we help ' + lead.Company + '?');
        email.setHtmlBody(
            String.isNotBlank(emailBody)
                ? emailBody
                : buildDefaultFollowUpBody(lead.FirstName, lead.Company)
        );

        setOrgWideAddress(email);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            OneOpsLogger.audit(MODULE, 'EMAIL_SENT', leadId, 'Lead', 'Follow-up email sent to ' + lead.Email);
        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'sendLeadFollowUp failed', ex);
        }
    }

    // ── Generic Notification Email ─────────────────────────────────────────

    public static void sendSystemAlert(List<String> toAddresses, String subject, String body) {
        if (toAddresses.isEmpty() || String.isBlank(subject)) return;

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject('[OneOps AI] ' + subject);
        email.setHtmlBody('<html><body style="font-family:sans-serif;">' + body + '</body></html>');

        setOrgWideAddress(email);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'sendSystemAlert failed: ' + subject, ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void setOrgWideAddress(Messaging.SingleEmailMessage email) {
        try {
            List<OrgWideEmailAddress> owea = [
                SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'OneOps AI' LIMIT 1
            ];
            if (!owea.isEmpty()) email.setOrgWideEmailAddressId(owea[0].Id);
        } catch (Exception ex) {
            // No OrgWideEmailAddress configured — Salesforce uses default
        }
    }

    private static String buildInvoiceEmailBody(Invoice__c inv) {
        return '<!DOCTYPE html><html><body style="font-family: Arial, sans-serif; color: #333;">' +
            '<div style="max-width:600px;margin:0 auto;border:1px solid #e0e0e0;border-radius:8px;overflow:hidden;">' +
            '<div style="background:#0A1628;padding:20px 30px;">' +
            '<h2 style="color:#C89B3C;margin:0;">OneOps AI</h2>' +
            '<p style="color:#fff;margin:4px 0 0;">Invoice Notification</p></div>' +
            '<div style="padding:30px;">' +
            '<p>Dear ' + inv.Account__r.Name + ',</p>' +
            '<p>Please find your invoice details below:</p>' +
            '<table style="width:100%;border-collapse:collapse;margin:20px 0;">' +
            '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Invoice Number</td><td style="padding:8px;border-bottom:1px solid #eee;">' + inv.Name + '</td></tr>' +
            '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Amount Due</td><td style="padding:8px;border-bottom:1px solid #eee;">$' + inv.Balance_Due__c + '</td></tr>' +
            '<tr><td style="padding:8px;font-weight:bold;">Due Date</td><td style="padding:8px;">' + inv.Due_Date__c.format() + '</td></tr>' +
            '</table>' +
            '<p>Please remit payment by the due date to avoid late fees.</p>' +
            '<p style="color:#888;font-size:12px;">This is an automated message from OneOps AI. Do not reply directly to this email.</p>' +
            '</div></div></body></html>';
    }

    private static String buildDefaultFollowUpBody(String firstName, String company) {
        return '<!DOCTYPE html><html><body style="font-family: Arial, sans-serif;color:#333;">' +
            '<p>Hi ' + firstName + ',</p>' +
            '<p>Thank you for your interest in OneOps AI. We\'d love to learn more about ' + company + '\'s workflow automation needs.</p>' +
            '<p>Would you be open to a 20-minute call this week? We can show you how our AI-driven platform has helped similar companies save 40%+ in operational overhead.</p>' +
            '<p>Looking forward to connecting,<br>The OneOps AI Team</p>' +
            '<hr style="border:none;border-top:1px solid #eee;"><p style="color:#888;font-size:11px;">Powered by OneOps AI | Unsubscribe</p>' +
            '</body></html>';
    }
}
