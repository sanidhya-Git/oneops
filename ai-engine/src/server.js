require('dotenv').config();
const express    = require('express');
const helmet     = require('helmet');
const compression = require('compression');
const { createRateLimiter } = require('./middleware/rateLimit');
const { authMiddleware }    = require('./middleware/auth');
const { errorHandler }      = require('./middleware/errorHandler');
const aiRoutes   = require('./routes/ai');
const healthRoutes = require('./routes/health');
const logger     = require('./utils/logger');

const app = express();
const PORT = process.env.PORT || 3001;

// ── Security ───────────────────────────────────────────────────
app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false
}));
app.use(compression());
app.use(express.json({ limit: '2mb' }));

// ── Health endpoint (no auth) ──────────────────────────────────
app.use('/health', healthRoutes);

// ── Rate limiting ──────────────────────────────────────────────
app.use('/api', createRateLimiter());

// ── Auth ───────────────────────────────────────────────────────
app.use('/api', authMiddleware);

// ── Routes ────────────────────────────────────────────────────
app.use(`/api/${process.env.API_VERSION || 'v1'}`, aiRoutes);

// ── 404 ───────────────────────────────────────────────────────
app.use((req, res) => {
    res.status(404).json({ success: false, error: 'Endpoint not found', path: req.path });
});

// ── Error handler ──────────────────────────────────────────────
app.use(errorHandler);

// ── Start ─────────────────────────────────────────────────────
app.listen(PORT, () => {
    logger.info(`OneOps AI Engine running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
    logger.info(`Primary AI provider: ${(process.env.AI_PROVIDER_ORDER || 'openai').split(',')[0]}`);
});

module.exports = app;
