const logger = require('../utils/logger');

function errorHandler(err, req, res, next) {
    const status = err.status || err.statusCode || 500;

    logger.error({
        path:      req.path,
        method:    req.method,
        status,
        message:   err.message,
        stack:     process.env.NODE_ENV !== 'production' ? err.stack : undefined
    }, 'Unhandled error');

    res.status(status).json({
        success: false,
        error:   status >= 500 ? 'Internal server error.' : err.message,
        code:    err.code || 'INTERNAL_ERROR',
        requestId: req.requestId || null
    });
}

module.exports = { errorHandler };
