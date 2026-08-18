/**
 * Dashboard Service — Cross-module KPI aggregation for the analytics dashboard.
 * All methods are @AuraEnabled cacheable for LWC consumption.
 */
public with sharing class DashboardService {

    private static final String MODULE = OneOpsConstants.MODULE_ANALYTICS;

    // ── Executive Summary ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getExecutiveSummary() {
        try {
            // CRM KPIs
            Integer newLeads    = [SELECT COUNT() FROM Lead WHERE CreatedDate = THIS_MONTH AND IsConverted = false WITH USER_MODE];
            Integer hotLeads    = [SELECT COUNT() FROM Lead WHERE Rating = 'Hot' AND IsConverted = false WITH USER_MODE];
            Integer convertedThisMonth = [SELECT COUNT() FROM Lead WHERE ConvertedDate = THIS_MONTH WITH USER_MODE];

            // Sales KPIs
            AggregateResult[] oppAg = [SELECT SUM(Amount) total, COUNT(Id) cnt FROM Opportunity WHERE IsClosed = false WITH USER_MODE];
            Decimal pipelineValue   = oppAg.isEmpty() ? 0 : (Decimal)(oppAg[0].get('total') != null ? oppAg[0].get('total') : 0);

            // Finance KPIs
            AggregateResult[] invoiceAg = [SELECT SUM(Total_Amount__c) total, SUM(Amount_Paid__c) paid FROM Invoice__c WHERE Status__c != 'Cancelled' WITH USER_MODE];
            Decimal totalRevenue = invoiceAg.isEmpty() ? 0 : (Decimal)(invoiceAg[0].get('total') != null ? invoiceAg[0].get('total') : 0);
            Decimal collected    = invoiceAg.isEmpty() ? 0 : (Decimal)(invoiceAg[0].get('paid')  != null ? invoiceAg[0].get('paid')  : 0);

            // Support KPIs
            Integer openTickets  = [SELECT COUNT() FROM Support_Ticket__c WHERE Status__c NOT IN ('Resolved', 'Closed') WITH USER_MODE];
            Integer slaBreached  = [SELECT COUNT() FROM Support_Ticket__c WHERE Is_SLA_Breached__c = true AND Status__c NOT IN ('Resolved', 'Closed') WITH USER_MODE];

            // Inventory KPIs
            Integer lowStockItems = [SELECT COUNT() FROM Inventory_Item__c WHERE Is_Low_Stock__c = true WITH USER_MODE];

            // HR KPIs
            Integer activeEmployees = [SELECT COUNT() FROM Employee__c WHERE Employment_Status__c = 'Active' WITH USER_MODE];
            Integer pendingLeave    = [SELECT COUNT() FROM Leave_Request__c WHERE Status__c = 'Pending' WITH USER_MODE];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'crm' => new Map<String, Object>{
                    'newLeads'        => newLeads,
                    'hotLeads'        => hotLeads,
                    'convertedThisMonth' => convertedThisMonth
                },
                'sales' => new Map<String, Object>{
                    'pipelineValue'   => pipelineValue,
                    'openOpps'        => oppAg.isEmpty() ? 0 : oppAg[0].get('cnt')
                },
                'finance' => new Map<String, Object>{
                    'totalRevenue'    => totalRevenue,
                    'collected'       => collected,
                    'outstanding'     => totalRevenue - collected
                },
                'support' => new Map<String, Object>{
                    'openTickets'     => openTickets,
                    'slaBreached'     => slaBreached,
                    'slaCompliance'   => openTickets > 0 ? Math.round(((openTickets - slaBreached) * 100.0) / openTickets) : 100
                },
                'inventory' => new Map<String, Object>{
                    'lowStockItems'   => lowStockItems
                },
                'hr' => new Map<String, Object>{
                    'activeEmployees' => activeEmployees,
                    'pendingLeave'    => pendingLeave
                }
            }).withModule(MODULE);

        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'getExecutiveSummary failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Lead Funnel ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getLeadFunnel() {
        try {
            AggregateResult[] byStatus = [
                SELECT Status, COUNT(Id) cnt FROM Lead
                WHERE IsConverted = false WITH USER_MODE GROUP BY Status ORDER BY COUNT(Id) DESC
            ];
            return OneOpsResponseWrapper.ok(byStatus).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Revenue Trend ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getRevenueTrend(Integer months) {
        try {
            if (months == null || months < 1 || months > 24) months = 6;
            Date fromDate = Date.today().addMonths(-months);

            AggregateResult[] monthly = [
                SELECT CALENDAR_YEAR(Invoice_Date__c) yr, CALENDAR_MONTH(Invoice_Date__c) mo,
                       SUM(Total_Amount__c) total, SUM(Amount_Paid__c) paid
                FROM Invoice__c
                WHERE Invoice_Date__c >= :fromDate AND Status__c != 'Cancelled'
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), CALENDAR_MONTH(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), CALENDAR_MONTH(Invoice_Date__c)
            ];

            return OneOpsResponseWrapper.ok(monthly).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── AI Insights Feed ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getAIInsightsFeed(String module) {
        try {
            String q = 'SELECT Id, Name, Module__c, Insight_Type__c, Severity__c, ' +
                       'Content__c, AI_Provider__c, Confidence_Score__c, ' +
                       'Is_Actioned__c, CreatedDate, Expiry_Date__c ' +
                       'FROM AI_Insight__c WHERE Is_Actioned__c = false ';
            if (String.isNotBlank(module)) {
                q += 'AND Module__c = \'' + OneopsSecurity.sanitise(module) + '\' ';
            }
            q += 'AND (Expiry_Date__c = null OR Expiry_Date__c >= TODAY) ORDER BY CreatedDate DESC LIMIT 20';

            return OneOpsResponseWrapper.ok(Database.query(q)).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Module Activity ────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getRecentActivity() {
        try {
            List<Audit_Log__c> logs = [
                SELECT Id, Module__c, Action__c, Object_Type__c, Record_ID__c,
                       User__c, User__r.Name, Timestamp__c, Level__c
                FROM Audit_Log__c
                WHERE Level__c IN ('AUDIT', 'INFO')
                ORDER BY Timestamp__c DESC LIMIT 50
            ];
            return OneOpsResponseWrapper.ok(logs).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Support Ticket Trends ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getSupportTrends(Integer days) {
        try {
            if (days == null || days < 1) days = 30;
            Date fromDate = Date.today().addDays(-days);

            AggregateResult[] byCategory = [
                SELECT Category__c, COUNT(Id) cnt, AVG(CSAT_Score__c) avgCsat
                FROM Support_Ticket__c WHERE CreatedDate >= :fromDate WITH USER_MODE
                GROUP BY Category__c ORDER BY COUNT(Id) DESC
            ];

            AggregateResult[] byPriority = [
                SELECT Priority__c, COUNT(Id) cnt FROM Support_Ticket__c
                WHERE CreatedDate >= :fromDate WITH USER_MODE GROUP BY Priority__c
            ];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'byCategory' => byCategory,
                'byPriority' => byPriority,
                'daysBack'   => days
            }).withModule(MODULE);
        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }
}
