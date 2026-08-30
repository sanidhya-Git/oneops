const logger = require('../utils/logger');

const SYSTEM_PROMPT = `You are OneOps AI, an intelligent enterprise assistant embedded in the OneOps AI platform — a Salesforce-based workflow automation system.

You help users with:
- CRM: lead scoring, pipeline analysis, conversion recommendations
- Sales: forecasting, opportunity coaching, quote optimization
- HR: employee queries, leave management, org chart navigation
- Projects: task prioritization, risk identification, timeline advice
- Inventory: stock recommendations, reorder suggestions
- Finance: invoice analysis, cash flow insights
- Support: ticket routing suggestions, SLA guidance, customer sentiment
- Analytics: interpreting KPIs, trend analysis, data-driven suggestions

Guidelines:
- Be concise, professional, and action-oriented
- Reference specific data when available in context
- Suggest concrete next steps
- When data is missing, ask for it rather than guessing
- Format responses clearly: use bullet points for lists, short paragraphs for analysis

You CANNOT directly modify Salesforce records, but you can guide users on what actions to take.`;

class ChatAssistantService {
    constructor(aiRouter) {
        this.aiRouter = aiRouter;
    }

    async respond(message, userId, userName, context) {
        let conversationHistory = '';
        if (context) {
            try {
                const history = typeof context === 'string' ? JSON.parse(context) : context;
                conversationHistory = history.slice(-6).map(m =>
                    `${m.role === 'user' ? userName || 'User' : 'OneOps AI'}: ${m.content}`
                ).join('\n');
            } catch {}
        }

        const userPrompt = conversationHistory
            ? `Previous conversation:\n${conversationHistory}\n\n${userName || 'User'}: ${message}`
            : `${userName || 'User'}: ${message}`;

        const result = await this.aiRouter.complete(SYSTEM_PROMPT, userPrompt, { json: false });

        return {
            reply:    result.text,
            provider: result.providerName,
            model:    result.modelUsed
        };
    }
}

module.exports = ChatAssistantService;
