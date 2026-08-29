const express = require('express');
const router  = express.Router();

router.get('/', (req, res) => {
    res.json({
        status:    'healthy',
        service:   'oneops-ai-engine',
        version:   process.env.npm_package_version || '1.0.0',
        timestamp: new Date().toISOString(),
        uptime:    Math.floor(process.uptime()),
        env:       process.env.NODE_ENV || 'development'
    });
});

router.get('/ready', (req, res) => {
    const hasAnyProvider = !!(
        process.env.OPENAI_API_KEY ||
        process.env.ANTHROPIC_API_KEY ||
        process.env.GEMINI_API_KEY
    );
    if (!hasAnyProvider) {
        return res.status(503).json({ ready: false, reason: 'No AI provider configured.' });
    }
    res.json({ ready: true });
});

module.exports = router;
