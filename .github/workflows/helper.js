/**
 * AI PC DevKit - Installation Helper
 */

/**
 * Logs installation messages
 * @param {string} message - Message to log
 */
function logMessage(message) {
    console.log(`[AI-PC-DevKit] ${message}`);
}

/**
 * Validates installation directory path
 * @param {string} path - Directory path
 * @returns {boolean} - True if valid
 */
function validatePath(path) {
    if (!path || typeof path !== 'string') {
        return false;
    }
    return path.length > 0;
}

module.exports = { logMessage, validatePath };
