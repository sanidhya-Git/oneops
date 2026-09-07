const request = require('supertest');
const express = require('express');
const healthRoutes = require('../routes/health');

function buildApp() {
    const app = express();
    app.use('/health', healthRoutes);
    return app;
}

afterEach(() => {
    delete process.env.OPENAI_API_KEY;
    delete process.env.ANTHROPIC_API_KEY;
    delete process.env.GEMINI_API_KEY;
});

describe('GET /health', () => {
    it('returns 200 with healthy status', async () => {
        const res = await request(buildApp()).get('/health');
        expect(res.status).toBe(200);
        expect(res.body.status).toBe('healthy');
        expect(res.body.service).toBe('oneops-ai-engine');
    });

    it('includes timestamp in ISO format', async () => {
        const res = await request(buildApp()).get('/health');
        expect(res.body.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('includes uptime as a number', async () => {
        const res = await request(buildApp()).get('/health');
        expect(typeof res.body.uptime).toBe('number');
        expect(res.body.uptime).toBeGreaterThanOrEqual(0);
    });

    it('includes env field', async () => {
        const res = await request(buildApp()).get('/health');
        expect(res.body.env).toBeDefined();
    });
});

describe('GET /health/ready', () => {
    it('returns 503 when no AI provider key is configured', async () => {
        const res = await request(buildApp()).get('/health/ready');
        expect(res.status).toBe(503);
        expect(res.body.ready).toBe(false);
        expect(res.body.reason).toContain('No AI provider');
    });

    it('returns 200 ready when OPENAI_API_KEY is set', async () => {
        process.env.OPENAI_API_KEY = 'sk-test-key';
        const res = await request(buildApp()).get('/health/ready');
        expect(res.status).toBe(200);
        expect(res.body.ready).toBe(true);
    });

    it('returns 200 ready when ANTHROPIC_API_KEY is set', async () => {
        process.env.ANTHROPIC_API_KEY = 'sk-ant-test-key';
        const res = await request(buildApp()).get('/health/ready');
        expect(res.status).toBe(200);
        expect(res.body.ready).toBe(true);
    });

    it('returns 200 ready when GEMINI_API_KEY is set', async () => {
        process.env.GEMINI_API_KEY = 'gemini-test-key';
        const res = await request(buildApp()).get('/health/ready');
        expect(res.status).toBe(200);
        expect(res.body.ready).toBe(true);
    });
});
