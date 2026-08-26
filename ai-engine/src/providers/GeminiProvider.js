const { GoogleGenerativeAI } = require('@google/generative-ai');
const AIProvider = require('./AIProvider');
const logger     = require('../utils/logger');

class GeminiProvider extends AIProvider {
    constructor(config) {
        super(config);
        this.name  = 'gemini';
        this.genAI = new GoogleGenerativeAI(config.apiKey);
    }

    isAvailable() {
        return !!this.config.apiKey;
    }

    async complete(systemPrompt, userPrompt, options = {}) {
        const modelName = options.model || this.config.model || 'gemini-1.5-flash';
        const model     = this.genAI.getGenerativeModel({
            model: modelName,
            systemInstruction: systemPrompt
        });

        const start    = Date.now();
        const result   = await model.generateContent(userPrompt);
        const latency  = Date.now() - start;
        const text     = result.response.text();

        logger.debug({ provider: 'gemini', model: modelName, latency }, 'AI call complete');

        return {
            text,
            usage: { inputTokens: 0, outputTokens: 0 }
        };
    }
}

module.exports = GeminiProvider;
