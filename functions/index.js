const functions = require('firebase-functions/v1');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { createHash } = require('crypto');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

const REGION = 'asia-south1';
const PAYMENT_RECEIVED_TITLE = 'Payment Received 💰';
const OTP_RATE_LIMIT_COLLECTION = 'otp_rate_limits';
const OTP_FREE_ATTEMPTS = 3;
const OTP_HARD_LIMIT = 10;
const OTP_FIXED_COOLDOWN_SECONDS = 30;
const OTP_HARD_BLOCK_MS = 24 * 60 * 60 * 1000;
const DELETE_BATCH_LIMIT = 400;

function normalizePhoneDigits(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (!digits) return null;
  let normalized = digits;
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.slice(2);
  }
  if (normalized.length > 10) {
    normalized = normalized.slice(-10);
  }
  if (!/^\d{10}$/.test(normalized)) return null;
  return normalized;
}

function normalizePhoneE164(value) {
  const raw = String(value || '').trim();
  if (!raw.startsWith('+')) return null;
  if (!/^\+[1-9][0-9]{7,14}$/.test(raw)) return null;
  return raw;
}

function phoneHash(value) {
  return createHash('sha256').update(value).digest('hex');
}

function toMillis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (typeof ts === 'number') return ts;
  return 0;
}

function computeCooldownSeconds(attempts, useExponentialBackoff) {
  if (!useExponentialBackoff) {
    return OTP_FIXED_COOLDOWN_SECONDS;
  }

  // 4th request onward: 30s, 60s, 120s ... capped at 10 minutes.
  const exponent = Math.max(0, attempts - OTP_FREE_ATTEMPTS);
  const seconds = OTP_FIXED_COOLDOWN_SECONDS * Math.pow(2, exponent);
  return Math.min(600, Math.floor(seconds));
}

exports.otpRequestGuard = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const phone = normalizePhoneE164(data?.phone);
    if (!phone) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid E.164 phone number.');
    }

    // Require App Check for anti-abuse. Remove this guard only for local emulator tests.
    if (!context.app) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'App Check token is required for OTP requests.',
      );
    }

    const nowMs = Date.now();
    const ip = context.rawRequest?.ip || null;
    const deviceId = String(data?.deviceId || '').trim() || null;
    const mode = String(data?.mode || 'otp_request');
    const useExponentialBackoff = Boolean(data?.useExponentialBackoff);

    const docId = phoneHash(phone);
    const docRef = db.collection(OTP_RATE_LIMIT_COLLECTION).doc(docId);

    const outcome = await db.runTransaction(async (txn) => {
      const snap = await txn.get(docRef);
      const current = snap.exists ? (snap.data() || {}) : {};

      const attempts = Number(current.attempts || 0);
      const blockedUntilMs = toMillis(current.blockedUntil);
      const lastAttemptTimeMs = toMillis(current.lastAttemptTime);
      const isBlocked = blockedUntilMs > nowMs;

      if (isBlocked) {
        return {
          allowed: false,
          errorCode: 'BLOCKED_24_HOURS',
          waitSeconds: Math.max(1, Math.ceil((blockedUntilMs - nowMs) / 1000)),
          blockedUntilMs,
        };
      }

      const nextAttempts = attempts + 1;
      const cooldownSeconds = computeCooldownSeconds(attempts, useExponentialBackoff);
      const cooldownMs = cooldownSeconds * 1000;
      const withinCooldown =
        attempts >= OTP_FREE_ATTEMPTS &&
        lastAttemptTimeMs > 0 &&
        (nowMs - lastAttemptTimeMs) < cooldownMs;

      if (nextAttempts >= OTP_HARD_LIMIT) {
        const nextBlockedUntilMs = nowMs + OTP_HARD_BLOCK_MS;
        txn.set(docRef, {
          attempts: nextAttempts,
          lastAttemptTime: Timestamp.fromMillis(nowMs),
          blockedUntil: Timestamp.fromMillis(nextBlockedUntilMs),
          updatedAt: FieldValue.serverTimestamp(),
          metadata: {
            lastIp: ip,
            lastDeviceId: deviceId,
            mode,
            appId: context.app?.appId || null,
          },
        }, { merge: true });

        return {
          allowed: false,
          errorCode: 'BLOCKED_24_HOURS',
          waitSeconds: Math.ceil(OTP_HARD_BLOCK_MS / 1000),
          blockedUntilMs: nextBlockedUntilMs,
        };
      }

      if (withinCooldown) {
        const remainingMs = cooldownMs - (nowMs - lastAttemptTimeMs);
        txn.set(docRef, {
          attempts: nextAttempts,
          lastAttemptTime: Timestamp.fromMillis(nowMs),
          updatedAt: FieldValue.serverTimestamp(),
          metadata: {
            lastIp: ip,
            lastDeviceId: deviceId,
            mode,
            appId: context.app?.appId || null,
          },
        }, { merge: true });

        return {
          allowed: false,
          errorCode: 'WAIT_30_SEC',
          waitSeconds: Math.max(1, Math.ceil(remainingMs / 1000)),
          blockedUntilMs: 0,
        };
      }

      txn.set(docRef, {
        attempts: nextAttempts,
        lastAttemptTime: Timestamp.fromMillis(nowMs),
        blockedUntil: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
        metadata: {
          lastIp: ip,
          lastDeviceId: deviceId,
          mode,
          appId: context.app?.appId || null,
        },
      }, { merge: true });

      return {
        allowed: true,
        errorCode: null,
        waitSeconds: 0,
        blockedUntilMs: 0,
      };
    });

    return {
      allowed: outcome.allowed,
      errorCode: outcome.errorCode,
      waitSeconds: outcome.waitSeconds,
      blockedUntilMs: outcome.blockedUntilMs,
      attemptsCap: OTP_HARD_LIMIT,
      cooldownSeconds: OTP_FIXED_COOLDOWN_SECONDS,
    };
  });

