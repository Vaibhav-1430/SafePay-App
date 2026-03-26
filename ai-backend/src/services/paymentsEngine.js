const { createHash, randomUUID } = require('crypto');
const { getDb, admin } = require('../config/firebase');
const { analyzeTransaction } = require('./risk');

const db = getDb();

const STATUS = {
  PENDING: 'pending',
  COMPLETED: 'completed',
  REJECTED: 'rejected',
  REFUNDED: 'refunded',
};

const AUDIT_META_PATH = 'system/audit_meta';
const MAX_DELAY_MINUTES = 60;
const EMERGENCY_CANCEL_WINDOW_MS = 90 * 1000;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function riskLevelFromScore01(score01) {
  if (score01 >= 0.75) return 'HIGH';
  if (score01 >= 0.4) return 'MEDIUM';
  return 'LOW';
}

function riskLabelFromScore01(score01) {
  if (score01 >= 0.75) return 'High Risk';
  if (score01 >= 0.4) return 'Medium Risk';
  return 'Safe';
}

function safeDateFromTimestamp(value) {
  if (!value) return null;
  if (value.toDate) return value.toDate();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function buildAuditHash(payload) {
  return createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

function transactionDto(id, tx) {
  return {
    id,
    transactionId: id,
    senderId: tx.senderId,
    receiverId: tx.receiverId,
    senderName: tx.senderName || 'Sender',
    receiverName: tx.receiverName || 'Receiver',
    senderUpiId: tx.senderUpiId || '',
    receiverUpiId: tx.receiverUpiId || '',
    amount: tx.amount || 0,
    note: tx.note || null,
    status: tx.status,
    timestamp: safeDateFromTimestamp(tx.createdAt)?.toISOString() || tx.createdAt || null,
    createdAt: safeDateFromTimestamp(tx.createdAt)?.toISOString() || tx.createdAt || null,
    updatedAt: safeDateFromTimestamp(tx.updatedAt)?.toISOString() || tx.updatedAt || null,
    approvedAt: safeDateFromTimestamp(tx.approvedAt)?.toISOString() || tx.approvedAt || null,
    rejectedAt: safeDateFromTimestamp(tx.rejectedAt)?.toISOString() || tx.rejectedAt || null,
    completedAt: safeDateFromTimestamp(tx.completedAt)?.toISOString() || tx.completedAt || null,
    releaseAt: safeDateFromTimestamp(tx.releaseAt)?.toISOString() || tx.releaseAt || null,
    cancelUntil: safeDateFromTimestamp(tx.cancelUntil)?.toISOString() || tx.cancelUntil || null,
    riskScore: tx.riskScore || 0,
    riskLevel: tx.riskLevel || 'Safe',
    riskFlags: tx.riskFlags || [],
    warnings: tx.warnings || [],
    delayMinutes: tx.delayMinutes || 0,
    audit: {
      blockIndex: tx.blockIndex || null,
      previousHash: tx.previousHash || null,
      hash: tx.hash || null,
    },
  };
}

async function countSenderTxLast24h(senderId) {
  const since = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000));
  const snap = await db
    .collection('transactions')
    .where('senderId', '==', senderId)
    .where('createdAt', '>=', since)
    .limit(50)
    .get();
  return snap.size;
}

async function hasTrustedContact(senderId, receiverId) {
  const snap = await db
    .collection('trusted_contacts')
    .where('ownerUserId', '==', senderId)
    .where('contactUserId', '==', receiverId)
    .limit(1)
    .get();
  return !snap.empty;
}

async function historicalAmountsForSender(senderId) {
  const snap = await db
    .collection('transactions')
    .where('senderId', '==', senderId)
    .where('status', '==', STATUS.COMPLETED)
    .orderBy('createdAt', 'desc')
    .limit(15)
    .get();
  return snap.docs
    .map((d) => Number(d.data().amount || 0))
    .filter((a) => Number.isFinite(a) && a > 0);
}

