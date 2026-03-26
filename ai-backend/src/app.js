const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const env = require('./config/env');
const { requireMobileApiKey } = require('./middleware/apiKey');
const aiRoutes = require('./routes/ai');
const paymentRoutes = require('./routes/payments');
const { notFoundHandler, errorHandler } = require('./middleware/error');

const app = express();

app.set('env', env.nodeEnv);
app.use(helmet());
app.use(express.json({ limit: '1mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin || env.allowedOrigins.length === 0 || env.allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(new Error('CORS blocked for this origin'));
    },
  })
);

app.use(
  '/api',
  rateLimit({
    windowMs: env.rateLimitWindowMs,
    max: env.rateLimitMax,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'safepay-ai-backend', mode: env.nodeEnv });
});

app.get('/', (req, res) => {
  res.json({
    ok: true,
    service: 'safepay-ai-backend',
    message: 'Backend is running. Use /health or /api/* endpoints.',
  });
});

app.get('/api', (req, res) => {
  res.json({
    ok: true,
    message: 'API online. Send POST requests to documented endpoints with x-api-key header.',
    endpoints: [
      '/api/ai/analyze-transaction',
      '/api/ai/security-check',
      '/api/ai/chat-assistant',
      '/api/payments/verify',
      '/api/payments/transactions/request',
      '/api/payments/transactions/:transactionId/approve',
      '/api/payments/transactions/:transactionId/reject',
      '/api/payments/transactions/:transactionId/emergency-cancel',
      '/api/payments/transactions/history/:userId',
      '/api/payments/transactions/pending/:userId',
      '/api/payments/transactions/logs/:userId',
      '/api/payments/dashboard/:userId',
      '/api/payments/transactions/log',
    ],
    missingConfig: !env.mobileApiKey,
  });
});

app.use('/api/ai', requireMobileApiKey, aiRoutes);
app.use('/api/payments', requireMobileApiKey, paymentRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