exports.otpResetLimiter = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const phone = normalizePhoneE164(data?.phone);
    if (!phone) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid E.164 phone number.');
    }

    if (!context.app) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'App Check token is required for OTP reset.',
      );
    }

    const docId = phoneHash(phone);
    await db.collection(OTP_RATE_LIMIT_COLLECTION).doc(docId).set({
      attempts: 0,
      lastAttemptTime: FieldValue.delete(),
      blockedUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
      resetMeta: {
        reason: 'otp_verified',
        uid: context.auth?.uid || null,
        appId: context.app?.appId || null,
      },
    }, { merge: true });

    return { ok: true };
  });

exports.checkPhoneAvailability = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const normalized = normalizePhoneDigits(data?.phone);
    if (!normalized) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid phone number.',
      );
    }

    if (!context.app) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'App Check token is required for signup checks.',
      );
    }

    const indexRef = db.collection('user_phone_index').doc(normalized);
    const [indexSnap, usersByPhone, usersByNormalized] = await Promise.all([
      indexRef.get(),
      db.collection('users').where('phone', '==', normalized).limit(1).get(),
      db.collection('users').where('phoneNormalized', '==', normalized).limit(1).get(),
    ]);

    const exists = indexSnap.exists || !usersByPhone.empty || !usersByNormalized.empty;
    if (exists) {
      return {
        available: false,
        message: 'Phone number already exists. Please login instead.',
      };
    }

    return {
      available: true,
    };
  });

exports.claimPhoneNumberOwnership = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'You must be signed in.');
    }
    if (!context.app) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'App Check token is required for signup.',
      );
    }

    const uid = context.auth.uid;
    const normalized = normalizePhoneDigits(data?.phone);
    if (!normalized) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid phone number.');
    }

    const indexRef = db.collection('user_phone_index').doc(normalized);
    await db.runTransaction(async (txn) => {
      const indexSnap = await txn.get(indexRef);
      if (indexSnap.exists) {
        const ownerUid = String(indexSnap.get('uid') || '').trim();
        if (ownerUid && ownerUid !== uid) {
          throw new functions.https.HttpsError(
            'already-exists',
            'Phone number already exists. Please login instead.',
          );
        }
      }

      const now = Timestamp.now();
      txn.set(indexRef, {
        uid,
        phoneNumber: normalized,
        updatedAt: now,
        createdAt: indexSnap.exists
          ? (indexSnap.get('createdAt') || now)
          : now,
      }, { merge: true });
    });

    return {
      ok: true,
      phoneNumber: normalized,
    };
  });

function requireSecuredCaller(context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be signed in.');
  }
  if (!context.app) {
    // Keep payment actions available for authenticated users when App Check
    // token generation/verification is temporarily unavailable on device.
    logger.warn('Payment action called without App Check token; allowing authenticated fallback.', {
      uid: context.auth.uid,
    });
  }
  return context.auth.uid;
}

function requireAuthenticatedCaller(context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be signed in.');
  }
  return context.auth.uid;
}

function getTxMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value === 'number') return value;
  return 0;
}

