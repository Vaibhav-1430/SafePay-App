const admin = require('firebase-admin');

let initialized = false;

function buildCredentialFromEnv() {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKeyRaw = process.env.FIREBASE_PRIVATE_KEY;

  if (!projectId || !clientEmail || !privateKeyRaw) {
    return null;
  }

  return admin.credential.cert({
    projectId,
    clientEmail,
    privateKey: privateKeyRaw.replace(/\\n/g, '\n'),
  });
}

function ensureFirebase() {
  if (initialized) return;

  const credential = buildCredentialFromEnv();
  if (credential) {
    admin.initializeApp({ credential });
  } else {
    admin.initializeApp();
  }

  initialized = true;
}

function getDb() {
  ensureFirebase();
  return admin.firestore();
}

function getMessaging() {
  ensureFirebase();
  return admin.messaging();
}

module.exports = {
  admin,
  getDb,
  getMessaging,
};
