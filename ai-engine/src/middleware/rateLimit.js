const rateLimit = require('express-rate-limit');
const config    = require('../config');
const logger    = require('../utils/logger');

function createRateLimiter() {
    return rateLimit({
        windowMs:         config.rateLimit.windowMs,
        max:              config.rateLimit.maxRequests,
        standardHeaders:  true,
        legacyHeaders:    false,
        keyGenerator:     (req) => req.orgId || req.ip,
        handler: (req, res) => {
            logger.warn({ orgId: req.orgId, path: req.path }, 'Rate limit exceeded');
            res.status(429).json({
                success: false,
                error:   'Too many requests. Please wait before retrying.',
                code:    'RATE_LIMIT_EXCEEDED',
                retryAfter: Math.ceil(config.rateLimit.windowMs / 1000)
            });
        }
    });
}

module.exports = { createRateLimiter };
