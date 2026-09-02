'use strict';

const logger = require('../utils/logger');

class WorkflowService {

    constructor(providerRouter) {
        this.router = providerRouter;
    }

    async suggestWorkflow(module, trigger, recordId) {
        const systemPrompt = `You are an enterprise workflow automation expert for the OneOps AI platform.
Given a module, trigger event, and record context, suggest a practical automation workflow.
Return JSON with: { "workflowName", "steps": [{ "order", "action", "config" }], "estimatedTimeSaved", "complexity" }`;

        const userPrompt = `Suggest a workflow automation for:
Module: ${module}
Trigger: ${trigger}
Record ID: ${recordId || 'new record'}

Return a practical, production-ready workflow with 2-5 steps.`;

        const result = await this.router.routeWithFallback(systemPrompt, userPrompt, { json: true });
        return result;
    }

    async analyseWorkflowLogs(logs) {
        const systemPrompt = `You are a workflow analytics expert. Analyse workflow execution logs to identify bottlenecks,
failure patterns, and optimization opportunities. Return JSON with: { "issues": [], "recommendations": [], "avgDurationMs", "failureRate" }`;

        const summary = logs.slice(0, 50).map(l => ({
            name:       l.Workflow_Name__c,
            status:     l.Status__c,
            durationMs: l.Duration_Ms__c,
            module:     l.Module__c
        }));

        const result = await this.router.routeWithFallback(
            systemPrompt,
            `Analyse these workflow execution logs:\n${JSON.stringify(summary, null, 2)}`,
            { json: true }
        );
        return result;
    }
}

module.exports = WorkflowService;
