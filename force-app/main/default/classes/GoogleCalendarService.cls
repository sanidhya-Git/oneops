/**
 * GoogleCalendarService — Google Calendar API integration.
 * Named Credential: OneOps_Google_Calendar (OAuth 2.0 user credentials)
 * Creates, updates, and lists events; syncs with Leave Requests and Project Milestones.
 */
public with sharing class GoogleCalendarService {

    private static final String NC_BASE  = 'callout:OneOps_Google_Calendar';
    private static final String CAL_PATH = '/calendar/v3/calendars/primary/events';

    /* ─── Create calendar event ──────────────────────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper createEvent(String summary, String description,
                                                     Datetime startDt, Datetime endDt,
                                                     List<String> attendeeEmails) {
        try {
            Map<String, Object> event = buildEventPayload(summary, description, startDt, endDt, attendeeEmails);
            HttpResponse res = post(CAL_PATH + '?sendUpdates=all', event);

            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                return OneOpsResponseWrapper.error('Google Calendar error: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            OneOpsLogger.audit('GoogleCalendarService', 'Event created: ' + created.get('id'));
            return OneOpsResponseWrapper.success(created);

        } catch (Exception e) {
            OneOpsLogger.error('GoogleCalendarService.createEvent', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /**
     * Sync an approved leave request to Google Calendar.
     */
    @AuraEnabled
    public static OneOpsResponseWrapper syncLeaveToCalendar(Id leaveRequestId) {
        try {
            Leave_Request__c lr = [
                SELECT Employee__r.Full_Name__c, Employee__r.Email__c,
                       Leave_Type__c, Start_Date__c, End_Date__c, Reason__c
                FROM Leave_Request__c
                WHERE Id = :leaveRequestId
                WITH USER_MODE
                LIMIT 1
            ];

            String summary = lr.Employee__r.Full_Name__c + ' — ' + lr.Leave_Type__c;
            Datetime startDt = Datetime.newInstance(lr.Start_Date__c, Time.newInstance(0, 0, 0, 0));
            Datetime endDt   = Datetime.newInstance(lr.End_Date__c.addDays(1), Time.newInstance(0, 0, 0, 0));
            List<String> attendees = new List<String>{ lr.Employee__r.Email__c };

            return createEvent(summary, lr.Reason__c, startDt, endDt, attendees);

        } catch (Exception e) {
            OneOpsLogger.error('GoogleCalendarService.syncLeaveToCalendar', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_SYSTEM, 500);
        }
    }

    /**
     * List upcoming events.
     */
    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getUpcomingEvents(Integer maxResults) {
        try {
            String timeMin = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String path    = CAL_PATH + '?maxResults=' + (maxResults != null ? maxResults : 10)
                           + '&orderBy=startTime&singleEvents=true&timeMin='
                           + EncodingUtil.urlEncode(timeMin, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_BASE + path);
            req.setMethod('GET');
            req.setTimeout(10000);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Calendar API error: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }
            return OneOpsResponseWrapper.success(
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody())
            );
        } catch (Exception e) {
            OneOpsLogger.error('GoogleCalendarService.getUpcomingEvents', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /* ─── Private helpers ────────────────────────────────────────── */

    private static Map<String, Object> buildEventPayload(String summary, String description,
                                                          Datetime startDt, Datetime endDt,
                                                          List<String> emails) {
        List<Map<String, Object>> attendees = new List<Map<String, Object>>();
        if (emails != null) {
            for (String email : emails) {
                attendees.add(new Map<String, Object>{ 'email' => email });
            }
        }
        return new Map<String, Object>{
            'summary'     => summary,
            'description' => description,
            'start'       => new Map<String, Object>{
                'dateTime' => startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'timeZone' => 'UTC'
            },
            'end'         => new Map<String, Object>{
                'dateTime' => endDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'timeZone' => 'UTC'
            },
            'attendees'   => attendees
        };
    }

    private static HttpResponse post(String path, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_BASE + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(10000);
        req.setBody(JSON.serialize(body));
        return new Http().send(req);
    }
}