async function deleteDocRefsInBatches(docRefs) {
  const refs = [...docRefs];
  while (refs.length > 0) {
    const chunk = refs.splice(0, DELETE_BATCH_LIMIT);
    const batch = db.batch();
    for (const ref of chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

exports.deleteUserAccountCascade = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    // Account deletion must remain available for authenticated users even
    // if App Check token verification is temporarily unavailable.
    const uid = requireAuthenticatedCaller(context);
    const requestedUid = String(data?.uid || '').trim();
    if (requestedUid.length > 0 && requestedUid !== uid) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'You can only delete your own account.',
      );
    }

    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    const normalizedPhone = normalizePhoneDigits(
      userSnap.exists ? (userSnap.data()?.phoneNormalized || userSnap.data()?.phone || '') : '',
    );

    // Soft-delete marker first so backend ops can detect deletion intent.
    await userRef.set({
      deletion: {
        status: 'pending',
        requestedAt: FieldValue.serverTimestamp(),
        requestedByUid: uid,
      },
    }, { merge: true });

    const [
      txSenderSnap,
      txReceiverSnap,
      reqSenderSnap,
      reqReceiverSnap,
      logSenderSnap,
      logReceiverSnap,
      notifSnap,
      trustedContactsSnap,
    ] = await Promise.all([
      db.collection('transactions').where('senderId', '==', uid).get(),
      db.collection('transactions').where('receiverId', '==', uid).get(),
      db.collection('payment_requests').where('senderId', '==', uid).get(),
      db.collection('payment_requests').where('receiverId', '==', uid).get(),
      db.collection('transaction_logs').where('senderId', '==', uid).get(),
      db.collection('transaction_logs').where('receiverId', '==', uid).get(),
      db.collection('notifications').where('userId', '==', uid).get(),
      db.collection('trusted_contacts').where('ownerUserId', '==', uid).get(),
    ]);

    const refsByPath = new Map();
    const addDocs = (docs) => {
      for (const doc of docs) {
        refsByPath.set(doc.ref.path, doc.ref);
      }
    };

    addDocs(txSenderSnap.docs);
    addDocs(txReceiverSnap.docs);
    addDocs(reqSenderSnap.docs);
    addDocs(reqReceiverSnap.docs);
    addDocs(logSenderSnap.docs);
    addDocs(logReceiverSnap.docs);
    addDocs(notifSnap.docs);
    addDocs(trustedContactsSnap.docs);

    // Known singleton docs by user ID.
    refsByPath.set(db.collection('wallets').doc(uid).path, db.collection('wallets').doc(uid));
    refsByPath.set(db.collection('merchant_settings').doc(uid).path, db.collection('merchant_settings').doc(uid));
    refsByPath.set(db.collection('users').doc(uid).path, db.collection('users').doc(uid));

    await deleteDocRefsInBatches([...refsByPath.values()]);

    if (normalizedPhone) {
      const phoneIndexRef = db.collection('user_phone_index').doc(normalizedPhone);
      const phoneIndexSnap = await phoneIndexRef.get();
      if (phoneIndexSnap.exists && String(phoneIndexSnap.get('uid') || '').trim() === uid) {
        await phoneIndexRef.delete();
      }
    }

    return {
      ok: true,
      deletedDocuments: refsByPath.size,
      uid,
    };
  });

async function markTimedOutAndRefund({ transactionId, now }) {
  const txRef = db.collection('transactions').doc(transactionId);
  const reqRef = db.collection('payment_requests').doc(transactionId);

  const outcome = await db.runTransaction(async (txn) => {
    const txSnap = await txn.get(txRef);
    if (!txSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Transaction not found.');
    }

    const tx = txSnap.data() || {};
    if (tx.status !== 'pending') {
      return { ok: true, status: tx.status, alreadyFinalized: true };
    }

    const senderId = String(tx.senderId || '').trim();
    const amount = Number(tx.amount || 0);
    if (!senderId || !Number.isFinite(amount) || amount <= 0) {
      throw new functions.https.HttpsError('failed-precondition', 'Invalid transaction payload.');
    }

    const senderWalletRef = db.collection('wallets').doc(senderId);
    const senderWalletSnap = await txn.get(senderWalletRef);
    if (!senderWalletSnap.exists) {
      throw new functions.https.HttpsError('failed-precondition', 'Sender wallet not found.');
    }

    txn.update(senderWalletRef, {
      balance: FieldValue.increment(amount),
      updatedAt: now,
    });

    txn.update(txRef, {
      status: 'timedOut',
      completedAt: now,
      isEscrow: false,
      timeoutSource: 'server',
      updatedAt: now,
    });

    txn.set(reqRef, {
      status: 'timedOut',
      completedAt: now,
      updatedAt: now,
    }, { merge: true });

    const logRef = db.collection('transaction_logs').doc();
    txn.set(logRef, {
      transactionId,
      senderId,
      receiverId: String(tx.receiverId || ''),
      amount,
      eventType: 'PAYMENT_TIMED_OUT',
      status: 'timedOut',
      createdAt: now,
      source: 'cleanup_scheduler',
    });

    return { ok: true, status: 'timedOut', refunded: true };
  });

  return outcome;
}

