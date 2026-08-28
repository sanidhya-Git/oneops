const express         = require('express');
const router          = express.Router();
const config          = require('../config');
const logger          = require('../utils/logger');
const OpenAIProvider  = require('../providers/OpenAIProvider');
const ClaudeProvider  = require('../providers/ClaudeProvider');
const GeminiProvider  = require('../providers/GeminiProvider');
const LeadScoringService  = require('../services/LeadScoringService');
const ChatAssistantService = require('../services/ChatAssistantService');

// ── Build provider chain ───────────────────────────────────────
function buildProviders() {
    const map = {
        openai: () => new OpenAIProvider(config.providers.openai),
        claude: () => new ClaudeProvider(config.providers.claude),
        gemini: () => new GeminiProvider(config.providers.gemini)
    };
    return config.providers.order
        .map(name => map[name]?.())
        .filter(p => p && p.isAvailable());
}

// ── AI Router: attempts providers in order, falls back on error ─
async function routeWithFallback(systemPrompt, userPrompt, options = {}) {
    const providers = buildProviders();
    if (!providers.length) throw new Error('No AI providers configured or available.');

    for (const provider of providers) {
        try {
            const result = await provider.complete(systemPrompt, userPrompt, options);
            return { ...result, providerName: provider.name, modelUsed: options.model || config.providers[provider.name]?.model };
        } catch (err) {
            logger.warn({ provider: provider.name, error: err.message }, 'Provider failed, trying next');
        }
    }
    throw new Error('All AI providers failed.');
}

// ── Shared AI router object for services ───────────────────────
const aiRouter = { complete: routeWithFallback };

