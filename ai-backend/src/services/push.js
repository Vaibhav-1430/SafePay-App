const { getDb, getMessaging } = require('../config/firebase');

const db = getDb();

async function sendPushToUser({ userId, title, body, data = {} }) {
  if (!userId) return;

  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) return;

  const user = userDoc.data() || {};
  const token = user.fcmToken || user.deviceToken;
  const notificationsEnabled = user.notificationsEnabled !== false;
  if (!token || !notificationsEnabled) return;

  try {
    const messaging = getMessaging();
    await messaging.send({
      token,
      notification: {
        title,
        body,
      },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v ?? '')])
      ),
      android: {
        priority: 'high',
        notification: {
          channelId: 'safepay_general',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: { sound: 'default' },
        },
      },
    });
  } catch (error) {
    const code = error && error.code ? String(error.code) : '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      await db.collection('users').doc(userId).set({
        fcmToken: null,
      }, { merge: true });
    }
  }
}

module.exports = {
  sendPushToUser,
};