exports.approveEscrowPayment = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const actorUid = requireSecuredCaller(context);
    const transactionId = String(data?.transactionId || '').trim();
    if (!transactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'transactionId is required.');
    }

    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const now = Timestamp.now();
    const nowMs = Date.now();

    const result = await db.runTransaction(async (txn) => {
      const txSnap = await txn.get(txRef);
      if (!txSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Transaction not found.');
      }

      const tx = txSnap.data() || {};
      if (String(tx.receiverId || '') !== actorUid) {
        throw new functions.https.HttpsError('permission-denied', 'Only receiver can approve.');
      }

      if (tx.status !== 'pending') {
        return { ok: true, status: tx.status, alreadyFinalized: true };
      }

      const expiresAtMs = getTxMillis(tx.expiresAt);
      if (expiresAtMs > 0 && expiresAtMs <= nowMs) {
        throw new functions.https.HttpsError('failed-precondition', 'Transaction already expired.');
      }

      txn.update(txRef, {
        status: 'approved',
        approvedAt: now,
        approvedVia: 'server_callable',
        updatedAt: now,
      });

      txn.set(reqRef, {
        status: 'approved',
        approvedAt: now,
        updatedAt: now,
      }, { merge: true });

      return { ok: true, status: 'approved' };
    });

    return result;
  });

exports.completeEscrowPayment = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const actorUid = requireSecuredCaller(context);
    const transactionId = String(data?.transactionId || '').trim();
    if (!transactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'transactionId is required.');
    }

    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async (txn) => {
      const txSnap = await txn.get(txRef);
      if (!txSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Transaction not found.');
      }

      const tx = txSnap.data() || {};
      if (String(tx.senderId || '') !== actorUid) {
        throw new functions.https.HttpsError('permission-denied', 'Only sender can complete.');
      }

      if (tx.status === 'completed') {
        return { ok: true, status: 'completed', alreadyFinalized: true };
      }
      if (tx.status !== 'approved') {
        throw new functions.https.HttpsError('failed-precondition', 'Transaction is not approved.');
      }

      const receiverId = String(tx.receiverId || '').trim();
      const amount = Number(tx.amount || 0);
      if (!receiverId || !Number.isFinite(amount) || amount <= 0) {
        throw new functions.https.HttpsError('failed-precondition', 'Invalid transaction payload.');
      }

      const receiverWalletRef = db.collection('wallets').doc(receiverId);
      const receiverWalletSnap = await txn.get(receiverWalletRef);
      if (!receiverWalletSnap.exists) {
        txn.set(receiverWalletRef, {
          userId: receiverId,
          balance: 0,
          createdAt: now,
          updatedAt: now,
        }, { merge: true });
      }

      txn.update(receiverWalletRef, {
        balance: FieldValue.increment(amount),
        updatedAt: now,
      });

      txn.update(txRef, {
        status: 'completed',
        completedAt: now,
        isEscrow: false,
        settledVia: 'server_callable',
        updatedAt: now,
      });

      txn.set(reqRef, {
        status: 'completed',
        completedAt: now,
        updatedAt: now,
      }, { merge: true });

      const logRef = db.collection('transaction_logs').doc();
      txn.set(logRef, {
        transactionId,
        senderId: String(tx.senderId || ''),
        receiverId,
        amount,
        eventType: 'PAYMENT_COMPLETED',
        status: 'completed',
        createdAt: now,
        source: 'complete_callable',
      });

      return { ok: true, status: 'completed' };
    });

    return result;
  });

exports.rejectEscrowPayment = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const actorUid = requireSecuredCaller(context);
    const transactionId = String(data?.transactionId || '').trim();
    const reason = String(data?.reason || 'Rejected by receiver').trim();
    if (!transactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'transactionId is required.');
    }

    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async (txn) => {
      const txSnap = await txn.get(txRef);
      if (!txSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Transaction not found.');
      }

      const tx = txSnap.data() || {};
      if (String(tx.receiverId || '') !== actorUid) {
        throw new functions.https.HttpsError('permission-denied', 'Only receiver can reject.');
      }

      if (tx.status === 'rejected' || tx.status === 'refunded' || tx.status === 'timedOut') {
        return { ok: true, status: tx.status, alreadyFinalized: true };
      }
      if (tx.status !== 'pending') {
        throw new functions.https.HttpsError('failed-precondition', 'Only pending transactions can be rejected.');
      }

      const senderId = String(tx.senderId || '').trim();
      const amount = Number(tx.amount || 0);
      if (!senderId || !Number.isFinite(amount) || amount <= 0) {
        throw new functions.https.HttpsError('failed-precondition', 'Invalid transaction payload.');
      }

      const senderWalletRef = db.collection('wallets').doc(senderId);
      const senderWalletSnap = await txn.get(senderWalletRef);
      if (!senderWalletSnap.exists) {
        throw new functions.https.HttpsError('failed-precondition', 'Sender wallet not found.');
      }

      txn.update(senderWalletRef, {
        balance: FieldValue.increment(amount),
        updatedAt: now,
      });

      txn.update(txRef, {
        status: 'rejected',
        completedAt: now,
        isEscrow: false,
        rejectionReason: reason,
        settledVia: 'server_callable',
        updatedAt: now,
      });

      txn.set(reqRef, {
        status: 'rejected',
        completedAt: now,
        rejectionReason: reason,
        updatedAt: now,
      }, { merge: true });

      return { ok: true, status: 'rejected' };
    });

    return result;
  });

