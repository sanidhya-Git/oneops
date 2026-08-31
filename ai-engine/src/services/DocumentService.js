'use strict';

class DocumentService {

    constructor(providerRouter) {
        this.router = providerRouter;
    }

    async summarize(text, format = 'bullets') {
        const systemPrompt = `You are a business document analyst. Summarize documents concisely for enterprise users.
Return JSON with: { "summary", "keyPoints": [], "actionItems": [], "sentiment", "wordCount" }`;

        const trimmed = text?.slice(0, 6000) || '';

        const userPrompt = `Summarize the following document in ${format} format:\n\n${trimmed}`;

        return this.router.routeWithFallback(systemPrompt, userPrompt, { json: true });
    }

    async extractEntities(text) {
        const systemPrompt = `Extract named entities from business text.
Return JSON with: { "people": [], "companies": [], "dates": [], "amounts": [], "locations": [] }`;

        return this.router.routeWithFallback(
            systemPrompt,
            `Extract entities from:\n\n${(text || '').slice(0, 4000)}`,
            { json: true }
        );
    }
}

module.exports = DocumentService;
