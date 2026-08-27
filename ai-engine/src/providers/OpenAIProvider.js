const OpenAI  = require('openai');
const AIProvider = require('./AIProvider');
const logger     = require('../utils/logger');

class OpenAIProvider extends AIProvider {
    constructor(config) {
        super(config);
        this.name   = 'openai';
        this.client = new OpenAI({ apiKey: config.apiKey });
    }

    isAvailable() {
        return !!this.config.apiKey;
    }

    async complete(systemPrompt, userPrompt, options = {}) {
        const model       = options.model || this.config.model;
        const maxTokens   = options.maxTokens   || this.config.maxTokens   || 2048;
        const temperature = options.temperature ?? this.config.temperature ?? 0.2;

        const messages = [
            { role: 'system', content: systemPrompt },
            { role: 'user',   content: userPrompt }
        ];

        const reqBody = {
            model,
            messages,
            max_tokens:  maxTokens,
            temperature
        };

        // Request JSON output when caller needs structured data
        if (options.json) {
            reqBody.response_format = { type: 'json_object' };
        }

        const start    = Date.now();
        const response = await this.client.chat.completions.create(reqBody);
        const latency  = Date.now() - start;

        const text = response.choices[0]?.message?.content || '';
        logger.debug({ provider: 'openai', model, latency, tokens: response.usage }, 'AI call complete');

        return {
            text,
            usage: {
                inputTokens:  response.usage?.prompt_tokens     || 0,
                outputTokens: response.usage?.completion_tokens || 0
            }
        };
    }
}

module.exports = OpenAIProvider;