exports.cancelEscrowPayment = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    const actorUid = requireSecuredCaller(context);
    const transactionId = String(data?.transactionId || '').trim();
    const reason = String(data?.reason || 'Emergency sender cancel').trim();
    if (!transactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'transactionId is required.');
    }

    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const now = Timestamp.now();
    const nowMs = Date.now();

    const result = await db.runTransaction(async (txn) => {
      const txSnap = await txn.get(txRef);
      if (!txSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Transaction not found.');
      }

      const tx = txSnap.data() || {};
      if (String(tx.senderId || '') !== actorUid) {
        throw new functions.https.HttpsError('permission-denied', 'Only sender can cancel.');
      }

      if (tx.status === 'refunded' || tx.status === 'rejected' || tx.status === 'timedOut') {
        return { ok: true, status: tx.status, alreadyFinalized: true };
      }
      if (!(tx.status === 'pending' || tx.status === 'approved')) {
        throw new functions.https.HttpsError('failed-precondition', 'Transaction cannot be cancelled.');
      }

      const cancelUntilMs = getTxMillis(tx.cancelUntil);
      if (cancelUntilMs > 0 && nowMs > cancelUntilMs) {
        throw new functions.https.HttpsError('failed-precondition', 'Cancellation window expired.');
      }

      const senderId = String(tx.senderId || '').trim();
      const amount = Number(tx.amount || 0);
      if (!senderId || !Number.isFinite(amount) || amount <= 0) {
        throw new functions.https.HttpsError('failed-precondition', 'Invalid transaction payload.');
      }

      const senderWalletRef = db.collection('wallets').doc(senderId);
      const senderWalletSnap = await txn.get(senderWalletRef);
      if (!senderWalletSnap.exists) {
        throw new functions.https.HttpsError('failed-precondition', 'Sender wallet not found.');
      }

      txn.update(senderWalletRef, {
        balance: FieldValue.increment(amount),
        updatedAt: now,
      });

      txn.update(txRef, {
        status: 'refunded',
        completedAt: now,
        cancellationReason: reason,
        isEscrow: false,
        settledVia: 'server_callable',
        updatedAt: now,
      });

      txn.set(reqRef, {
        status: 'refunded',
        completedAt: now,
        cancellationReason: reason,
        updatedAt: now,
      }, { merge: true });

      return { ok: true, status: 'refunded' };
    });

    return result;
  });

exports.timeoutEscrowPayment = functions
  .region(REGION)
  .https
  .onCall(async (data, context) => {
    requireSecuredCaller(context);

    const transactionId = String(data?.transactionId || '').trim();
    if (!transactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'transactionId is required.');
    }

    return markTimedOutAndRefund({
      transactionId,
      now: Timestamp.now(),
    });
  });

function isSuccessfulStatus(status) {
  return status === 'success' || status === 'completed';
}

function normalizeAmount(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  return Math.round(amount * 100) / 100;
}

function getReceiverTokens(userData) {
  const tokenSet = new Set();

  if (typeof userData?.fcmToken === 'string' && userData.fcmToken.trim()) {
    tokenSet.add(userData.fcmToken.trim());
  }

  if (Array.isArray(userData?.fcmTokens)) {
    for (const token of userData.fcmTokens) {
      if (typeof token === 'string' && token.trim()) {
        tokenSet.add(token.trim());
      }
    }
  }

  return Array.from(tokenSet);
}

function validateTransactionData(txData) {
  const senderId = typeof txData?.senderId === 'string' ? txData.senderId.trim() : '';
  const receiverId = typeof txData?.receiverId === 'string' ? txData.receiverId.trim() : '';
  const senderName = typeof txData?.senderName === 'string' && txData.senderName.trim()
    ? txData.senderName.trim()
    : 'Someone';
  const amount = normalizeAmount(txData?.amount);
  const type = typeof txData?.type === 'string' ? txData.type : 'send';

  const isValid = Boolean(senderId) && Boolean(receiverId) && senderId !== receiverId && amount !== null;
  return {
    isValid,
    senderId,
    receiverId,
    senderName,
    amount,
    type,
  };
}

