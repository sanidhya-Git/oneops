const Anthropic = require('@anthropic-ai/sdk');
const AIProvider = require('./AIProvider');
const logger     = require('../utils/logger');

class ClaudeProvider extends AIProvider {
    constructor(config) {
        super(config);
        this.name   = 'claude';
        this.client = new Anthropic({ apiKey: config.apiKey });
    }

    isAvailable() {
        return !!this.config.apiKey;
    }

    async complete(systemPrompt, userPrompt, options = {}) {
        const model       = options.model || this.config.model || 'claude-sonnet-4-6';
        const maxTokens   = options.maxTokens   || this.config.maxTokens   || 2048;
        const temperature = options.temperature ?? this.config.temperature ?? 0.2;

        const start    = Date.now();
        const response = await this.client.messages.create({
            model,
            max_tokens: maxTokens,
            system:     systemPrompt,
            messages:   [{ role: 'user', content: userPrompt }]
        });
        const latency = Date.now() - start;

        const text = response.content.map(b => b.type === 'text' ? b.text : '').join('');
        logger.debug({ provider: 'claude', model, latency }, 'AI call complete');

        return {
            text,
            usage: {
                inputTokens:  response.usage?.input_tokens  || 0,
                outputTokens: response.usage?.output_tokens || 0
            }
        };
    }
}

module.exports = ClaudeProvider;
