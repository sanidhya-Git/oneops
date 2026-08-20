module.exports = {
    port:         parseInt(process.env.PORT, 10) || 3001,
    nodeEnv:      process.env.NODE_ENV || 'development',
    apiSecret:    process.env.ONEOPS_API_SECRET || '',
    logLevel:     process.env.LOG_LEVEL || 'info',

    providers: {
        order:    (process.env.AI_PROVIDER_ORDER || 'openai,claude,gemini').split(',').map(p => p.trim()),
        openai: {
            apiKey:        process.env.OPENAI_API_KEY,
            model:         process.env.OPENAI_MODEL         || 'gpt-4o',
            fallbackModel: process.env.OPENAI_FALLBACK_MODEL || 'gpt-4o-mini',
            maxTokens:     4096,
            temperature:   0.2
        },
        claude: {
            apiKey:   process.env.ANTHROPIC_API_KEY,
            model:    process.env.CLAUDE_MODEL || 'claude-sonnet-4-6',
            maxTokens: 4096,
            temperature: 0.2
        },
        gemini: {
            apiKey: process.env.GEMINI_API_KEY,
            model:  process.env.GEMINI_MODEL || 'gemini-1.5-flash'
        }
    },

    salesforce: {
        loginUrl:      process.env.SALESFORCE_LOGIN_URL || 'https://login.salesforce.com',
        clientId:      process.env.SALESFORCE_CLIENT_ID,
        clientSecret:  process.env.SALESFORCE_CLIENT_SECRET,
        username:      process.env.SALESFORCE_USERNAME,
        password:      process.env.SALESFORCE_PASSWORD,
        securityToken: process.env.SALESFORCE_SECURITY_TOKEN
    },

    redis: {
        url:     process.env.REDIS_URL || '',
        enabled: !!process.env.REDIS_URL,
        ttl:     300  // 5 min cache
    },

    rateLimit: {
        windowMs:    parseInt(process.env.RATE_LIMIT_WINDOW_MS,     10) || 60000,
        maxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS,   10) || 120
    }
};