async function acquireNotificationLock(txRef, lockField) {
  const shouldSend = await db.runTransaction(async (txn) => {
    const snap = await txn.get(txRef);
    if (!snap.exists) return false;
    if (snap.get(lockField) === true) return false;

    txn.update(txRef, {
      [lockField]: true,
      [`${lockField}At`]: FieldValue.serverTimestamp(),
    });
    return true;
  });

  return shouldSend;
}

async function pruneInvalidToken(userId, token) {
  try {
    await db.collection('users').doc(userId).set({
      fcmToken: FieldValue.delete(),
      fcmTokens: FieldValue.arrayRemove(token),
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    logger.warn('Removed invalid FCM token', { userId, tokenSnippet: token.slice(0, 10) });
  } catch (error) {
    logger.error('Failed to remove invalid token', {
      userId,
      code: error?.code,
      message: error?.message,
    });
  }
}

function getChannelByCategory(category) {
  if (category === 'payment_request') return 'safepay_payment_req';
  return 'safepay_general';
}

async function sendToUserTokens({ userId, title, body, data, category = 'general' }) {
  logger.info('Fetching user token(s)', { userId, category });
  const userSnap = await db.collection('users').doc(userId).get();

  if (!userSnap.exists) {
    logger.warn('User doc not found for push', { userId, category });
    return { sent: 0, skipped: true, reason: 'user_not_found' };
  }

  const userData = userSnap.data() || {};
  const notificationsEnabled = userData.notificationsEnabled !== false;
  if (!notificationsEnabled) {
    logger.info('User has notifications disabled', { userId, category });
    return { sent: 0, skipped: true, reason: 'notifications_disabled' };
  }

  const tokens = getReceiverTokens(userData);
  if (tokens.length === 0) {
    logger.warn('No FCM token found for user', { userId, category });
    return { sent: 0, skipped: true, reason: 'no_token' };
  }

  logger.info('Attempting push send', { userId, category, tokenCount: tokens.length });

  const channelId = getChannelByCategory(category);

  if (tokens.length === 1) {
    try {
      const messageId = await messaging.send({
        token: tokens[0],
        notification: { title, body },
        data,
        android: {
          priority: 'high',
          notification: {
            channelId,
            sound: 'default',
            tag: data?.transactionId || category,
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: {
              sound: 'default',
              ...(category === 'payment_request' ? { category: 'PAYMENT_REQUEST' } : {}),
            },
          },
        },
      });

      logger.info('Push sent successfully', { userId, category, messageId });
      return { sent: 1, skipped: false };
    } catch (error) {
      logger.error('Push send failed', {
        userId,
        category,
        code: error?.code,
        message: error?.message,
      });

      if (
        error?.code === 'messaging/registration-token-not-registered' ||
        error?.code === 'messaging/invalid-registration-token'
      ) {
        await pruneInvalidToken(userId, tokens[0]);
      }
      return { sent: 0, skipped: false, reason: 'send_failed' };
    }
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: {
      priority: 'high',
      notification: {
        channelId,
        sound: 'default',
        tag: data?.transactionId || category,
      },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: 'default',
          ...(category === 'payment_request' ? { category: 'PAYMENT_REQUEST' } : {}),
        },
      },
    },
  });

  let failures = 0;
  await Promise.all(response.responses.map(async (res, idx) => {
    if (res.success) return;
    failures += 1;
    const errorCode = res.error?.code;

    logger.error('Multicast push token failed', {
      userId,
      category,
      code: errorCode,
      message: res.error?.message,
      tokenIndex: idx,
    });

    if (
      errorCode === 'messaging/registration-token-not-registered' ||
      errorCode === 'messaging/invalid-registration-token'
    ) {
      await pruneInvalidToken(userId, tokens[idx]);
    }
  }));

  logger.info('Multicast send complete', {
    userId,
    category,
    successCount: response.successCount,
    failureCount: failures,
  });

  return {
    sent: response.successCount,
    skipped: false,
    failures,
  };
}

