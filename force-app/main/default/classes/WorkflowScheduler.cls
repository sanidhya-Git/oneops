/**
 * WorkflowScheduler — fires WorkflowEngine.runScheduledWorkflows every 15 minutes.
 *
 * Deploy via anonymous Apex:
 *   WorkflowScheduler.schedule();
 */
global with sharing class WorkflowScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        try {
            WorkflowEngine.runScheduledWorkflows();
        } catch (Exception e) {
            OneOpsLogger.error('WorkflowScheduler', e.getMessage());
        }
    }

    public static void schedule() {
        // Abort existing jobs with this name
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'OneOps Workflow Engine'
            WITH USER_MODE
        ]) {
            System.abortJob(ct.Id);
        }

        // Every 15 minutes: 0, 15, 30, 45
        for (Integer minute : new List<Integer>{ 0, 15, 30, 45 }) {
            System.schedule(
                'OneOps Workflow Engine ' + minute,
                '0 ' + minute + ' * * * ?',
                new WorkflowScheduler()
            );
        }
    }
}
