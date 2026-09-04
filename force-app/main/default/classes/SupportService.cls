/**
 * Support Service — Ticket lifecycle, SLA tracking, AI deflection, and CSAT.
 */
public with sharing class SupportService {

    private static final String MODULE = OneOpsConstants.MODULE_SUPPORT;

    // ── Ticket Creation ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper createTicket(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Support_Ticket__c.SObjectType);
            validateTicketFields(fields);

            String priority = (String) fields.get('priority');
            if (String.isBlank(priority)) priority = OneOpsConstants.PRIORITY_MEDIUM;

            Support_Ticket__c ticket = new Support_Ticket__c(
                Account__c    = (Id) fields.get('accountId'),
                Contact__c    = (Id) fields.get('contactId'),
                Subject       = (String) fields.get('subject'),
                Description__c = (String) fields.get('description'),
                Priority__c   = priority,
                Status__c     = 'New',
                Category__c   = (String) fields.get('category'),
                Channel__c    = (String) fields.get('channel'),
                SLA_Due_Date__c = calculateSLADueDate(priority)
            );

            insert ticket;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, ticket.Id, 'Support_Ticket__c',
                'Ticket created. Priority: ' + priority + ', Channel: ' + ticket.Channel__c);

            // Async: get AI suggestion and sentiment
            System.enqueueJob(new TicketAIQueueable(ticket.Id));

            // Auto-assign based on availability and skills
            autoAssignTicket(ticket.Id, priority);

            return OneOpsResponseWrapper.created(ticket).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createTicket failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Ticket Queue ───────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getTicketQueue(String statusFilter, String priorityFilter,
                                                        Id agentId, Integer pageNum, Integer pageSize) {
        try {
            OneopsSecurity.requireRead(Support_Ticket__c.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, Account__c, Account__r.Name, Contact__c, Contact__r.Name, ' +
                       'Subject, Priority__c, Status__c, Category__c, Channel__c, ' +
                       'Assigned_Agent__c, Assigned_Agent__r.Name, ' +
                       'SLA_Due_Date__c, Is_SLA_Breached__c, AI_Sentiment__c, ' +
                       'CreatedDate, Resolved_Date__c, CSAT_Score__c ' +
                       'FROM Support_Ticket__c WHERE Id != null ';

            if (String.isNotBlank(statusFilter)) {
                q += 'AND Status__c = \'' + OneopsSecurity.sanitise(statusFilter) + '\' ';
            }
            if (String.isNotBlank(priorityFilter)) {
                q += 'AND Priority__c = \'' + OneopsSecurity.sanitise(priorityFilter) + '\' ';
            }
            if (agentId != null) {
                q += 'AND Assigned_Agent__c = \'' + agentId + '\' ';
            }

            q += 'ORDER BY Priority__c DESC, CreatedDate ASC LIMIT :pageSize OFFSET :offset';

            List<Support_Ticket__c> tickets = Database.query(q);

            String countQ = 'SELECT COUNT() FROM Support_Ticket__c WHERE Id != null';
            if (String.isNotBlank(statusFilter)) countQ += ' AND Status__c = \'' + OneopsSecurity.sanitise(statusFilter) + '\'';
            Integer total = Database.countQuery(countQ);

            return OneOpsResponseWrapper.paginated(tickets, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getTicketById(Id ticketId) {
        try {
            OneopsSecurity.requireRead(Support_Ticket__c.SObjectType);
            List<Support_Ticket__c> tickets = [
                SELECT Id, Name, Account__c, Account__r.Name, Contact__c, Contact__r.Name,
                       Subject, Description__c, Resolution__c, Priority__c, Status__c,
                       Category__c, Channel__c, Assigned_Agent__c, Assigned_Agent__r.Name,
                       SLA_Due_Date__c, Is_SLA_Breached__c, AI_Suggested_Solution__c,
                       AI_Sentiment__c, CSAT_Score__c,
                       CreatedDate, Resolved_Date__c, First_Response_Date__c
                FROM Support_Ticket__c WHERE Id = :ticketId WITH USER_MODE LIMIT 1
            ];
            if (tickets.isEmpty()) throw OneOpsException.notFound('Support Ticket', ticketId);

            List<Ticket_Comment__c> comments = [
                SELECT Id, Body__c, Author_Type__c, Is_Internal__c, Is_AI_Generated__c,
                       CreatedById, CreatedBy.Name, CreatedDate
                FROM Ticket_Comment__c
                WHERE Support_Ticket__c = :ticketId
                WITH USER_MODE ORDER BY CreatedDate ASC
            ];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'ticket'   => tickets[0],
                'comments' => comments
            }).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Ticket Actions ─────────────────────────────────────────────────────

    public static OneOpsResponseWrapper resolveTicket(Id ticketId, String resolution) {
        try {
            OneopsSecurity.requireUpdate(Support_Ticket__c.SObjectType);
            if (String.isBlank(resolution)) {
                throw OneOpsException.validation('resolution', 'Resolution notes are required to close a ticket.');
            }

            update new Support_Ticket__c(
                Id             = ticketId,
                Status__c      = 'Resolved',
                Resolution__c  = resolution,
                Resolved_Date__c = DateTime.now()
            );

            OneOpsLogger.audit(MODULE, 'TICKET_RESOLVE', ticketId, 'Support_Ticket__c', 'Ticket resolved.');

            // Trigger CSAT survey workflow
            NotificationService.sendCSATSurvey(ticketId);

            return OneOpsResponseWrapper.ok(null, 'Ticket resolved.').withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper addComment(Id ticketId, String body, Boolean isInternal) {
        try {
            OneopsSecurity.requireCreate(Ticket_Comment__c.SObjectType);
            if (String.isBlank(body)) {
                throw OneOpsException.validation('body', 'Comment body cannot be empty.');
            }

            Ticket_Comment__c comment = new Ticket_Comment__c(
                Support_Ticket__c = ticketId,
                Body__c           = body,
                Author_Type__c    = 'Agent',
                Is_Internal__c    = isInternal
            );
            insert comment;

            // Set first response date if not set
            List<Support_Ticket__c> tkt = [
                SELECT Id, First_Response_Date__c, Status__c
                FROM Support_Ticket__c WHERE Id = :ticketId WITH USER_MODE LIMIT 1
            ];
            if (!tkt.isEmpty() && tkt[0].First_Response_Date__c == null) {
                update new Support_Ticket__c(
                    Id = ticketId,
                    First_Response_Date__c = DateTime.now(),
                    Status__c = tkt[0].Status__c == 'New' ? 'Open' : tkt[0].Status__c
                );
            }

            return OneOpsResponseWrapper.created(comment).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── SLA Dashboard ──────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getSLAMetrics() {
        try {
            Integer openTotal    = [SELECT COUNT() FROM Support_Ticket__c WHERE Status__c NOT IN ('Resolved', 'Closed') WITH USER_MODE];
            Integer breached     = [SELECT COUNT() FROM Support_Ticket__c WHERE Is_SLA_Breached__c = true AND Status__c NOT IN ('Resolved', 'Closed') WITH USER_MODE];
            Integer resolvedToday = [SELECT COUNT() FROM Support_Ticket__c WHERE Status__c = 'Resolved' AND DAY_ONLY(Resolved_Date__c) = TODAY WITH USER_MODE];

            AggregateResult[] avgCsat = [SELECT AVG(CSAT_Score__c) avgScore FROM Support_Ticket__c WHERE CSAT_Score__c != null WITH USER_MODE];
            Decimal csatAvg = avgCsat.isEmpty() ? 0 : (Decimal) avgCsat[0].get('avgScore');

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'openTickets'    => openTotal,
                'slaBreached'    => breached,
                'resolvedToday'  => resolvedToday,
                'slaCompliance'  => openTotal > 0 ? Math.round(((openTotal - breached) * 100.0) / openTotal) : 100,
                'avgCsat'        => csatAvg.setScale(1)
            }).withModule(MODULE);

        } catch (Exception ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static void validateTicketFields(Map<String, Object> fields) {
        if (String.isBlank((String) fields.get('subject'))) {
            throw OneOpsException.validation('subject', 'Ticket subject is required.');
        }
        if (String.isBlank((String) fields.get('description'))) {
            throw OneOpsException.validation('description', 'Ticket description is required.');
        }
    }

    private static DateTime calculateSLADueDate(String priority) {
        Integer hours;
        if (priority == OneOpsConstants.PRIORITY_CRITICAL) hours = OneOpsConstants.SLA_CRITICAL_HOURS;
        else if (priority == OneOpsConstants.PRIORITY_HIGH)  hours = OneOpsConstants.SLA_HIGH_HOURS;
        else if (priority == OneOpsConstants.PRIORITY_LOW)   hours = OneOpsConstants.SLA_LOW_HOURS;
        else                                                   hours = OneOpsConstants.SLA_MEDIUM_HOURS;
        return DateTime.now().addHours(hours);
    }

    private static void autoAssignTicket(Id ticketId, String priority) {
        // Round-robin assignment to the agent with the fewest open Critical/High tickets
        List<AggregateResult> agentLoad = [
            SELECT Assigned_Agent__c agentId, COUNT(Id) cnt
            FROM Support_Ticket__c
            WHERE Status__c NOT IN ('Resolved', 'Closed')
            AND   Assigned_Agent__c != null
            WITH USER_MODE
            GROUP BY Assigned_Agent__c ORDER BY COUNT(Id) ASC LIMIT 1
        ];

        if (!agentLoad.isEmpty()) {
            Id agentId = (Id) agentLoad[0].get('agentId');
            update new Support_Ticket__c(Id = ticketId, Assigned_Agent__c = agentId, Status__c = 'Open');
        }
    }
}