async function sendPaymentRequestNotification({ transactionRef, transactionId, txData }) {
  const valid = validateTransactionData(txData);
  if (!valid.isValid || valid.type !== 'send' || txData.status !== 'pending') {
    logger.warn('Skipping payment-request push due to invalid transaction data', {
      transactionId,
      status: txData.status,
      type: valid.type,
      senderId: valid.senderId,
      receiverId: valid.receiverId,
      amount: valid.amount,
    });
    return;
  }

  const lockAcquired = await acquireNotificationLock(
    transactionRef,
    'notificationMeta.requestSent',
  );

  if (!lockAcquired) {
    logger.info('Skipping duplicate payment-request push', { transactionId });
    return;
  }

  const riskLevel = typeof txData.riskLevel === 'string' ? txData.riskLevel : 'Low Risk';
  const riskEmoji = riskLevel === 'High Risk' ? '🔴' : (riskLevel === 'Medium Risk' ? '🟡' : '🟢');

  await sendToUserTokens({
    userId: valid.receiverId,
    title: '💸 Payment Request',
    body: `${valid.senderName} wants to send ₹${Math.round(valid.amount)} to you`,
    data: {
      type: 'payment_request',
      transactionId,
      senderId: valid.senderId,
      receiverId: valid.receiverId,
      senderName: valid.senderName,
      amount: String(valid.amount),
      riskLevel,
      riskEmoji,
    },
    category: 'payment_request',
  });
}

async function sendPaymentReceivedNotification({ transactionRef, transactionId, txData, source }) {
  const valid = validateTransactionData(txData);
  if (!valid.isValid || valid.type !== 'send' || !isSuccessfulStatus(txData.status)) {
    logger.warn('Skipping payment-received push due to invalid transaction data', {
      transactionId,
      source,
      status: txData.status,
      type: valid.type,
      senderId: valid.senderId,
      receiverId: valid.receiverId,
      amount: valid.amount,
    });
    return;
  }

  const lockAcquired = await acquireNotificationLock(
    transactionRef,
    'notificationMeta.receiverPaymentSent',
  );

  if (!lockAcquired) {
    logger.info('Skipping duplicate payment-received push', { transactionId, source });
    return;
  }

  await sendToUserTokens({
    userId: valid.receiverId,
    title: PAYMENT_RECEIVED_TITLE,
    body: `You received ₹${Math.round(valid.amount)} from ${valid.senderName}`,
    data: {
      type: 'payment_received',
      transactionId,
      amount: String(valid.amount),
      senderId: valid.senderId,
      senderName: valid.senderName,
    },
    category: 'payment_received',
  });
}

exports.onPaymentRequestCreated = functions
  .region(REGION)
  .firestore
  .document('transactions/{transactionId}')
  .onCreate(async (snap, context) => {
    if (!snap) return null;

    const txData = snap.data();
    const transactionId = context.params.transactionId;

    logger.info('Trigger fired: onPaymentRequestCreated', {
      transactionId,
      status: txData?.status,
      senderId: txData?.senderId,
      receiverId: txData?.receiverId,
    });

    try {
      if (txData?.status === 'pending') {
        await sendPaymentRequestNotification({
          transactionRef: snap.ref,
          transactionId,
          txData,
        });
      }

      if (isSuccessfulStatus(txData?.status)) {
        await sendPaymentReceivedNotification({
          transactionRef: snap.ref,
          transactionId,
          txData,
          source: 'create',
        });
      }
    } catch (error) {
      logger.error('onPaymentRequestCreated failed', {
        transactionId,
        code: error?.code,
        message: error?.message,
      });
      throw error;
    }

    return null;
  });

