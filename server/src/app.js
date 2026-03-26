const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const env = require('./config/env');
const { initFirebase } = require('./config/firebase');
const authRoutes = require('./routes/auth');
const paymentRoutes = require('./routes/payments');
const aiRoutes = require('./routes/ai');
const userRoutes = require('./routes/users');
const notificationRoutes = require('./routes/notifications');
const { notFoundHandler, errorHandler } = require('./middleware/error');

initFirebase();

const app = express();

app.use(helmet());
app.use(express.json({ limit: '1mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

const corsOptions = {
  origin: (origin, callback) => {
    if (!origin || env.allowedOrigins.length === 0 || env.allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error('CORS blocked for this origin'));
  },
};
app.use(cors(corsOptions));

app.use(
  '/api',
  rateLimit({
    windowMs: 60 * 1000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'safepay-server', mode: env.nodeEnv });
});

app.use('/api/auth', authRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/users', userRoutes);
app.use('/api/notifications', notificationRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
