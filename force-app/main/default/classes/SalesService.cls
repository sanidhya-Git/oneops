/**
 * Sales Service — Opportunity pipeline, forecasting, and quote management.
 */
public with sharing class SalesService {

    private static final String MODULE = OneOpsConstants.MODULE_SALES;

    // ── Opportunity Management ─────────────────────────────────────────────

    public static OneOpsResponseWrapper getOpportunities(String stage, Id accountId, Integer pageNum, Integer pageSize) {
        try {
            OneopsSecurity.requireRead(Opportunity.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, AccountId, Account.Name, StageName, Amount, ' +
                       'CloseDate, Probability, OwnerId, Owner.Name, ' +
                       'LeadSource, ForecastCategoryName, CreatedDate ' +
                       'FROM Opportunity WHERE Id != null ';
            if (String.isNotBlank(stage))  q += 'AND StageName = \'' + OneopsSecurity.sanitise(stage) + '\' ';
            if (accountId != null)         q += 'AND AccountId = \'' + accountId + '\' ';
            q += 'ORDER BY CloseDate ASC NULLS LAST LIMIT :pageSize OFFSET :offset';

            List<Opportunity> opps = Database.query(q);

            String countQ = 'SELECT COUNT() FROM Opportunity WHERE Id != null';
            Integer total = Database.countQuery(countQ);

            return OneOpsResponseWrapper.paginated(opps, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Pipeline Summary ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getPipelineSummary() {
        try {
            AggregateResult[] byStage = [
                SELECT StageName, COUNT(Id) cnt, SUM(Amount) total
                FROM Opportunity
                WHERE IsClosed = false AND StageName != null
                WITH USER_MODE
                GROUP BY StageName ORDER BY StageName
            ];

            Decimal totalPipelineValue = 0;
            for (AggregateResult r : byStage) {
                totalPipelineValue += (Decimal)(r.get('total') != null ? r.get('total') : 0);
            }

            Integer closingThisMonth = [
                SELECT COUNT() FROM Opportunity
                WHERE IsClosed = false AND CloseDate >= :Date.today().toStartOfMonth()
                AND CloseDate <= :Date.today().toStartOfMonth().addMonths(1).addDays(-1)
                WITH USER_MODE
            ];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'byStage'           => byStage,
                'totalPipelineValue' => totalPipelineValue,
                'closingThisMonth'  => closingThisMonth
            }).withModule(MODULE);

        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Forecasting ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getForecast(Integer quarterOffset) {
        try {
            // Build quarter date range
            Date today     = Date.today();
            Integer month  = today.month();
            Integer year   = today.year();
            Integer qStart = (((month - 1) / 3) * 3) + 1 + (quarterOffset * 3);
            if (qStart > 12) { qStart -= 12; year++; }
            if (qStart < 1)  { qStart += 12; year--; }
            Date fromDate = Date.newInstance(year, qStart, 1);
            Date toDate   = fromDate.addMonths(3).addDays(-1);

            AggregateResult[] forecast = [
                SELECT ForecastCategoryName, SUM(Amount) total, COUNT(Id) cnt
                FROM Opportunity
                WHERE IsClosed = false AND CloseDate >= :fromDate AND CloseDate <= :toDate
                WITH USER_MODE GROUP BY ForecastCategoryName
            ];

            // AI forecast enhancement
            Map<String, Object> aiPayload = new Map<String, Object>{
                'action'         => 'sales_forecast',
                'fromDate'       => String.valueOf(fromDate),
                'toDate'         => String.valueOf(toDate),
                'forecastData'   => JSON.serialize(forecast)
            };
            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(aiPayload);

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'forecastByCategory' => forecast,
                'fromDate'           => fromDate,
                'toDate'             => toDate,
                'aiPrediction'       => aiResp.success ? aiResp.data : null
            }).withModule(MODULE);

        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Quote Management ───────────────────────────────────────────────────

    public static OneOpsResponseWrapper createQuote(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Quote.SObjectType);

            if (fields.get('opportunityId') == null) {
                throw OneOpsException.validation('opportunityId', 'Opportunity is required for quote creation.');
            }

            Quote q = new Quote(
                Name            = (String) fields.get('name'),
                OpportunityId   = (Id)     fields.get('opportunityId'),
                ExpirationDate  = fields.containsKey('expiryDate') ? Date.valueOf((String) fields.get('expiryDate')) : Date.today().addDays(30),
                Description     = (String) fields.get('description'),
                Discount        = fields.containsKey('discount') ? Decimal.valueOf(String.valueOf(fields.get('discount'))) : 0,
                ShippingHandling = fields.containsKey('shipping') ? Decimal.valueOf(String.valueOf(fields.get('shipping'))) : 0,
                Tax             = fields.containsKey('tax') ? Decimal.valueOf(String.valueOf(fields.get('tax'))) : 0
            );

            insert q;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, q.Id, 'Quote',
                'Quote created: ' + q.Name);

            return OneOpsResponseWrapper.created(q).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── AI Win Probability ─────────────────────────────────────────────────

    public static OneOpsResponseWrapper getWinProbability(Id oppId) {
        try {
            List<Opportunity> opps = [
                SELECT Id, Name, StageName, Amount, CloseDate, Probability,
                       AccountId, Account.Industry, Account.AnnualRevenue,
                       CreatedDate, LastActivityDate
                FROM Opportunity WHERE Id = :oppId WITH USER_MODE LIMIT 1
            ];
            if (opps.isEmpty()) throw OneOpsException.notFound('Opportunity', oppId);
            Opportunity opp = opps[0];

            Map<String, Object> aiPayload = new Map<String, Object>{
                'action'          => 'win_probability',
                'opportunityId'   => oppId,
                'stage'           => opp.StageName,
                'amount'          => opp.Amount,
                'daysToClose'     => Date.today().daysBetween(opp.CloseDate),
                'industry'        => opp.Account.Industry,
                'annualRevenue'   => opp.Account.AnnualRevenue,
                'currentProbability' => opp.Probability
            };

            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(aiPayload);

            return OneOpsResponseWrapper.ok(aiResp.success ? aiResp.data : new Map<String, Object>{
                'aiProbability' => opp.Probability,
                'source'        => 'fallback'
            }).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }
}
