/**
 * Abstract AI Provider base class.
 * All providers must implement: complete(systemPrompt, userPrompt, options)
 */
class AIProvider {
    constructor(config) {
        if (new.target === AIProvider) {
            throw new Error('AIProvider is abstract — instantiate a concrete subclass.');
        }
        this.config = config;
        this.name   = 'abstract';
    }

    /**
     * Send a completion request.
     * @param {string} systemPrompt
     * @param {string} userPrompt
     * @param {Object} options — { maxTokens, temperature, json: boolean }
     * @returns {Promise<{ text: string, usage: { inputTokens, outputTokens } }>}
     */
    async complete(systemPrompt, userPrompt, options = {}) {
        throw new Error('complete() must be implemented by subclass.');
    }

    /**
     * Helper: attempt JSON parse with fallback to raw text.
     */
    parseJSON(text) {
        try {
            const clean = text.replace(/^```(?:json)?/m, '').replace(/```$/m, '').trim();
            return JSON.parse(clean);
        } catch {
            return { raw: text };
        }
    }

    isAvailable() {
        throw new Error('isAvailable() must be implemented by subclass.');
    }
}

module.exports = AIProvider;
