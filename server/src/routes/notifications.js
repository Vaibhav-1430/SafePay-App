// =============================================================================
// NOTIFICATION ROUTES
// server/src/routes/notifications.js
//
// REST API endpoint to send FCM push notifications from the backend.
// This provides an alternative to Cloud Functions for sending FCM messages,
// useful when the Express.js backend is already processing payment transactions
// and needs to trigger notifications inline.
//
// Endpoints:
//   POST /api/notifications/send-payment-request — Send FCM to receiver
//   POST /api/notifications/send-status-update   — Notify sender of status change
// =============================================================================

const express = require('express');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { z } = require('zod');

const router = express.Router();

// Lazy-init: Firebase must be initialized (in app.js) before these are called.
// We cannot call getFirestore() / getMessaging() at module top-level because
// this file is require()'d before initFirebase() runs.
let _db, _messaging;
function db()        { return _db        || (_db        = getFirestore()); }
function messaging() { return _messaging || (_messaging = getMessaging()); }

// ─────────────────────────────────────────────────────────────────────────────
// Middleware: Verify Firebase ID token
// ─────────────────────────────────────────────────────────────────────────────
async function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid authorization header' });
  }

  try {
    const token = authHeader.split('Bearer ')[1];
    req.user = await getAuth().verifyIdToken(token);
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /send-payment-request
// Sends an FCM DATA message to the receiver for a new payment request.
// ─────────────────────────────────────────────────────────────────────────────
const sendPaymentRequestSchema = z.object({
  transactionId: z.string().min(1),
  receiverId: z.string().min(1),
  senderId: z.string().min(1),
  senderName: z.string().min(1),
  amount: z.number().positive(),
  riskLevel: z.string().optional().default('Low Risk'),
  riskEmoji: z.string().optional().default('🟢'),
});

router.post('/send-payment-request', verifyToken, async (req, res) => {
  try {
    const parsed = sendPaymentRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({
        error: 'Invalid request body',
        details: parsed.error.flatten(),
      });
    }

    const { transactionId, receiverId, senderId, senderName, amount, riskLevel, riskEmoji } = parsed.data;

    // 1. Fetch receiver's user document
    const receiverDoc = await db().collection('users').doc(receiverId).get();
    if (!receiverDoc.exists) {
      return res.status(404).json({ error: 'Receiver not found' });
    }

    const receiverData = receiverDoc.data();
    const notificationsEnabled = receiverData.notificationsEnabled !== false;
    const fcmToken = receiverData.fcmToken;

    // 2. Check notification preference
    if (!notificationsEnabled) {
      return res.json({
        sent: false,
        reason: 'Receiver has notifications disabled',
      });
    }

    // 3. Check FCM token
    if (!fcmToken) {
      return res.json({
        sent: false,
        reason: 'No FCM token registered for receiver',
      });
    }

    // 4. Send FCM DATA message
    const message = {
      token: fcmToken,
      data: {
        type: 'payment_request',
        transactionId,
        senderName,
        senderId,
        receiverId,
        amount: String(amount),
        riskLevel,
        riskEmoji,
      },
      android: {
        priority: 'high',
        ttl: 300000,
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 300),
        },
        payload: {
          aps: {
            'content-available': 1,
            sound: 'default',
            category: 'PAYMENT_REQUEST',
          },
        },
      },
    };

    await messaging().send(message);

    return res.json({ sent: true, transactionId });
  } catch (error) {
    // Handle token-related errors
    if (error.code === 'messaging/registration-token-not-registered' ||
        error.code === 'messaging/invalid-registration-token') {
      // Clean up stale token
      const { receiverId } = req.body;
      if (receiverId) {
        await db().collection('users').doc(receiverId).update({
          fcmToken: FieldValue.delete(),
        });
      }
      return res.json({ sent: false, reason: 'FCM token expired or invalid' });
    }

    console.error('[notifications/send-payment-request] Error:', error.message);
    return res.status(500).json({ error: 'Failed to send notification' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /send-status-update
// Sends a notification push when payment status changes (approved/rejected/completed).
// ─────────────────────────────────────────────────────────────────────────────
const statusUpdateSchema = z.object({
  transactionId: z.string().min(1),
  userId: z.string().min(1),
  title: z.string().min(1),
  body: z.string().min(1),
  type: z.enum(['payment_approved', 'payment_rejected', 'payment_completed']),
});

router.post('/send-status-update', verifyToken, async (req, res) => {
  try {
    const parsed = statusUpdateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({
        error: 'Invalid request body',
        details: parsed.error.flatten(),
      });
    }

    const { transactionId, userId, title, body, type } = parsed.data;

    // 1. Fetch user
    const userDoc = await db().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;
    const notificationsEnabled = userData.notificationsEnabled !== false;

    if (!notificationsEnabled || !fcmToken) {
      return res.json({ sent: false, reason: 'Notifications disabled or no token' });
    }

    // 2. Send notification message
    const message = {
      token: fcmToken,
      notification: { title, body },
      data: { type, transactionId },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'safepay_general',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    };

    await messaging().send(message);

    return res.json({ sent: true, transactionId });
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      const { userId } = req.body;
      if (userId) {
        await db().collection('users').doc(userId).update({
          fcmToken: FieldValue.delete(),
        });
      }
      return res.json({ sent: false, reason: 'FCM token expired' });
    }

    console.error('[notifications/send-status-update] Error:', error.message);
    return res.status(500).json({ error: 'Failed to send notification' });
  }
});

module.exports = router;