exports.onPaymentStatusChanged = functions
  .region(REGION)
  .firestore
  .document('transactions/{transactionId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before?.data();
    const afterData = change.after?.data();
    const transactionId = context.params.transactionId;

    if (!beforeData || !afterData) return null;

    const prevStatus = beforeData.status;
    const newStatus = afterData.status;

    logger.info('Trigger fired: onPaymentStatusChanged', {
      transactionId,
      prevStatus,
      newStatus,
      senderId: afterData.senderId,
      receiverId: afterData.receiverId,
    });

    if (prevStatus === newStatus) {
      logger.info('Skipping status trigger: status unchanged', { transactionId, status: newStatus });
      return null;
    }

    try {
      if (newStatus === 'approved' && prevStatus === 'pending') {
        await _sendPushToUser({
          userId: afterData.senderId,
          title: 'Payment Approved! 🎉',
          body: `${afterData.receiverName || 'Receiver'} accepted your ₹${Math.round(afterData.amount || 0)} request. Enter your UPI PIN to complete.`,
          data: {
            type: 'payment_approved',
            transactionId,
          },
        });
      }

      if (newStatus === 'rejected' && prevStatus === 'pending') {
        await _sendPushToUser({
          userId: afterData.senderId,
          title: 'Payment Rejected',
          body: `${afterData.receiverName || 'Receiver'} rejected your ₹${Math.round(afterData.amount || 0)} payment. Amount refunded.`,
          data: {
            type: 'payment_rejected',
            transactionId,
          },
        });
      }

      if (!isSuccessfulStatus(prevStatus) && isSuccessfulStatus(newStatus)) {
        await sendPaymentReceivedNotification({
          transactionRef: change.after.ref,
          transactionId,
          txData: afterData,
          source: 'status_update',
        });
      }
    } catch (error) {
      logger.error('onPaymentStatusChanged failed', {
        transactionId,
        code: error?.code,
        message: error?.message,
      });
      throw error;
    }

    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// 3. ON IN-APP NOTIFICATION CREATED — Mirror to FCM tray notification
// ─────────────────────────────────────────────────────────────────────────────

exports.onInAppNotificationCreated = functions
  .region(REGION)
  .firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    if (!snap) return null;

    const notificationId = context.params.notificationId;
    const payload = snap.data() || {};

    logger.info('Trigger fired: onInAppNotificationCreated', {
      notificationId,
      userId: payload.userId,
      type: payload.type,
    });

    const userId = typeof payload.userId === 'string' ? payload.userId.trim() : '';
    const title = typeof payload.title === 'string' ? payload.title.trim() : '';
    const body = typeof payload.body === 'string' ? payload.body.trim() : '';
    const type = typeof payload.type === 'string' ? payload.type.trim() : 'general';
    const data = payload.data && typeof payload.data === 'object' ? payload.data : {};

    if (!userId || !title || !body) {
      logger.warn('Skipping push: invalid in-app notification payload', {
        notificationId,
        userId,
        hasTitle: Boolean(title),
        hasBody: Boolean(body),
      });
      return null;
    }

    // Retry-safe dedupe lock for this notification document.
    const lockAcquired = await db.runTransaction(async (txn) => {
      const fresh = await txn.get(snap.ref);
      if (!fresh.exists) return false;
      if (fresh.get('pushMeta.sent') === true) return false;
      txn.update(snap.ref, {
        'pushMeta.sent': true,
        'pushMeta.sentAt': FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!lockAcquired) {
      logger.info('Skipping duplicate notification push', { notificationId, userId });
      return null;
    }

    const txIdRaw = data.transactionId;
    const amountRaw = data.amount;

    await sendToUserTokens({
      userId,
      title,
      body,
      data: {
        type,
        notificationId,
        transactionId: txIdRaw != null ? String(txIdRaw) : '',
        amount: amountRaw != null ? String(amountRaw) : '',
      },
      category: type === 'payment_request' ? 'payment_request' : 'general',
    });

    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// 4. CLEANUP EXPIRED PAYMENTS (Scheduled every 5 minutes)
// ─────────────────────────────────────────────────────────────────────────────

exports.cleanupExpiredPayments = onSchedule(
  {
    schedule: 'every 5 minutes',
    region: 'asia-south1',
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  async () => {
    const now = Timestamp.now();

    try {
      const expiredSnap = await db
        .collection('transactions')
        .where('status', '==', 'pending')
        .where('expiresAt', '<=', now)
        .limit(50) // Process in batches
        .get();

      if (expiredSnap.empty) {
        logger.info('[cleanupExpiredPayments] No expired transactions found');
        return null;
      }

      logger.info('[cleanupExpiredPayments] Processing expired transactions', {
        count: expiredSnap.size,
      });

      let processedCount = 0;
      for (const doc of expiredSnap.docs) {
        const outcome = await markTimedOutAndRefund({
          transactionId: doc.id,
          now,
        });

        if (outcome?.status === 'timedOut') {
          processedCount += 1;
          const data = doc.data();
          await db.collection('notifications').add({
            userId: data.senderId,
            title: 'Payment Expired ⏰',
            body: `Your ₹${Math.round(data.amount)} payment to ${data.receiverName || 'receiver'} expired. Amount refunded.`,
            type: 'payment_expired',
            data: { transactionId: doc.id },
            isRead: false,
            createdAt: now,
          });
        }
      }

      logger.info('[cleanupExpiredPayments] Processed expired transactions', {
        scanned: expiredSnap.size,
        processed: processedCount,
      });
      return null;
    } catch (error) {
      logger.error('[cleanupExpiredPayments] Error', {
        code: error?.code,
        message: error?.message,
      });
      return null;
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Send push notification to a user
// ─────────────────────────────────────────────────────────────────────────────

async function _sendPushToUser({ userId, title, body, data = {} }) {
  try {
    await sendToUserTokens({
      userId,
      title,
      body,
      data,
      category: 'status_update',
    });
    logger.info('Status push send attempted', { userId, title });
  } catch (error) {
    logger.error('Status push send failed', {
      userId,
      code: error?.code,
      message: error?.message,
    });
  }
}