async function computeRisk({ senderId, receiverId, amount }) {
  const [senderDoc, trusted, txCount24h, history] = await Promise.all([
    db.collection('users').doc(senderId).get(),
    hasTrustedContact(senderId, receiverId),
    countSenderTxLast24h(senderId),
    historicalAmountsForSender(senderId),
  ]);

  let score = 0.12;
  const flags = [];

  const senderCreatedAt = safeDateFromTimestamp(senderDoc.data()?.createdAt);
  if (!senderCreatedAt || Date.now() - senderCreatedAt.getTime() < 7 * 24 * 60 * 60 * 1000) {
    score += 0.22;
    flags.push('New user');
  }

  if (amount >= 10000) {
    score += 0.28;
    flags.push('High amount');
  } else if (amount >= 5000) {
    score += 0.16;
    flags.push('Above normal amount');
  }

  if (!trusted) {
    score += 0.18;
    flags.push('Unknown receiver');
  }

  if (txCount24h >= 6) {
    score += 0.2;
    flags.push('Frequent transactions');
  }

  if (history.length >= 3) {
    const avg = history.reduce((a, b) => a + b, 0) / history.length;
    if (amount > avg * 3) {
      score += 0.15;
      flags.push('Amount anomaly');
    }
  }

  const ai = analyzeTransaction({
    senderId,
    receiverId,
    amount,
    known_receiver: trusted,
    tx_count_last_24h: txCount24h,
    unusual_spending_pattern: flags.includes('Amount anomaly'),
    historical_amounts: history,
  });

  const blended = clamp((score * 0.55) + ((ai.risk_score || 0) * 0.45), 0, 1);
  const triggers = [...new Set([...(ai.triggers || []), ...flags])];
  return {
    riskScore01: blended,
    riskScore100: Math.round(blended * 100),
    riskLevel: riskLabelFromScore01(blended),
    riskLevelKey: riskLevelFromScore01(blended),
    flags: triggers,
  };
}

async function _loadUserWalletTx(txn, userId) {
  const walletRef = db.collection('wallets').doc(userId);
  const walletSnap = await txn.get(walletRef);
  if (!walletSnap.exists) {
    throw new Error('Wallet missing');
  }
  const wallet = walletSnap.data() || {};
  return {
    walletRef,
    available: Number(wallet.balance || 0),
    reserved: Number(wallet.reservedBalance || 0),
  };
}

