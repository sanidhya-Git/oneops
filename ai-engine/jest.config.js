module.exports = {
    testEnvironment: 'node',
    testMatch: ['**/src/__tests__/**/*.test.js'],
    collectCoverageFrom: ['src/**/*.js', '!src/**/__tests__/**'],
    coverageThreshold: {
        global: {
            branches: 60,
            functions: 65,
            lines: 65,
            statements: 65
        }
    }
};
