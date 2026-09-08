const LeadScoringService = require('../services/LeadScoringService');

function buildMockRouter(overrides = {}) {
    return {
        complete: jest.fn().mockResolvedValue({
            text: JSON.stringify({ score: 75, reason: 'Good fit', emailDraft: '<p>Hello</p>' }),
            providerName: 'claude',
            modelUsed: 'claude-sonnet-4-6',
            ...overrides
        })
    };
}

describe('LeadScoringService — score()', () => {
    it('calls aiRouter.complete with a prompt containing company name', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        await svc.score({ company: 'Acme Corp', industry: 'Technology' });
        expect(router.complete).toHaveBeenCalled();
        const [, userPrompt] = router.complete.mock.calls[0];
        expect(userPrompt).toContain('Acme Corp');
        expect(userPrompt).toContain('Technology');
    });

    it('returns parsed score between 0 and 100', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        const result = await svc.score({ company: 'Acme' });
        expect(result.score).toBeGreaterThanOrEqual(0);
        expect(result.score).toBeLessThanOrEqual(100);
        expect(result.score).toBe(75);
    });

    it('returns reason from AI response', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        const result = await svc.score({ company: 'Test' });
        expect(result.reason).toBe('Good fit');
    });

    it('returns emailDraft from AI response', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        const result = await svc.score({ company: 'Test' });
        expect(result.emailDraft).toBe('<p>Hello</p>');
    });

    it('returns provider name from router result', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        const result = await svc.score({ company: 'Test' });
        expect(result.provider).toBe('claude');
    });

    it('clamps score to 0 when AI returns negative value', async () => {
        const router = buildMockRouter({ text: JSON.stringify({ score: -10, reason: 'Bad', emailDraft: '' }) });
        const svc = new LeadScoringService(router);
        const result = await svc.score({});
        expect(result.score).toBe(0);
    });

    it('clamps score to 100 when AI returns value > 100', async () => {
        const router = buildMockRouter({ text: JSON.stringify({ score: 150, reason: 'Great', emailDraft: '' }) });
        const svc = new LeadScoringService(router);
        const result = await svc.score({});
        expect(result.score).toBe(100);
    });

    it('defaults reason when AI returns no reason', async () => {
        const router = buildMockRouter({ text: JSON.stringify({ score: 50 }) });
        const svc = new LeadScoringService(router);
        const result = await svc.score({});
        expect(result.reason).toBeTruthy();
    });

    it('handles gemini provider JSON with code fences', async () => {
        const router = {
            complete: jest.fn().mockResolvedValue({
                text: '```json\n{"score": 65, "reason": "Decent fit", "emailDraft": "<p>Hi</p>"}\n```',
                providerName: 'gemini'
            })
        };
        const svc = new LeadScoringService(router);
        const result = await svc.score({ company: 'Test' });
        expect(result.score).toBe(65);
        expect(result.reason).toBe('Decent fit');
    });

    it('includes all lead fields in prompt', async () => {
        const router = buildMockRouter();
        const svc = new LeadScoringService(router);
        await svc.score({
            company: 'Mega Corp',
            industry: 'Healthcare',
            annualRevenue: 5000000,
            numberOfEmployees: 500,
            leadSource: 'Web',
            currentStatus: 'Hot',
            email: 'test@mega.com'
        });
        const [, prompt] = router.complete.mock.calls[0];
        expect(prompt).toContain('Mega Corp');
        expect(prompt).toContain('Healthcare');
        expect(prompt).toContain('5,000,000');
        expect(prompt).toContain('500');
        expect(prompt).toContain('Web');
        expect(prompt).toContain('test@mega.com');
    });
});

describe('LeadScoringService — _scoreToConfidence()', () => {
    let svc;
    beforeEach(() => {
        svc = new LeadScoringService({ complete: jest.fn() });
    });

    it('returns 92 for score >= 80', () => {
        expect(svc._scoreToConfidence(80)).toBe(92);
        expect(svc._scoreToConfidence(95)).toBe(92);
        expect(svc._scoreToConfidence(100)).toBe(92);
    });

    it('returns 82 for score 60-79', () => {
        expect(svc._scoreToConfidence(60)).toBe(82);
        expect(svc._scoreToConfidence(70)).toBe(82);
        expect(svc._scoreToConfidence(79)).toBe(82);
    });

    it('returns 70 for score 40-59', () => {
        expect(svc._scoreToConfidence(40)).toBe(70);
        expect(svc._scoreToConfidence(55)).toBe(70);
        expect(svc._scoreToConfidence(59)).toBe(70);
    });

    it('returns 55 for score below 40', () => {
        expect(svc._scoreToConfidence(39)).toBe(55);
        expect(svc._scoreToConfidence(0)).toBe(55);
        expect(svc._scoreToConfidence(20)).toBe(55);
    });
});
