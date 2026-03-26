const express = require('express');
const crypto = require('crypto');
const { z } = require('zod');

const env = require('../config/env');
const { validate } = require('../middleware/validation');
const { authenticateJwt, signAppToken } = require('../middleware/auth');
const { upsertUser, getUser, getUserByPhone } = require('../services/store');

const router = express.Router();
const otpStore = new Map();

function normalizePhone(phone) {
  let digits = String(phone || '').replace(/\D/g, '');
  if (digits.startsWith('91') && digits.length === 12) {
    digits = digits.slice(2);
  }
  if (digits.length > 10) {
    digits = digits.slice(-10);
  }
  if (digits.length < 10) {
    return '';
  }
  return digits;
}

function toE164(phoneNormalized) {
  return `+91${phoneNormalized}`;
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashAppPin(uid, pin) {
  return crypto.createHash('sha256').update(`${uid}::${pin}`).digest('hex');
}

function publicUser(user) {
  return {
    uid: user.uid,
    email: user.email,
    name: user.name,
    phone: user.phone,
    upiId: user.upiId,
    authProvider: user.authProvider,
  };
}

const requestOtpSchema = z.object({
  body: z.object({
    phone: z.string().min(8),
    purpose: z.enum(['signup', 'login']).default('login'),
  }),
  query: z.object({}).optional(),
  params: z.object({}).optional(),
});

router.post('/request-otp', validate(requestOtpSchema), async (req, res) => {
  const { phone, purpose } = req.validated.body;
  const normalized = normalizePhone(phone);

  if (!normalized) {
    return res.status(400).json({ error: 'Invalid phone number' });
  }

  const existingUser = await getUserByPhone(normalized);
  if (purpose === 'login' && !existingUser) {
    return res.status(404).json({ error: 'User not found for this phone number' });
  }
  if (purpose === 'signup' && existingUser) {
    return res.status(409).json({ error: 'Phone number already registered' });
  }

  const otp = generateOtp();
  const expiresAt = Date.now() + 5 * 60 * 1000;
  otpStore.set(normalized, { otp, purpose, expiresAt, attempts: 0 });

  return res.json({
    success: true,
    phone: toE164(normalized),
    expiresInSeconds: 300,
    otp: env.nodeEnv === 'production' ? undefined : otp,
  });
});

const verifyOtpSchema = z.object({
  body: z.object({
    phone: z.string().min(8),
    otp: z.string().regex(/^\d{6}$/),
    name: z.string().min(2).optional(),
    email: z.string().email().optional(),
    upiId: z.string().min(3).optional(),
  }),
  query: z.object({}).optional(),
  params: z.object({}).optional(),
});

router.post('/verify-otp', validate(verifyOtpSchema), async (req, res) => {
  const { phone, otp, name, email, upiId } = req.validated.body;
  const normalized = normalizePhone(phone);
  if (!normalized) {
    return res.status(400).json({ error: 'Invalid phone number' });
  }

  const session = otpStore.get(normalized);
  if (!session) {
    return res.status(400).json({ error: 'OTP not requested or expired' });
  }
  if (Date.now() > session.expiresAt) {
    otpStore.delete(normalized);
    return res.status(400).json({ error: 'OTP expired' });
  }
  if (session.attempts >= 5) {
    otpStore.delete(normalized);
    return res.status(429).json({ error: 'Too many invalid OTP attempts' });
  }
  if (session.otp !== otp) {
    session.attempts += 1;
    otpStore.set(normalized, session);
    return res.status(401).json({ error: 'Invalid OTP' });
  }

  let user = await getUserByPhone(normalized);
  const isNewUser = !user;

  if (!user) {
    if (!name || !email) {
      return res.status(400).json({ error: 'Name and email are required for signup' });
    }

    const uid = `user_${normalized}`;
    user = await upsertUser({
      uid,
      email,
      name,
      phone: toE164(normalized),
      phoneNormalized: normalized,
      upiId: upiId || `${normalized}@safepay`,
      authProvider: 'phone-otp',
    });
  }

  otpStore.delete(normalized);
  const token = signAppToken({
    uid: user.uid,
    email: user.email,
    phone: user.phone,
    provider: 'phone-otp',
  });

  return res.json({
    success: true,
    token,
    isNewUser,
    user: publicUser(user),
  });
});

const setAppPinSchema = z.object({
  body: z.object({
    pin: z.string().regex(/^\d{4,6}$/),
  }),
  query: z.object({}).optional(),
  params: z.object({}).optional(),
});

router.post('/app-lock-pin', authenticateJwt, validate(setAppPinSchema), async (req, res) => {
  const { pin } = req.validated.body;
  const existing = await getUser(req.auth.uid);
  if (!existing) {
    return res.status(404).json({ error: 'User not found' });
  }

  const appLockPinHash = hashAppPin(existing.uid, pin);
  await upsertUser({ ...existing, appLockPinHash, uid: existing.uid });
  return res.json({ success: true });
});

const verifyAppPinSchema = z.object({
  body: z.object({
    pin: z.string().regex(/^\d{4,6}$/),
  }),
  query: z.object({}).optional(),
  params: z.object({}).optional(),
});

router.post(
  '/verify-app-lock-pin',
  authenticateJwt,
  validate(verifyAppPinSchema),
  async (req, res) => {
    const { pin } = req.validated.body;
    const user = await getUser(req.auth.uid);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    if (!user.appLockPinHash) {
      return res.status(400).json({ error: 'App PIN not set' });
    }

    const isValid = user.appLockPinHash === hashAppPin(user.uid, pin);
    return res.json({ success: isValid });
  }
);

router.post('/logout', authenticateJwt, async (_req, res) => {
  return res.json({ success: true });
});

router.get('/me', authenticateJwt, async (req, res) => {
  const user = await getUser(req.auth.uid);
  if (!user) return res.status(404).json({ error: 'User not found' });

  res.json(publicUser(user));
});

module.exports = router;
