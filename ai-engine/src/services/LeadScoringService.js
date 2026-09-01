const logger = require('../utils/logger');

const SYSTEM_PROMPT = `You are an expert B2B sales AI scoring leads for enterprise software.
Evaluate the lead and return a JSON object with:
- score (0-100): lead quality score
- reason (string): 2-3 sentence explanation of the score
- emailDraft (string): personalized follow-up email in HTML

Score criteria:
- 80-100: Perfect ICP match, large company, decision-maker, high intent
- 60-79: Good fit, mid-market, some qualification signals
- 40-59: Potential fit, needs nurturing
- 0-39: Poor fit or incomplete data

Respond ONLY with valid JSON.`;

class LeadScoringService {
    constructor(aiRouter) {
        this.aiRouter = aiRouter;
    }

    async score(leadData) {
        const prompt = `Score this B2B lead:
Company: ${leadData.company || 'Unknown'}
Industry: ${leadData.industry || 'Unknown'}
Annual Revenue: ${leadData.annualRevenue ? '$' + leadData.annualRevenue.toLocaleString() : 'Unknown'}
Employees: ${leadData.numberOfEmployees || 'Unknown'}
Lead Source: ${leadData.leadSource || 'Unknown'}
Current Status: ${leadData.currentStatus || 'New'}
Email: ${leadData.email || 'Unknown'}

Return JSON: { "score": number, "reason": string, "emailDraft": string }`;

        const result = await this.aiRouter.complete(SYSTEM_PROMPT, prompt, { json: true });
        const parsed = result.providerName === 'gemini'
            ? JSON.parse(result.text.replace(/^```json?\n?/, '').replace(/\n?```$/, ''))
            : JSON.parse(result.text);

        return {
            score:      Math.min(100, Math.max(0, parseInt(parsed.score, 10) || 0)),
            reason:     parsed.reason     || 'AI scoring complete.',
            emailDraft: parsed.emailDraft || '',
            provider:   result.providerName,
            confidence: this._scoreToConfidence(parsed.score)
        };
    }

    _scoreToConfidence(score) {
        if (score >= 80) return 92;
        if (score >= 60) return 82;
        if (score >= 40) return 70;
        return 55;
    }
}

module.exports = LeadScoringService;