async function _appendAuditInTxn(txn, { txId, eventType, txData, metadata = {} }) {
  const metaRef = db.doc(AUDIT_META_PATH);
  const metaSnap = await txn.get(metaRef);
  const meta = metaSnap.exists ? (metaSnap.data() || {}) : {};
  const blockIndex = Number(meta.blockIndex || 0) + 1;
  const previousHash = meta.lastHash || 'GENESIS';
  const createdAt = new Date().toISOString();

  const payload = {
    blockIndex,
    eventType,
    transactionId: txId,
    senderId: txData.senderId,
    receiverId: txData.receiverId,
    amount: txData.amount,
    status: txData.status,
    riskLevel: txData.riskLevel,
    riskScore: txData.riskScore,
    previousHash,
    metadata,
    createdAt,
  };
  const hash = buildAuditHash(payload);

  const logRef = db.collection('transaction_logs').doc();
  txn.set(logRef, {
    ...payload,
    hash,
    createdAt: admin.firestore.Timestamp.fromDate(new Date(createdAt)),
  });
  txn.set(metaRef, { blockIndex, lastHash: hash, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  return { blockIndex, previousHash, hash };
}

async function sendPayment({
  senderId,
  receiverId,
  amount,
  note,
  senderName,
  receiverName,
  senderUpiId,
  receiverUpiId,
  clientTransactionId,
  delayMinutes = 0,
}) {
  if (senderId === receiverId) {
    throw new Error('Sender and receiver cannot be the same');
  }

  const safeDelay = clamp(Number(delayMinutes || 0), 0, MAX_DELAY_MINUTES);
  const txId = clientTransactionId || randomUUID();
  const risk = await computeRisk({ senderId, receiverId, amount });

  await db.runTransaction(async (txn) => {
    const txRef = db.collection('transactions').doc(txId);
    const existingTx = await txn.get(txRef);
    if (existingTx.exists) {
      return;
    }

    const idemRef = db.collection('idempotency_keys').doc(`${senderId}_${txId}`);
    const idemSnap = await txn.get(idemRef);
    if (idemSnap.exists) {
      return;
    }

    const senderWallet = await _loadUserWalletTx(txn, senderId);
    if (senderWallet.available < amount) {
      throw new Error('Insufficient balance');
    }

    const now = new Date();
    const nowTs = admin.firestore.Timestamp.fromDate(now);
    const releaseAt = safeDelay > 0
      ? admin.firestore.Timestamp.fromDate(new Date(now.getTime() + safeDelay * 60 * 1000))
      : null;
    const cancelUntil = admin.firestore.Timestamp.fromDate(new Date(now.getTime() + EMERGENCY_CANCEL_WINDOW_MS));

    txn.update(senderWallet.walletRef, {
      balance: senderWallet.available - amount,
      reservedBalance: senderWallet.reserved + amount,
      updatedAt: nowTs,
    });

    const paymentRef = db.collection('payment_requests').doc(txId);
    const txData = {
      senderId,
      receiverId,
      senderName: senderName || 'Sender',
      receiverName: receiverName || 'Receiver',
      senderUpiId: senderUpiId || '',
      receiverUpiId: receiverUpiId || '',
      amount,
      note: note || null,
      status: STATUS.PENDING,
      createdAt: nowTs,
      updatedAt: nowTs,
      releaseAt,
      cancelUntil,
      delayMinutes: safeDelay,
      isEscrow: true,
      riskScore01: risk.riskScore01,
      riskScore: risk.riskScore100,
      riskLevelKey: risk.riskLevelKey,
      riskLevel: risk.riskLevel,
      riskFlags: risk.flags,
    };

    const audit = await _appendAuditInTxn(txn, {
      txId,
      eventType: 'REQUESTED',
      txData,
      metadata: {
        delayMinutes: safeDelay,
      },
    });

    const txWithAudit = {
      ...txData,
      blockIndex: audit.blockIndex,
      previousHash: audit.previousHash,
      hash: audit.hash,
    };

    txn.set(txRef, txWithAudit, { merge: false });
    txn.set(paymentRef, txWithAudit, { merge: false });
    txn.set(idemRef, {
      senderId,
      transactionId: txId,
      createdAt: nowTs,
    });
  });

  const txDoc = await db.collection('transactions').doc(txId).get();
  if (!txDoc.exists) {
    throw new Error('Failed to create transaction');
  }

  return transactionDto(txDoc.id, txDoc.data() || {});
}

async function approvePayment({ transactionId, receiverId, addToTrustedContacts = false }) {
  await db.runTransaction(async (txn) => {
    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const txSnap = await txn.get(txRef);
    if (!txSnap.exists) {
      throw new Error('Transaction not found');
    }
    const txData = txSnap.data() || {};
    if (txData.receiverId !== receiverId) {
      throw new Error('Only receiver can approve');
    }
    if (txData.status !== STATUS.PENDING) {
      return;
    }

    const now = new Date();
    const nowTs = admin.firestore.Timestamp.fromDate(now);
    const releaseAt = safeDateFromTimestamp(txData.releaseAt);
    if (releaseAt && now < releaseAt) {
      throw new Error(`Release delay active until ${releaseAt.toISOString()}`);
    }

    const senderWallet = await _loadUserWalletTx(txn, txData.senderId);
    const receiverWallet = await _loadUserWalletTx(txn, txData.receiverId);

    if (senderWallet.reserved < Number(txData.amount || 0)) {
      throw new Error('Reserved balance mismatch');
    }

    txn.update(senderWallet.walletRef, {
      reservedBalance: senderWallet.reserved - Number(txData.amount || 0),
      updatedAt: nowTs,
    });

    txn.update(receiverWallet.walletRef, {
      balance: receiverWallet.available + Number(txData.amount || 0),
      updatedAt: nowTs,
    });

    const next = {
      ...txData,
      status: STATUS.COMPLETED,
      approvedAt: nowTs,
      completedAt: nowTs,
      updatedAt: nowTs,
    };

    const audit = await _appendAuditInTxn(txn, {
      txId: transactionId,
      eventType: 'APPROVED',
      txData: next,
      metadata: {
        approvedBy: receiverId,
        addToTrustedContacts,
      },
    });

    next.blockIndex = audit.blockIndex;
    next.previousHash = audit.previousHash;
    next.hash = audit.hash;

    txn.set(txRef, next, { merge: true });
    txn.set(reqRef, next, { merge: true });

    if (addToTrustedContacts) {
      const trustedRef = db.collection('trusted_contacts').doc(`${txData.receiverId}_${txData.senderId}`);
      txn.set(trustedRef, {
        ownerUserId: txData.receiverId,
        contactUserId: txData.senderId,
        createdAt: nowTs,
      }, { merge: true });
    }
  });

  const txDoc = await db.collection('transactions').doc(transactionId).get();
  if (!txDoc.exists) throw new Error('Transaction not found');
  return transactionDto(txDoc.id, txDoc.data() || {});
}

async function rejectPayment({ transactionId, receiverId, reason }) {
  await db.runTransaction(async (txn) => {
    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const txSnap = await txn.get(txRef);
    if (!txSnap.exists) {
      throw new Error('Transaction not found');
    }
    const txData = txSnap.data() || {};
    if (txData.receiverId !== receiverId) {
      throw new Error('Only receiver can reject');
    }
    if (txData.status !== STATUS.PENDING) {
      return;
    }

    const nowTs = admin.firestore.Timestamp.now();
    const senderWallet = await _loadUserWalletTx(txn, txData.senderId);
    const amount = Number(txData.amount || 0);

    if (senderWallet.reserved < amount) {
      throw new Error('Reserved balance mismatch');
    }

    txn.update(senderWallet.walletRef, {
      reservedBalance: senderWallet.reserved - amount,
      balance: senderWallet.available + amount,
      updatedAt: nowTs,
    });

    const next = {
      ...txData,
      status: STATUS.REJECTED,
      rejectedAt: nowTs,
      updatedAt: nowTs,
      rejectionReason: reason || null,
    };

    const audit = await _appendAuditInTxn(txn, {
      txId: transactionId,
      eventType: 'REJECTED',
      txData: next,
      metadata: {
        rejectedBy: receiverId,
        reason: reason || null,
      },
    });

    next.blockIndex = audit.blockIndex;
    next.previousHash = audit.previousHash;
    next.hash = audit.hash;

    txn.set(txRef, next, { merge: true });
    txn.set(reqRef, next, { merge: true });
  });

  const txDoc = await db.collection('transactions').doc(transactionId).get();
  if (!txDoc.exists) throw new Error('Transaction not found');
  return transactionDto(txDoc.id, txDoc.data() || {});
}

async function emergencyCancel({ transactionId, senderId, reason }) {
  await db.runTransaction(async (txn) => {
    const txRef = db.collection('transactions').doc(transactionId);
    const reqRef = db.collection('payment_requests').doc(transactionId);
    const txSnap = await txn.get(txRef);
    if (!txSnap.exists) {
      throw new Error('Transaction not found');
    }

    const txData = txSnap.data() || {};
    if (txData.senderId !== senderId) {
      throw new Error('Only sender can cancel');
    }
    if (txData.status !== STATUS.PENDING) {
      throw new Error('Transaction cannot be cancelled now');
    }

    const cancelUntil = safeDateFromTimestamp(txData.cancelUntil);
    if (cancelUntil && Date.now() > cancelUntil.getTime()) {
      throw new Error('Emergency cancel window has expired');
    }

    const amount = Number(txData.amount || 0);
    const senderWallet = await _loadUserWalletTx(txn, senderId);
    if (senderWallet.reserved < amount) {
      throw new Error('Reserved balance mismatch');
    }

    const nowTs = admin.firestore.Timestamp.now();
    txn.update(senderWallet.walletRef, {
      reservedBalance: senderWallet.reserved - amount,
      balance: senderWallet.available + amount,
      updatedAt: nowTs,
    });

    const next = {
      ...txData,
      status: STATUS.REFUNDED,
      cancelledAt: nowTs,
      updatedAt: nowTs,
      cancellationReason: reason || 'Emergency sender cancel',
    };

    const audit = await _appendAuditInTxn(txn, {
      txId: transactionId,
      eventType: 'EMERGENCY_CANCELLED',
      txData: next,
      metadata: {
        cancelledBy: senderId,
        reason: next.cancellationReason,
      },
    });

    next.blockIndex = audit.blockIndex;
    next.previousHash = audit.previousHash;
    next.hash = audit.hash;

    txn.set(txRef, next, { merge: true });
    txn.set(reqRef, next, { merge: true });
  });

  const txDoc = await db.collection('transactions').doc(transactionId).get();
  if (!txDoc.exists) throw new Error('Transaction not found');
  return transactionDto(txDoc.id, txDoc.data() || {});
}

async function mergeUserTransactions(userId, limit = 50) {
  const boundedLimit = clamp(Number(limit || 50), 1, 200);

  const [sent, received] = await Promise.all([
    db.collection('transactions').where('senderId', '==', userId).orderBy('createdAt', 'desc').limit(boundedLimit).get(),
    db.collection('transactions').where('receiverId', '==', userId).orderBy('createdAt', 'desc').limit(boundedLimit).get(),
  ]);

  const mergedMap = new Map();
  for (const doc of [...sent.docs, ...received.docs]) {
    mergedMap.set(doc.id, doc);
  }

  return [...mergedMap.values()]
    .sort((a, b) => {
      const ad = safeDateFromTimestamp(a.data().createdAt)?.getTime() || 0;
      const bd = safeDateFromTimestamp(b.data().createdAt)?.getTime() || 0;
      return bd - ad;
    })
    .slice(0, boundedLimit)
    .map((doc) => transactionDto(doc.id, doc.data()));
}

async function fetchHistory(userId, limit = 50) {
  return mergeUserTransactions(userId, limit);
}

async function fetchPending(userId, limit = 50) {
  const boundedLimit = clamp(Number(limit || 50), 1, 200);
  const [sent, received] = await Promise.all([
    db.collection('transactions')
      .where('senderId', '==', userId)
      .where('status', '==', STATUS.PENDING)
      .orderBy('createdAt', 'desc')
      .limit(boundedLimit)
      .get(),
    db.collection('transactions')
      .where('receiverId', '==', userId)
      .where('status', '==', STATUS.PENDING)
      .orderBy('createdAt', 'desc')
      .limit(boundedLimit)
      .get(),
  ]);

  const map = new Map();
  for (const doc of [...sent.docs, ...received.docs]) {
    map.set(doc.id, doc);
  }

  return [...map.values()]
    .sort((a, b) => {
      const ad = safeDateFromTimestamp(a.data().createdAt)?.getTime() || 0;
      const bd = safeDateFromTimestamp(b.data().createdAt)?.getTime() || 0;
      return bd - ad;
    })
    .slice(0, boundedLimit)
    .map((doc) => transactionDto(doc.id, doc.data()));
}

async function fetchLogs(userId, limit = 40) {
  const boundedLimit = clamp(Number(limit || 40), 1, 200);
  const [sent, received] = await Promise.all([
    db.collection('transaction_logs')
      .where('senderId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(boundedLimit)
      .get(),
    db.collection('transaction_logs')
      .where('receiverId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(boundedLimit)
      .get(),
  ]);

  const map = new Map();
  for (const doc of [...sent.docs, ...received.docs]) {
    map.set(doc.id, doc.data());
  }

  return [...map.values()]
    .sort((a, b) => {
      const ad = safeDateFromTimestamp(a.createdAt)?.getTime() || 0;
      const bd = safeDateFromTimestamp(b.createdAt)?.getTime() || 0;
      return bd - ad;
    })
    .slice(0, boundedLimit)
    .map((entry) => ({
      ...entry,
      createdAt: safeDateFromTimestamp(entry.createdAt)?.toISOString() || null,
    }));
}

async function fetchDashboard(userId, days = 30) {
  const dayWindow = clamp(Number(days || 30), 1, 365);
  const since = new Date(Date.now() - dayWindow * 24 * 60 * 60 * 1000);
  const txs = await mergeUserTransactions(userId, 500);

  const recent = txs.filter((t) => {
    const d = t.createdAt ? new Date(t.createdAt) : null;
    return d && !Number.isNaN(d.getTime()) && d >= since;
  });

  const total = recent.length;
  const highRisk = recent.filter((t) => Number(t.riskScore || 0) >= 75).length;
  const mediumRisk = recent.filter((t) => {
    const s = Number(t.riskScore || 0);
    return s >= 40 && s < 75;
  }).length;
  const safe = recent.filter((t) => Number(t.riskScore || 0) < 40).length;
  const prevented = recent.filter((t) =>
    ['rejected', 'timedOut', 'refunded'].includes(t.status) && Number(t.riskScore || 0) >= 40
  ).length;
  const highRiskVolume = recent
    .filter((t) => Number(t.riskScore || 0) >= 75)
    .reduce((sum, t) => sum + Number(t.amount || 0), 0);

  return {
    windowDays: dayWindow,
    totalTransactions: total,
    safeTransactions: safe,
    mediumRiskTransactions: mediumRisk,
    highRiskTransactions: highRisk,
    preventedFraudCount: prevented,
    highRiskVolume,
  };
}

async function verifyRisk(payload) {
  const amount = Number(payload.amount || 0);
  const risk = await computeRisk({
    senderId: payload.senderId,
    receiverId: payload.receiverId,
    amount,
  });
  return {
    risk_score: risk.riskScore01,
    classification: risk.riskLevel,
    triggers: risk.flags,
    require_extra_verification: risk.riskScore01 >= 0.75,
    delay_recommended: risk.riskScore01 >= 0.75 && amount >= 7000,
  };
}

module.exports = {
  sendPayment,
  approvePayment,
  rejectPayment,
  emergencyCancel,
  fetchHistory,
  fetchPending,
  fetchLogs,
  fetchDashboard,
  verifyRisk,
};
