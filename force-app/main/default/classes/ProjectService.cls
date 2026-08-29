/**
 * Project Service — Kanban board, Gantt, milestones, time tracking.
 * Supports drag-and-drop ordering via Kanban_Order__c.
 */
public with sharing class ProjectService {

    private static final String MODULE = OneOpsConstants.MODULE_PM;

    // ── Project CRUD ───────────────────────────────────────────────────────

    public static OneOpsResponseWrapper createProject(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Project__c.SObjectType);
            if (String.isBlank((String) fields.get('name'))) {
                throw OneOpsException.validation('name', 'Project name is required.');
            }

            Project__c project = new Project__c(
                Name                   = (String)  fields.get('name'),
                Project_Code__c        = generateProjectCode(),
                Account__c             = (Id)      fields.get('accountId'),
                Project_Manager__c     = fields.containsKey('pmId') ? (Id) fields.get('pmId') : UserInfo.getUserId(),
                Status__c              = 'Planning',
                Priority__c            = fields.containsKey('priority') ? (String) fields.get('priority') : OneOpsConstants.PRIORITY_MEDIUM,
                Start_Date__c          = fields.containsKey('startDate') ? Date.valueOf((String) fields.get('startDate')) : Date.today(),
                End_Date__c            = fields.containsKey('endDate') ? Date.valueOf((String) fields.get('endDate')) : null,
                Budget__c              = fields.containsKey('budget') ? Decimal.valueOf(String.valueOf(fields.get('budget'))) : null,
                Description__c         = (String)  fields.get('description')
            );

            insert project;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, project.Id, 'Project__c',
                'Project created: ' + project.Name);

            return OneOpsResponseWrapper.created(project).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createProject failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getProjects(String status, Integer pageNum, Integer pageSize) {
        try {
            OneopsSecurity.requireRead(Project__c.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, Project_Code__c, Account__c, Account__r.Name, ' +
                       'Project_Manager__c, Project_Manager__r.Name, Status__c, Priority__c, ' +
                       'Start_Date__c, End_Date__c, Budget__c, Actual_Cost__c, ' +
                       'Completion_Percentage__c, AI_Health_Score__c, AI_Risk_Assessment__c ' +
                       'FROM Project__c WHERE Id != null ';
            if (String.isNotBlank(status)) {
                q += 'AND Status__c = \'' + OneopsSecurity.sanitise(status) + '\' ';
            }
            q += 'ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset';

            List<Project__c> projects = Database.query(q);
            Integer total = [SELECT COUNT() FROM Project__c];

            return OneOpsResponseWrapper.paginated(projects, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Kanban Board ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static OneOpsResponseWrapper getKanbanBoard(Id projectId) {
        try {
            OneopsSecurity.requireRead(Project_Task__c.SObjectType);

            List<Project_Task__c> tasks = [
                SELECT Id, Name, Subject__c, Status__c, Priority__c,
                       Assigned_To__c, Assigned_To__r.Name,
                       Due_Date__c, Estimated_Hours__c, Actual_Hours__c,
                       Kanban_Order__c, Tags__c, Milestone__c, Milestone__r.Name,
                       Completed_Date__c
                FROM Project_Task__c
                WHERE Project__c = :projectId
                WITH USER_MODE
                ORDER BY Status__c, Kanban_Order__c NULLS LAST, CreatedDate
            ];

            // Group by status column
            Map<String, List<Project_Task__c>> board = new Map<String, List<Project_Task__c>>{
                'Backlog'      => new List<Project_Task__c>(),
                'To Do'        => new List<Project_Task__c>(),
                'In Progress'  => new List<Project_Task__c>(),
                'In Review'    => new List<Project_Task__c>(),
                'Done'         => new List<Project_Task__c>(),
                'Blocked'      => new List<Project_Task__c>()
            };

            for (Project_Task__c t : tasks) {
                if (board.containsKey(t.Status__c)) {
                    board.get(t.Status__c).add(t);
                }
            }

            return OneOpsResponseWrapper.ok(board).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    @AuraEnabled
    public static OneOpsResponseWrapper moveTask(Id taskId, String newStatus, Integer newOrder) {
        try {
            OneopsSecurity.requireUpdate(Project_Task__c.SObjectType);

            Project_Task__c toUpdate = new Project_Task__c(
                Id              = taskId,
                Status__c       = newStatus,
                Kanban_Order__c = newOrder
            );
            if (newStatus == 'Done') {
                toUpdate.Completed_Date__c = Date.today();
            }

            update toUpdate;
            return OneOpsResponseWrapper.ok(null, 'Task moved to ' + newStatus).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Task Management ────────────────────────────────────────────────────

    public static OneOpsResponseWrapper createTask(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Project_Task__c.SObjectType);

            if (fields.get('projectId') == null) throw OneOpsException.validation('projectId', 'Project is required.');
            if (String.isBlank((String) fields.get('subject'))) throw OneOpsException.validation('subject', 'Task subject is required.');

            Project_Task__c task = new Project_Task__c(
                Project__c       = (Id)    fields.get('projectId'),
                Subject__c       = (String) fields.get('subject'),
                Description__c   = (String) fields.get('description'),
                Assigned_To__c   = (Id)    fields.get('assignedTo'),
                Milestone__c     = (Id)    fields.get('milestoneId'),
                Status__c        = 'Backlog',
                Priority__c      = fields.containsKey('priority') ? (String) fields.get('priority') : OneOpsConstants.PRIORITY_MEDIUM,
                Due_Date__c      = fields.containsKey('dueDate') ? Date.valueOf((String) fields.get('dueDate')) : null,
                Estimated_Hours__c = fields.containsKey('estimatedHours') ? Decimal.valueOf(String.valueOf(fields.get('estimatedHours'))) : null,
                Tags__c          = (String) fields.get('tags')
            );

            insert task;
            return OneOpsResponseWrapper.created(task).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Time Tracking ──────────────────────────────────────────────────────

    public static OneOpsResponseWrapper logTime(Id taskId, Id employeeId, Date logDate, Decimal hours, Boolean billable, String notes) {
        try {
            OneopsSecurity.requireCreate(Time_Entry__c.SObjectType);
            if (hours <= 0 || hours > 24) {
                throw OneOpsException.validation('hours', 'Hours must be between 0.1 and 24.');
            }

            Time_Entry__c entry = new Time_Entry__c(
                Project_Task__c = taskId,
                Employee__c     = employeeId,
                Date__c         = logDate != null ? logDate : Date.today(),
                Hours__c        = hours,
                Is_Billable__c  = billable,
                Notes__c        = notes
            );
            insert entry;

            // Update task actual hours
            AggregateResult[] ag = [SELECT SUM(Hours__c) total FROM Time_Entry__c WHERE Project_Task__c = :taskId];
            Decimal total = ag.isEmpty() ? 0 : (Decimal)(ag[0].get('total') != null ? ag[0].get('total') : 0);
            update new Project_Task__c(Id = taskId, Actual_Hours__c = total);

            return OneOpsResponseWrapper.created(entry).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Project Health (AI) ────────────────────────────────────────────────

    public static OneOpsResponseWrapper getAIProjectHealth(Id projectId) {
        try {
            List<Project__c> projects = [
                SELECT Id, Name, Status__c, Start_Date__c, End_Date__c,
                       Budget__c, Actual_Cost__c, Completion_Percentage__c
                FROM Project__c WHERE Id = :projectId WITH USER_MODE LIMIT 1
            ];
            if (projects.isEmpty()) throw OneOpsException.notFound('Project', projectId);

            Integer taskCount    = [SELECT COUNT() FROM Project_Task__c WHERE Project__c = :projectId WITH USER_MODE];
            Integer blockedCount = [SELECT COUNT() FROM Project_Task__c WHERE Project__c = :projectId AND Status__c = 'Blocked' WITH USER_MODE];
            Integer doneCount    = [SELECT COUNT() FROM Project_Task__c WHERE Project__c = :projectId AND Status__c = 'Done' WITH USER_MODE];

            Map<String, Object> payload = new Map<String, Object>{
                'action'            => 'project_health',
                'projectId'         => projectId,
                'status'            => projects[0].Status__c,
                'startDate'         => String.valueOf(projects[0].Start_Date__c),
                'endDate'           => String.valueOf(projects[0].End_Date__c),
                'budget'            => projects[0].Budget__c,
                'actualCost'        => projects[0].Actual_Cost__c,
                'completionPercent' => projects[0].Completion_Percentage__c,
                'totalTasks'        => taskCount,
                'blockedTasks'      => blockedCount,
                'completedTasks'    => doneCount
            };

            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(payload);

            if (aiResp.success) {
                Integer healthScore = Integer.valueOf(aiResp.data.get('healthScore'));
                String riskAssessment = (String) aiResp.data.get('riskAssessment');

                update new Project__c(
                    Id = projectId,
                    AI_Health_Score__c = healthScore,
                    AI_Risk_Assessment__c = riskAssessment
                );
            }

            return OneOpsResponseWrapper.ok(aiResp.success ? aiResp.data : null).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static String generateProjectCode() {
        Integer cnt = [SELECT COUNT() FROM Project__c] + 1;
        return 'PRJ-' + String.valueOf(Date.today().year()) + '-' + String.valueOf(cnt).leftPad(4, '0');
    }
}
