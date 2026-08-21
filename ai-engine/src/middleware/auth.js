const config = require('../config');
const logger = require('../utils/logger');

function authMiddleware(req, res, next) {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        logger.warn({ path: req.path, ip: req.ip }, 'Unauthorized: missing Bearer token');
        return res.status(401).json({ success: false, error: 'Unauthorized: Bearer token required.' });
    }

    const token = authHeader.slice(7);

    // In production, validate against the configured API secret
    if (config.apiSecret && token !== config.apiSecret) {
        logger.warn({ path: req.path, ip: req.ip }, 'Unauthorized: invalid API token');
        return res.status(401).json({ success: false, error: 'Unauthorized: invalid API token.' });
    }

    // Attach org context from headers
    req.orgId     = req.headers['x-oneops-org'] || 'unknown';
    req.requestId = req.headers['x-request-id'] || 'req-' + Date.now();

    next();
}

module.exports = { authMiddleware };