// ── Main process endpoint ──────────────────────────────────────
router.post('/process', async (req, res, next) => {
    const { action, ...payload } = req.body || {};
    if (!action) {
        return res.status(400).json({ success: false, error: 'action field is required.' });
    }

    const start = Date.now();
    logger.info({ action, orgId: req.orgId, requestId: req.requestId }, 'AI request received');

    try {
        let data, providerName, confidence = 0;

        switch (action) {

            case 'score_lead': {
                const result = await new LeadScoringService(aiRouter).score(payload);
                data         = { score: result.score, reason: result.reason, emailDraft: result.emailDraft };
                providerName = result.provider;
                confidence   = result.confidence;
                break;
            }

            case 'chat': {
                const result = await new ChatAssistantService(aiRouter).respond(
                    payload.message, payload.userId, payload.userName, payload.context
                );
                data         = { reply: result.reply };
                providerName = result.provider;
                confidence   = 90;
                break;
            }

            case 'generate_email': {
                const sys = 'You are an expert B2B sales copywriter. Write a personalized, professional follow-up email in HTML. Keep it under 200 words. Be specific and relevant to the company/industry.';
                const usr = `Write a follow-up email for: ${payload.recipientName} at ${payload.company} (${payload.industry}). Tone: ${payload.tone || 'professional'}. Context: ${payload.context || 'Initial outreach'}. Their AI lead score is ${payload.aiScore || 'unknown'}/100.`;
                const result = await routeWithFallback(sys, usr, { json: false });
                data         = { emailHtml: result.text };
                providerName = result.providerName;
                confidence   = 85;
                break;
            }

            case 'analyse_ticket': {
                const sys = 'You are a customer support AI. Analyse the ticket and return JSON: { "sentiment": "Positive|Neutral|Negative|Frustrated", "suggestion": string (recommended resolution), "agentNote": string (internal note for agent) }. Be specific and actionable.';
                const usr = `Ticket: "${payload.subject}"\nDescription: "${payload.description}"\nCategory: ${payload.category}\nPriority: ${payload.priority}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = result.providerName === 'gemini'
                    ? JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''))
                    : JSON.parse(result.text);
                data         = parsed;
                providerName = result.providerName;
                confidence   = 80;
                break;
            }

            case 'summarize': {
                const type = payload.summaryType || 'executive';
                const sys  = `You are a document analyst. Produce a ${type} summary.${type === 'executive' ? ' Focus on key decisions, risks, and action items. Use bullet points.' : ''}`;
                const result = await routeWithFallback(sys, `Summarize:\n\n${payload.text}`, { json: false });
                data         = { summary: result.text };
                providerName = result.providerName;
                confidence   = 88;
                break;
            }

            case 'predict': {
                const sys = 'You are a business intelligence AI. Analyze the provided data and return actionable predictions in JSON format with fields: predictions (array), risks (array), opportunities (array), confidence (0-100).';
                const usr = `Module: ${payload.module}\nContext: ${JSON.stringify(payload.context || {})}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = parsed.confidence || 75;
                break;
            }

            case 'vendor_scorecard': {
                const sys = 'You are a procurement AI. Evaluate vendor performance and return JSON: { "performanceScore": number (0-100), "strengths": array, "risks": array, "recommendation": string }.';
                const usr = `Vendor: ${payload.vendorName}\nTotal POs: ${payload.totalPOs}\nOn-time: ${payload.onTimePOs}\nTotal Spend: $${payload.totalSpend}\nCurrent Score: ${payload.currentScore}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = 82;
                break;
            }

            case 'suggest_workflow': {
                const sys = 'You are a Salesforce workflow automation expert. Given a trigger event and context, suggest the most valuable automation workflows. Return JSON: { "workflows": [{ "name": string, "trigger": string, "actions": array, "impact": string }] }.';
                const usr = `Trigger: ${payload.triggerEvent}\nObject: ${payload.objectType}\nContext: ${JSON.stringify(payload.recordContext || {})}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = 78;
                break;
            }

            case 'reorder_suggestions': {
                const sys = 'You are an inventory optimization AI. Analyze low stock items and return JSON: { "suggestions": [{ "itemId": string, "suggestedQuantity": number, "urgency": "Critical|High|Medium", "reasoning": string }] }.';
                const usr = `Low stock items:\n${JSON.stringify(payload.items)}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = 80;
                break;
            }

            case 'project_health': {
                const sys = 'You are a project management AI. Assess project health and return JSON: { "healthScore": number (0-100), "riskAssessment": string (2-3 sentences), "recommendations": array }.';
                const usr = `Project status: ${payload.status}\nCompletion: ${payload.completionPercent}%\nBudget vs Actual: ${payload.budget} vs ${payload.actualCost}\nBlocked tasks: ${payload.blockedTasks}/${payload.totalTasks}\nDays to deadline: ${payload.daysToDeadline || 'unknown'}`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = 85;
                break;
            }

            case 'sales_forecast': {
                const sys = 'You are a sales forecasting AI. Analyze pipeline data and return JSON: { "predictedRevenue": number, "confidence": number, "keyRisks": array, "insights": string }.';
                const result = await routeWithFallback(sys, `Period: ${payload.fromDate} to ${payload.toDate}\nData: ${payload.forecastData}`, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = parsed.confidence || 78;
                break;
            }

            case 'win_probability': {
                const sys = 'You are a sales AI. Predict win probability for this opportunity. Return JSON: { "aiProbability": number (0-100), "keyFactors": array, "nextBestAction": string }.';
                const usr = `Stage: ${payload.stage}\nAmount: $${payload.amount}\nDays to close: ${payload.daysToClose}\nIndustry: ${payload.industry}\nCurrent probability: ${payload.currentProbability}%`;
                const result = await routeWithFallback(sys, usr, { json: true });
                const parsed = JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''));
                data         = parsed;
                providerName = result.providerName;
                confidence   = 82;
                break;
            }

            default:
                return res.status(400).json({ success: false, error: `Unknown action: ${action}` });
        }

        const latency = Date.now() - start;
        logger.info({ action, provider: providerName, latency, orgId: req.orgId }, 'AI request completed');

        res.json({
            success:    true,
            provider:   providerName,
            model:      config.providers[providerName]?.model || 'unknown',
            data,
            confidence,
            latencyMs:  latency,
            requestId:  req.requestId
        });

    } catch (err) {
        next(err);
    }
});

module.exports = router;
