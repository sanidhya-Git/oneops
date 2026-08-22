/**
 * Finance Service — Invoice lifecycle, payment recording, budget tracking, revenue analytics.
 */
public with sharing class FinanceService {

    private static final String MODULE = OneOpsConstants.MODULE_FINANCE;

    // ── Invoice Management ─────────────────────────────────────────────────

    public static OneOpsResponseWrapper createInvoice(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Invoice__c.SObjectType);

            if (fields.get('accountId') == null) {
                throw OneOpsException.validation('accountId', 'Account is required for invoice creation.');
            }

            Date invoiceDate = Date.today();
            Integer paymentTermDays = 30;
            if (fields.containsKey('paymentTermDays')) {
                paymentTermDays = Integer.valueOf(fields.get('paymentTermDays'));
            }

            Invoice__c inv = new Invoice__c(
                Account__c      = (Id)  fields.get('accountId'),
                Opportunity__c  = (Id)  fields.get('opportunityId'),
                Status__c       = OneOpsConstants.STATUS_DRAFT,
                Invoice_Date__c = invoiceDate,
                Due_Date__c     = invoiceDate.addDays(paymentTermDays),
                Notes__c        = (String) fields.get('notes'),
                Currency_Code__c = fields.containsKey('currencyCode') ? (String)fields.get('currencyCode') : 'USD'
            );

            insert inv;

            // Create line items
            if (fields.containsKey('lineItems')) {
                List<Object> lineItems = (List<Object>) fields.get('lineItems');
                createInvoiceLines(inv.Id, lineItems);
            }

            // Recalculate subtotal
            recalculateInvoiceTotals(inv.Id);

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, inv.Id, 'Invoice__c',
                'Invoice created for Account: ' + fields.get('accountId'));

            return OneOpsResponseWrapper.created(inv).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createInvoice failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getInvoices(String status, Id accountId, Integer pageNum, Integer pageSize) {
        try {
            OneopsSecurity.requireRead(Invoice__c.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, Account__c, Account__r.Name, Opportunity__c, ' +
                       'Status__c, Invoice_Date__c, Due_Date__c, ' +
                       'Subtotal__c, Tax_Amount__c, Total_Amount__c, Amount_Paid__c, Balance_Due__c, ' +
                       'Days_Overdue__c, Currency_Code__c ' +
                       'FROM Invoice__c WHERE Id != null ';
            if (String.isNotBlank(status)) q += 'AND Status__c = \'' + OneopsSecurity.sanitise(status) + '\' ';
            if (accountId != null)         q += 'AND Account__c = \'' + accountId + '\' ';
            q += 'ORDER BY Invoice_Date__c DESC LIMIT :pageSize OFFSET :offset';

            List<Invoice__c> invoices = Database.query(q);

            String countQ = 'SELECT COUNT() FROM Invoice__c WHERE Id != null';
            if (String.isNotBlank(status)) countQ += ' AND Status__c = \'' + OneopsSecurity.sanitise(status) + '\'';
            Integer total = Database.countQuery(countQ);

            return OneOpsResponseWrapper.paginated(invoices, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper sendInvoice(Id invoiceId) {
        try {
            List<Invoice__c> invList = [
                SELECT Id, Status__c, Account__c, Account__r.Name,
                       Total_Amount__c, Due_Date__c
                FROM Invoice__c WHERE Id = :invoiceId WITH USER_MODE LIMIT 1
            ];
            if (invList.isEmpty()) throw OneOpsException.notFound('Invoice', invoiceId);
            Invoice__c inv = invList[0];

            if (inv.Status__c != 'Draft') {
                throw OneOpsException.validation('status', 'Only draft invoices can be sent.');
            }

            update new Invoice__c(Id = invoiceId, Status__c = 'Sent');

            // Send email with invoice details
            EmailService.sendInvoiceEmail(invoiceId);

            OneOpsLogger.audit(MODULE, 'INVOICE_SENT', invoiceId, 'Invoice__c',
                'Invoice sent to: ' + inv.Account__r.Name + '. Amount: ' + inv.Total_Amount__c);

            return OneOpsResponseWrapper.ok(null, 'Invoice sent.').withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Payment Recording ──────────────────────────────────────────────────

    public static OneOpsResponseWrapper recordPayment(Id invoiceId, Decimal amount, String method, String reference) {
        try {
            OneopsSecurity.requireCreate(Payment__c.SObjectType);

            List<Invoice__c> invList = [
                SELECT Id, Status__c, Total_Amount__c, Amount_Paid__c, Balance_Due__c
                FROM Invoice__c WHERE Id = :invoiceId WITH USER_MODE LIMIT 1
            ];
            if (invList.isEmpty()) throw OneOpsException.notFound('Invoice', invoiceId);
            Invoice__c inv = invList[0];

            if (inv.Status__c == 'Paid') {
                throw OneOpsException.validation('status', 'Invoice is already fully paid.');
            }
            if (amount <= 0) {
                throw OneOpsException.validation('amount', 'Payment amount must be greater than zero.');
            }
            if (amount > inv.Balance_Due__c) {
                throw OneOpsException.validation('amount',
                    'Payment (' + amount + ') exceeds balance due (' + inv.Balance_Due__c + ').');
            }

            Payment__c payment = new Payment__c(
                Invoice__c       = invoiceId,
                Amount__c        = amount,
                Payment_Date__c  = Date.today(),
                Payment_Method__c = method,
                Reference_Number__c = reference,
                Status__c        = 'Confirmed'
            );
            insert payment;

            // Update invoice amount_paid and status
            Decimal newPaid = (inv.Amount_Paid__c != null ? inv.Amount_Paid__c : 0) + amount;
            String newStatus = newPaid >= inv.Total_Amount__c ? 'Paid' : 'Partially Paid';
            update new Invoice__c(Id = invoiceId, Amount_Paid__c = newPaid, Status__c = newStatus);

            OneOpsLogger.audit(MODULE, 'PAYMENT_RECORDED', invoiceId, 'Invoice__c',
                'Payment: ' + amount + ' via ' + method + '. Status → ' + newStatus);

            return OneOpsResponseWrapper.created(payment).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'recordPayment failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Revenue Analytics ─────────────────────────────────────────────────

    public static OneOpsResponseWrapper getRevenueAnalytics(Integer monthsBack) {
        try {
            Date fromDate = Date.today().addMonths(-monthsBack);
            AggregateResult[] monthly = [
                SELECT CALENDAR_MONTH(Invoice_Date__c) mo, CALENDAR_YEAR(Invoice_Date__c) yr,
                       SUM(Total_Amount__c) total, SUM(Amount_Paid__c) paid, COUNT(Id) cnt
                FROM Invoice__c
                WHERE Invoice_Date__c >= :fromDate AND Status__c != 'Cancelled'
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), CALENDAR_MONTH(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), CALENDAR_MONTH(Invoice_Date__c)
            ];

            Decimal totalRevenue = 0;
            Decimal totalPaid    = 0;
            for (AggregateResult r : monthly) {
                totalRevenue += (Decimal)(r.get('total') != null ? r.get('total') : 0);
                totalPaid    += (Decimal)(r.get('paid')  != null ? r.get('paid')  : 0);
            }

            Integer overdueCount = [SELECT COUNT() FROM Invoice__c WHERE Status__c = 'Overdue' WITH USER_MODE];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'monthlyBreakdown' => monthly,
                'totalRevenue'     => totalRevenue,
                'totalCollected'   => totalPaid,
                'outstanding'      => totalRevenue - totalPaid,
                'overdueInvoices'  => overdueCount
            }).withModule(MODULE);

        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Budget Tracking ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getBudgetStatus(Id deptId) {
        try {
            List<Budget__c> budgets = [
                SELECT Id, Name, Department__c, Department__r.Name, Budget_Type__c,
                       Fiscal_Year__c, Allocated_Amount__c, Spent_Amount__c,
                       Remaining_Amount__c, Utilization_Percent__c, Alert_Threshold__c, Status__c
                FROM Budget__c WHERE Department__c = :deptId WITH USER_MODE
                ORDER BY Fiscal_Year__c DESC
            ];
            return OneOpsResponseWrapper.ok(budgets).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void createInvoiceLines(Id invoiceId, List<Object> lineItems) {
        List<Invoice_Line__c> lines = new List<Invoice_Line__c>();
        for (Object item : lineItems) {
            Map<String, Object> line = (Map<String, Object>) item;
            lines.add(new Invoice_Line__c(
                Invoice__c      = invoiceId,
                Description__c  = (String)  line.get('description'),
                Quantity__c     = Decimal.valueOf(String.valueOf(line.get('quantity'))),
                Unit_Price__c   = Decimal.valueOf(String.valueOf(line.get('unitPrice'))),
                Discount_Percent__c = line.containsKey('discountPct') ? Decimal.valueOf(String.valueOf(line.get('discountPct'))) : 0,
                Tax_Percent__c  = line.containsKey('taxPct') ? Decimal.valueOf(String.valueOf(line.get('taxPct'))) : 0
            ));
        }
        if (!lines.isEmpty()) insert lines;
    }

    private static void recalculateInvoiceTotals(Id invoiceId) {
        AggregateResult[] ag = [
            SELECT SUM(Line_Total__c) subtotal FROM Invoice_Line__c WHERE Invoice__c = :invoiceId
        ];
        Decimal subtotal = ag.isEmpty() ? 0 : (Decimal)(ag[0].get('subtotal') != null ? ag[0].get('subtotal') : 0);
        update new Invoice__c(Id = invoiceId, Subtotal__c = subtotal);
    }
}
