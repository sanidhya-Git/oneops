const ChatAssistantService = require('../services/ChatAssistantService');

function buildRouter(overrides = {}) {
    return {
        complete: jest.fn().mockResolvedValue({
            text: 'Here is the AI reply.',
            providerName: 'openai',
            modelUsed: 'gpt-4o',
            ...overrides
        })
    };
}

describe('ChatAssistantService — respond()', () => {
    it('calls aiRouter.complete', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('Hello', 'user1', 'Alice', null);
        expect(router.complete).toHaveBeenCalled();
    });

    it('returns reply from router result', async () => {
        const router = buildRouter({ text: 'You have 5 hot leads.' });
        const svc = new ChatAssistantService(router);
        const result = await svc.respond('Show hot leads', 'user1', 'Alice', null);
        expect(result.reply).toBe('You have 5 hot leads.');
    });

    it('returns provider from router result', async () => {
        const router = buildRouter({ providerName: 'claude' });
        const svc = new ChatAssistantService(router);
        const result = await svc.respond('Hello', 'u1', 'Alice', null);
        expect(result.provider).toBe('claude');
    });

    it('returns model from router result', async () => {
        const router = buildRouter({ modelUsed: 'claude-sonnet-4-6' });
        const svc = new ChatAssistantService(router);
        const result = await svc.respond('Hello', 'u1', 'Alice', null);
        expect(result.model).toBe('claude-sonnet-4-6');
    });

    it('includes user message in prompt', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('What is the pipeline?', 'user1', 'Alice', null);
        const [, userPrompt] = router.complete.mock.calls[0];
        expect(userPrompt).toContain('What is the pipeline?');
    });

    it('includes userName in prompt', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('Hello', 'user1', 'Bob', null);
        const [, userPrompt] = router.complete.mock.calls[0];
        expect(userPrompt).toContain('Bob');
    });

    it('uses "User" when userName is not provided', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('Hello', 'user1', null, null);
        const [, userPrompt] = router.complete.mock.calls[0];
        expect(userPrompt).toContain('User');
    });

    it('includes conversation history when context is provided', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        const context = JSON.stringify([
            { role: 'user', content: 'Previous question' },
            { role: 'ai',   content: 'Previous answer' }
        ]);
        await svc.respond('Follow up', 'user1', 'Alice', context);
        const [, userPrompt] = router.complete.mock.calls[0];
        expect(userPrompt).toContain('Previous question');
        expect(userPrompt).toContain('Previous answer');
    });

    it('handles object context (not just string)', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        const context = [{ role: 'user', content: 'Earlier message' }];
        await svc.respond('Follow up', 'user1', 'Alice', context);
        expect(router.complete).toHaveBeenCalled();
    });

    it('limits conversation history to last 6 messages', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        const history = Array.from({ length: 10 }, (_, i) => ({
            role: i % 2 === 0 ? 'user' : 'ai',
            content: `Message ${i}`
        }));
        await svc.respond('New message', 'user1', 'Alice', JSON.stringify(history));
        const [, userPrompt] = router.complete.mock.calls[0];
        // Should contain last 6 messages
        expect(userPrompt).toContain('Message 9');
        expect(userPrompt).toContain('Message 4');
        // Should NOT contain very early messages
        expect(userPrompt).not.toContain('Message 0');
    });

    it('handles invalid JSON context gracefully', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('Hello', 'user1', 'Alice', 'not-valid-json');
        expect(router.complete).toHaveBeenCalled();
    });

    it('passes json: false option to router', async () => {
        const router = buildRouter();
        const svc = new ChatAssistantService(router);
        await svc.respond('Hello', 'user1', 'Alice', null);
        const [, , options] = router.complete.mock.calls[0];
        expect(options.json).toBe(false);
    });
});
