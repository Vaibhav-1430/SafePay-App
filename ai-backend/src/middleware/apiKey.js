const env = require('../config/env');

function requireMobileApiKey(req, res, next) {
  if (!env.mobileApiKey) {
    return res.status(500).json({
      ok: false,
      error: {
        code: 'MISSING_BACKEND_CONFIG',
        message: 'Server API key is not configured.',
      },
    });
  }

  const incoming = req.header('x-api-key');
  if (!incoming || incoming !== env.mobileApiKey) {
    return res.status(401).json({
      ok: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Invalid API key.',
      },
    });
  }

  return next();
}

module.exports = { requireMobileApiKey };
