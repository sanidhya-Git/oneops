const request  = require('supertest');
const express  = require('express');

// Mock AI providers BEFORE requiring the route module
jest.mock('../providers/OpenAIProvider');
jest.mock('../providers/ClaudeProvider');
jest.mock('../providers/GeminiProvider');
jest.mock('../services/LeadScoringService');
jest.mock('../services/ChatAssistantService');

const OpenAIProvider  = require('../providers/OpenAIProvider');
const ClaudeProvider  = require('../providers/ClaudeProvider');
const GeminiProvider  = require('../providers/GeminiProvider');
const LeadScoringService  = require('../services/LeadScoringService');
const ChatAssistantService = require('../services/ChatAssistantService');

const { errorHandler } = require('../middleware/errorHandler');
const { authMiddleware } = require('../middleware/auth');

function buildApp(routerOverrides) {
    const app = express();
    app.use(express.json());
    app.use('/api', authMiddleware);
    app.use('/api/v1', require('../routes/ai'));
    app.use(errorHandler);
    return app;
}

function authHeader() {
    return { Authorization: 'Bearer test-token' };
}

async function post(app, body) {
    return request(app)
        .post('/api/v1/process')
        .set(authHeader())
        .send(body);
}

beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.ONEOPS_API_SECRET;
});

describe('POST /api/v1/process — validation', () => {
    let app;
    beforeEach(() => {
        // Default mock setup: no providers available
        OpenAIProvider.mockImplementation(() => ({ isAvailable: () => false }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));
        app = buildApp();
    });

    it('returns 400 when action field is missing', async () => {
        const res = await post(app, { someData: 'value' });
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
        expect(res.body.error).toContain('action');
    });

    it('returns 400 for unknown action', async () => {
        const res = await post(app, { action: 'do_something_unknown' });
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
        expect(res.body.error).toContain('Unknown action');
    });
});

describe('POST /api/v1/process — score_lead', () => {
    let app;

    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({
            name: 'openai',
            isAvailable: () => true,
            complete: jest.fn().mockResolvedValue({ text: '{"score":80,"reason":"Good","emailDraft":"<p>Hi</p>"}', usage: {} })
        }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));

        LeadScoringService.mockImplementation(() => ({
            score: jest.fn().mockResolvedValue({
                score: 82,
                reason: 'Strong ICP match',
                emailDraft: '<p>Hello Alice</p>',
                provider: 'openai',
                confidence: 92
            })
        }));

        app = buildApp();
    });

    it('returns 200 with score_lead action', async () => {
        const res = await post(app, {
            action: 'score_lead',
            company: 'Acme Corp',
            industry: 'Technology',
            annualRevenue: 5000000
        });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });

    it('includes score, reason, emailDraft in data', async () => {
        const res = await post(app, { action: 'score_lead', company: 'Test' });
        expect(res.body.data).toHaveProperty('score');
        expect(res.body.data).toHaveProperty('reason');
        expect(res.body.data).toHaveProperty('emailDraft');
    });

    it('includes confidence and latencyMs in response', async () => {
        const res = await post(app, { action: 'score_lead', company: 'Test' });
        expect(res.body.confidence).toBeDefined();
        expect(typeof res.body.latencyMs).toBe('number');
    });
});

describe('POST /api/v1/process — chat', () => {
    let app;

    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({
            name: 'openai',
            isAvailable: () => true,
            complete: jest.fn().mockResolvedValue({ text: 'AI reply', usage: {} })
        }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));

        ChatAssistantService.mockImplementation(() => ({
            respond: jest.fn().mockResolvedValue({
                reply: 'You have 3 open tickets.',
                provider: 'openai',
                model: 'gpt-4o'
            })
        }));

        app = buildApp();
    });

    it('returns 200 with chat action', async () => {
        const res = await post(app, {
            action: 'chat',
            message: 'How many tickets are open?',
            userId: 'u1',
            userName: 'Alice'
        });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });

    it('includes reply in data', async () => {
        const res = await post(app, { action: 'chat', message: 'Hello' });
        expect(res.body.data).toHaveProperty('reply');
        expect(res.body.data.reply).toBe('You have 3 open tickets.');
    });
});

describe('POST /api/v1/process — generate_email', () => {
    let app;

    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({
            name: 'openai',
            isAvailable: () => true,
            complete: jest.fn().mockResolvedValue({ text: '<p>Email body</p>', providerName: 'openai', usage: {} })
        }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));
        LeadScoringService.mockImplementation(() => ({}));
        ChatAssistantService.mockImplementation(() => ({}));

        app = buildApp();
    });

    it('returns 200 and emailHtml for generate_email action', async () => {
        const res = await post(app, {
            action: 'generate_email',
            recipientName: 'Alice',
            company: 'Acme',
            industry: 'Technology',
            tone: 'professional',
            aiScore: 85
        });
        expect(res.status).toBe(200);
        expect(res.body.data).toHaveProperty('emailHtml');
    });
});

describe('POST /api/v1/process — summarize', () => {
    let app;

    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({
            name: 'openai',
            isAvailable: () => true,
            complete: jest.fn().mockResolvedValue({ text: 'Executive summary bullet points.', providerName: 'openai', usage: {} })
        }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));
        LeadScoringService.mockImplementation(() => ({}));
        ChatAssistantService.mockImplementation(() => ({}));

        app = buildApp();
    });

    it('returns 200 and summary for summarize action', async () => {
        const res = await post(app, {
            action: 'summarize',
            text: 'Long document text here...',
            summaryType: 'executive'
        });
        expect(res.status).toBe(200);
        expect(res.body.data).toHaveProperty('summary');
        expect(res.body.data.summary).toBe('Executive summary bullet points.');
    });
});

describe('POST /api/v1/process — no providers configured', () => {
    let app;

    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({ isAvailable: () => false }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));
        LeadScoringService.mockImplementation(() => ({
            score: jest.fn().mockRejectedValue(new Error('No AI providers configured or available.'))
        }));
        ChatAssistantService.mockImplementation(() => ({
            respond: jest.fn().mockRejectedValue(new Error('No AI providers configured or available.'))
        }));

        app = buildApp();
    });

    it('returns 500 when no providers are available for score_lead', async () => {
        const res = await post(app, { action: 'score_lead', company: 'Test' });
        expect(res.status).toBe(500);
    });
});

describe('POST /api/v1/process — auth requirement', () => {
    let app;
    beforeEach(() => {
        OpenAIProvider.mockImplementation(() => ({ isAvailable: () => false }));
        ClaudeProvider.mockImplementation(() => ({ isAvailable: () => false }));
        GeminiProvider.mockImplementation(() => ({ isAvailable: () => false }));
        LeadScoringService.mockImplementation(() => ({}));
        ChatAssistantService.mockImplementation(() => ({}));
        app = buildApp();
    });

    it('returns 401 without Authorization header', async () => {
        const res = await request(app).post('/api/v1/process').send({ action: 'chat', message: 'Hi' });
        expect(res.status).toBe(401);
        expect(res.body.success).toBe(false);
    });
});
