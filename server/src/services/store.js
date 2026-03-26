const { getFirestore, admin } = require('../config/firebase');

const memory = {
  users: new Map(),
  txLogs: [],
};

function nowIso() {
  return new Date().toISOString();
}

async function upsertUser(user) {
  const db = getFirestore();
  if (!db) {
    memory.users.set(user.uid, { ...user, updatedAt: nowIso() });
    return { ...user, updatedAt: nowIso() };
  }

  const ref = db.collection('server_users').doc(user.uid);
  await ref.set({ ...user, updatedAt: admin.firestore.Timestamp.now() }, { merge: true });
  const snap = await ref.get();
  return { uid: snap.id, ...snap.data() };
}

async function getUser(uid) {
  const db = getFirestore();
  if (!db) return memory.users.get(uid) || null;

  const snap = await db.collection('server_users').doc(uid).get();
  if (!snap.exists) return null;
  return { uid: snap.id, ...snap.data() };
}

async function getUserByPhone(phoneNormalized) {
  const db = getFirestore();
  if (!db) {
    for (const user of memory.users.values()) {
      if (
        user.phoneNormalized === phoneNormalized ||
        user.phone === phoneNormalized ||
        user.phone === `+91${phoneNormalized}`
      ) {
        return user;
      }
    }
    return null;
  }

  let query = await db
    .collection('server_users')
    .where('phoneNormalized', '==', phoneNormalized)
    .limit(1)
    .get();
  if (!query.empty) {
    const doc = query.docs[0];
    return { uid: doc.id, ...doc.data() };
  }

  query = await db
    .collection('server_users')
    .where('phone', '==', phoneNormalized)
    .limit(1)
    .get();
  if (!query.empty) {
    const doc = query.docs[0];
    return { uid: doc.id, ...doc.data() };
  }

  query = await db
    .collection('server_users')
    .where('phone', '==', `+91${phoneNormalized}`)
    .limit(1)
    .get();
  if (!query.empty) {
    const doc = query.docs[0];
    return { uid: doc.id, ...doc.data() };
  }

  return null;
}

async function logTransaction(payload) {
  const db = getFirestore();
  const entry = {
    ...payload,
    createdAt: nowIso(),
  };

  if (!db) {
    memory.txLogs.push(entry);
    return entry;
  }

  const ref = await db.collection('transaction_logs').add({
    ...payload,
    createdAt: admin.firestore.Timestamp.now(),
  });
  return { id: ref.id, ...entry };
}

async function listTransactionsForUser(userId) {
  const db = getFirestore();
  if (!db) {
    return memory.txLogs.filter((tx) => tx.senderId === userId || tx.receiverId === userId);
  }

  const bySender = db.collection('transaction_logs').where('senderId', '==', userId).limit(100).get();
  const byReceiver = db.collection('transaction_logs').where('receiverId', '==', userId).limit(100).get();
  const [senderSnap, receiverSnap] = await Promise.all([bySender, byReceiver]);

  const merged = [
    ...senderSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    ...receiverSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
  ];

  const seen = new Set();
  return merged.filter((tx) => {
    const id = tx.id || `${tx.senderId}-${tx.receiverId}-${tx.transactionId}`;
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

module.exports = {
  upsertUser,
  getUser,
  getUserByPhone,
  logTransaction,
  listTransactionsForUser,
};
