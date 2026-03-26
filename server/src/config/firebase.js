const admin = require('firebase-admin');
const env = require('./env');

let firestore = null;

function initFirebase() {
  if (admin.apps.length > 0) {
    firestore = admin.firestore();
    return firestore;
  }

  if (!env.firebaseProjectId || !env.firebaseClientEmail || !env.firebasePrivateKey) {
    return null;
  }

  const privateKey = env.firebasePrivateKey.replace(/\\n/g, '\n');

  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: env.firebaseProjectId,
      clientEmail: env.firebaseClientEmail,
      privateKey,
    }),
  });

  firestore = admin.firestore();
  return firestore;
}

function getFirestore() {
  return firestore || initFirebase();
}

module.exports = {
  admin,
  initFirebase,
  getFirestore,
};
