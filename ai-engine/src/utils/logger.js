const winston = require('winston');

const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
        winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
        winston.format.errors({ stack: true }),
        process.env.NODE_ENV === 'development'
            ? winston.format.combine(
                winston.format.colorize(),
                winston.format.printf(({ timestamp, level, message, ...rest }) => {
                    const extra = Object.keys(rest).length ? ' ' + JSON.stringify(rest) : '';
                    return `${timestamp} [${level}] ${message}${extra}`;
                })
              )
            : winston.format.json()
    ),
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'logs/error.log', level: 'error', maxFiles: 5, maxsize: 10485760 }),
        new winston.transports.File({ filename: 'logs/combined.log', maxFiles: 10, maxsize: 10485760 })
    ]
});

module.exports = logger;
