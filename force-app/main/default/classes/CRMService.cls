/**
 * CRM Service — Lead and Account management with AI integration.
 * All public methods are callable from REST controllers and LWC.
 * Uses `with sharing` to respect record-level Sharing Rules.
 */
public with sharing class CRMService {

    private static final String MODULE = OneOpsConstants.MODULE_CRM;

    // ── Lead Retrieval ─────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getLeads(Integer pageNum, Integer pageSize, String statusFilter, String searchTerm) {
        try {
            OneopsSecurity.requireRead(Lead.SObjectType);

            Integer offset = (pageNum - 1) * pageSize;
            String likeFilter = searchTerm != null ? '%' + OneopsSecurity.sanitise(searchTerm) + '%' : '%';

            String baseQuery =
                'SELECT Id, FirstName, LastName, Company, Email, Phone, Status, ' +
                '       LeadSource, Industry, AnnualRevenue, Rating, ' +
                '       OwnerId, Owner.Name, CreatedDate, ' +
                '       AI_Score__c, AI_Assignment_Reason__c, IsConverted ' +
                'FROM Lead ' +
                'WHERE IsConverted = false ';

            if (String.isNotBlank(statusFilter)) {
                baseQuery += 'AND Status = \'' + OneopsSecurity.sanitise(statusFilter) + '\' ';
            }
            if (String.isNotBlank(searchTerm)) {
                baseQuery += 'AND (FirstName LIKE :likeFilter OR LastName LIKE :likeFilter OR Company LIKE :likeFilter OR Email LIKE :likeFilter) ';
            }
            baseQuery += 'ORDER BY CreatedDate DESC NULLS LAST LIMIT :pageSize OFFSET :offset';

            List<Lead> leads = Database.query(baseQuery);

            String countQuery = 'SELECT COUNT() FROM Lead WHERE IsConverted = false';
            if (String.isNotBlank(statusFilter)) {
                countQuery += ' AND Status = \'' + OneopsSecurity.sanitise(statusFilter) + '\'';
            }
            Integer total = Database.countQuery(countQuery);

            OneOpsLogger.info(MODULE, 'getLeads: returned ' + leads.size() + ' of ' + total);
            return OneOpsResponseWrapper.paginated(leads, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'getLeads failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        } catch (Exception ex) {
            OneOpsLogger.error(MODULE, 'getLeads unexpected error', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getLeadById(Id leadId) {
        try {
            OneopsSecurity.requireRead(Lead.SObjectType);

            List<Lead> leads = [
                SELECT Id, FirstName, LastName, Company, Email, Phone, MobilePhone,
                       Status, LeadSource, Industry, AnnualRevenue, NumberOfEmployees,
                       Rating, Title, Website, Description, Address,
                       OwnerId, Owner.Name, CreatedDate, LastModifiedDate,
                       AI_Score__c, AI_Assignment_Reason__c, AI_Email_Draft__c,
                       IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId
                FROM Lead
                WHERE Id = :leadId
                WITH USER_MODE
                LIMIT 1
            ];

            if (leads.isEmpty()) {
                throw OneOpsException.notFound('Lead', leadId);
            }

            return OneOpsResponseWrapper.ok(leads[0]).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'getLeadById failed for ' + leadId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Lead Creation ──────────────────────────────────────────────────────

    public static OneOpsResponseWrapper createLead(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Lead.SObjectType);
            validateLeadFields(fields);

            Lead newLead = new Lead(
                FirstName   = (String)  fields.get('firstName'),
                LastName    = (String)  fields.get('lastName'),
                Company     = (String)  fields.get('company'),
                Email       = (String)  fields.get('email'),
                Phone       = (String)  fields.get('phone'),
                LeadSource  = (String)  fields.get('leadSource'),
                Industry    = (String)  fields.get('industry'),
                Status      = OneOpsConstants.LEAD_STATUS_NEW,
                Rating      = 'Cold'
            );

            if (fields.containsKey('annualRevenue')) {
                newLead.AnnualRevenue = Decimal.valueOf(String.valueOf(fields.get('annualRevenue')));
            }
            if (fields.containsKey('numberOfEmployees')) {
                newLead.NumberOfEmployees = Integer.valueOf(fields.get('numberOfEmployees'));
            }

            insert newLead;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, newLead.Id, 'Lead',
                'Lead created: ' + newLead.FirstName + ' ' + newLead.LastName + ' at ' + newLead.Company);

            // Enqueue AI scoring asynchronously
            System.enqueueJob(new LeadScoringQueueable(new List<Id>{ newLead.Id }));

            return OneOpsResponseWrapper.created(newLead).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createLead failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        } catch (DmlException ex) {
            OneOpsLogger.error(MODULE, 'createLead DML error', ex);
            return OneOpsResponseWrapper.error(ex.getDmlMessage(0), OneOpsException.ERR_DML, 500);
        }
    }

    // ── Lead Update ────────────────────────────────────────────────────────

    public static OneOpsResponseWrapper updateLead(Id leadId, Map<String, Object> fields) {
        try {
            OneopsSecurity.requireUpdate(Lead.SObjectType);

            List<Lead> existing = [SELECT Id, OwnerId FROM Lead WHERE Id = :leadId WITH USER_MODE LIMIT 1];
            if (existing.isEmpty()) throw OneOpsException.notFound('Lead', leadId);

            Lead toUpdate = new Lead(Id = leadId);
            if (fields.containsKey('status'))    toUpdate.Status    = (String) fields.get('status');
            if (fields.containsKey('rating'))     toUpdate.Rating    = (String) fields.get('rating');
            if (fields.containsKey('phone'))      toUpdate.Phone     = (String) fields.get('phone');
            if (fields.containsKey('email'))      toUpdate.Email     = (String) fields.get('email');
            if (fields.containsKey('ownerId'))    toUpdate.OwnerId   = (Id)     fields.get('ownerId');
            if (fields.containsKey('industry'))   toUpdate.Industry  = (String) fields.get('industry');

            update toUpdate;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_UPDATE, leadId, 'Lead',
                'Fields updated: ' + String.join(new List<String>(fields.keySet()), ', '));

            return OneOpsResponseWrapper.ok(toUpdate, 'Lead updated.').withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'updateLead failed for ' + leadId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── AI Lead Scoring ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper scoreLeadWithAI(Id leadId) {
        try {
            List<Lead> leads = [
                SELECT Id, FirstName, LastName, Company, Email, Industry,
                       AnnualRevenue, NumberOfEmployees, LeadSource, Status
                FROM Lead WHERE Id = :leadId WITH USER_MODE LIMIT 1
            ];
            if (leads.isEmpty()) throw OneOpsException.notFound('Lead', leadId);
            Lead lead = leads[0];

            // Build AI scoring payload
            Map<String, Object> payload = new Map<String, Object>{
                'action'            => 'score_lead',
                'leadId'            => leadId,
                'company'           => lead.Company,
                'industry'          => lead.Industry,
                'annualRevenue'     => lead.AnnualRevenue,
                'numberOfEmployees' => lead.NumberOfEmployees,
                'leadSource'        => lead.LeadSource,
                'currentStatus'     => lead.Status
            };

            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(payload);

            if (aiResp.success) {
                Integer score = Integer.valueOf(aiResp.data.get('score'));
                String  reason = (String) aiResp.data.get('reason');
                String  emailDraft = (String) aiResp.data.get('emailDraft');

                Lead toUpdate = new Lead(
                    Id = leadId,
                    AI_Score__c             = score,
                    AI_Assignment_Reason__c = reason,
                    AI_Email_Draft__c       = emailDraft
                );

                // Apply status update based on score thresholds
                if (score >= OneOpsConstants.AI_SCORE_HOT) {
                    toUpdate.Status = OneOpsConstants.LEAD_STATUS_HOT;
                    toUpdate.Rating = 'Hot';
                } else if (score >= OneOpsConstants.AI_SCORE_WARM) {
                    toUpdate.Status = OneOpsConstants.LEAD_STATUS_WORKING;
                    toUpdate.Rating = 'Warm';
                } else {
                    toUpdate.Rating = 'Cold';
                }

                update toUpdate;

                // Persist AI insight record
                AI_Insight__c insight = new AI_Insight__c(
                    Name                 = 'Lead Score: ' + lead.FirstName + ' ' + lead.LastName,
                    Module__c            = MODULE,
                    Insight_Type__c      = 'Prediction',
                    Content__c           = 'AI Score: ' + score + '/100. ' + reason,
                    Related_Record_ID__c = leadId,
                    Related_Object_Type__c = 'Lead',
                    AI_Provider__c       = aiResp.provider,
                    Confidence_Score__c  = aiResp.confidence,
                    Severity__c          = score >= 80 ? 'High' : (score >= 50 ? 'Medium' : 'Low')
                );
                insert insight;

                OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_AI_CALL, leadId, 'Lead',
                    'AI lead score: ' + score + ' | Provider: ' + aiResp.provider);

                return OneOpsResponseWrapper.ok(
                    new Map<String, Object>{ 'score' => score, 'reason' => reason, 'emailDraft' => emailDraft }
                ).withModule(MODULE).withAIProvider(aiResp.provider);
            } else {
                throw OneOpsException.aiFailure('LeadScoring', aiResp.errorMessage);
            }

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'scoreLeadWithAI failed for ' + leadId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Lead Conversion ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper convertLead(Id leadId, String opportunityName, Boolean createOpportunity) {
        try {
            OneopsSecurity.requireCreate(Account.SObjectType);
            OneopsSecurity.requireCreate(Contact.SObjectType);

            Database.LeadConvert conv = new Database.LeadConvert();
            conv.setLeadId(leadId);
            conv.setConvertedStatus('Qualified');
            conv.setDoNotCreateOpportunity(!createOpportunity);

            if (createOpportunity && String.isNotBlank(opportunityName)) {
                conv.setOpportunityName(opportunityName);
            }

            Database.LeadConvertResult result = Database.convertLead(conv);

            if (!result.isSuccess()) {
                List<String> errs = new List<String>();
                for (Database.Error e : result.getErrors()) errs.add(e.getMessage());
                throw OneOpsException.validation(String.join(errs, '; '));
            }

            Map<String, Object> convResult = new Map<String, Object>{
                'accountId'     => result.getAccountId(),
                'contactId'     => result.getContactId(),
                'opportunityId' => result.getOpportunityId()
            };

            OneOpsLogger.audit(MODULE, 'LEAD_CONVERT', leadId, 'Lead',
                'Converted → Account: ' + result.getAccountId() + ', Contact: ' + result.getContactId());

            return OneOpsResponseWrapper.ok(convResult, 'Lead converted successfully.').withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'convertLead failed for ' + leadId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── SOSL Lead Search ───────────────────────────────────────────────────

    public static OneOpsResponseWrapper searchLeads(String searchText) {
        try {
            if (String.isBlank(searchText) || searchText.trim().length() < 2) {
                throw OneOpsException.validation('searchText', 'Search term must be at least 2 characters.');
            }
            String term = OneopsSecurity.sanitise(searchText) + '*';
            List<List<SObject>> results = [
                FIND :term IN ALL FIELDS
                RETURNING Lead(Id, FirstName, LastName, Company, Email, Status, AI_Score__c
                               WHERE IsConverted = false ORDER BY CreatedDate DESC LIMIT 20)
            ];
            return OneOpsResponseWrapper.ok(results[0]).withModule(MODULE);
        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void validateLeadFields(Map<String, Object> fields) {
        if (String.isBlank((String) fields.get('lastName'))) {
            throw OneOpsException.validation('lastName', 'Last name is required.');
        }
        if (String.isBlank((String) fields.get('company'))) {
            throw OneOpsException.validation('company', 'Company is required.');
        }
        String email = (String) fields.get('email');
        if (String.isNotBlank(email) && !email.contains('@')) {
            throw OneOpsException.validation('email', 'Invalid email address format.');
        }
    }
}
