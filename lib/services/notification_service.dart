// =============================================================================
// NOTIFICATION SERVICE (COMPLETE REWRITE)
// lib/services/notification_service.dart
//
// Architecture:
//   This service manages the full lifecycle of push notifications for SafePay:
//
//   1. FCM Setup — Requests permission, retrieves & persists the FCM token,
//      and configures foreground / background / terminated-state listeners.
//
//   2. Actionable Payment-Request Notifications —
//      When a payment request is received, the receiver sees a rich notification
//      with two inline action buttons (ACCEPT / REJECT) that work without
//      opening the app (Android notification shade & iOS notification center).
//
//      Android: Uses AndroidNotificationAction with REPLY-style buttons.
//      iOS:     Uses DarwinNotificationActionOption + DarwinNotificationCategory.
//
//   3. Background Action Handler —
//      The static top-level function [notificationActionHandler] is registered
//      as the FlutterLocalNotifications background callback.  It performs the
//      Firestore wallet update atomically and writes the result back so the UI
//      (if open) is updated via Firestore streams.
//
//   4. Supporting Notifications — Approval / Rejection / Completed signals.
//
// Notification Channel Architecture (Android):
//   safepay_payment_req  — Payment request with ACCEPT/REJECT actions (high)
//   safepay_general      — Info / status notifications (default)
// =============================================================================

import 'dart:convert';
import 'dart:ui' show Color;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'fraud_risk_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND ISOLATE ENTRY-POINT
// Must be a top-level function (NOT inside a class) so the plugin can invoke
// it from a separate Dart isolate when the app is not in the foreground.
// ─────────────────────────────────────────────────────────────────────────────

/// Called by FLN background callback when the user taps an action button
/// (ACCEPT or REJECT) from the notification shade while the app is *closed* or
/// in the background.
///
/// This function runs in a separate Dart isolate — do NOT call Flutter widgets
/// or context-dependent code here.  Firebase works fine because it is
/// initialized with [BackgroundIsolateSpawnToken].
@pragma('vm:entry-point')
void notificationActionHandler(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null) return;

  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final transactionId = data['transactionId'] as String?;
  final receiverId = data['receiverId'] as String?;
  final senderId = data['senderId'] as String?;
  final amount = (data['amount'] as num?)?.toDouble();

  if (transactionId == null || receiverId == null || amount == null) return;

  if (response.actionId == NotificationService.kAcceptActionId) {
    await _bgHandleAccept(
      transactionId: transactionId,
      receiverId: receiverId,
      senderId: senderId ?? '',
      amount: amount,
    );
  } else if (response.actionId == NotificationService.kRejectActionId) {
    await _bgHandleReject(
      transactionId: transactionId,
      receiverId: receiverId,
      senderId: senderId ?? '',
      amount: amount,
    );
  }
}

/// Background helper — approve transaction atomically.
Future<void> _bgHandleAccept({
  required String transactionId,
  required String receiverId,
  required String senderId,
  required double amount,
}) async {
  try {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final callable = functions.httpsCallable('approveEscrowPayment');
    await callable.call({'transactionId': transactionId});

    debugPrint('[BG] Transaction $transactionId approved via notification');
  } catch (e) {
    debugPrint('[BG] Accept error: $e');
  }
}

/// Background helper — reject transaction atomically.
Future<void> _bgHandleReject({
  required String transactionId,
  required String receiverId,
  required String senderId,
  required double amount,
}) async {
  try {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final callable = functions.httpsCallable('rejectEscrowPayment');
    await callable.call({
      'transactionId': transactionId,
      'reason': 'Rejected from notification action',
    });

    debugPrint('[BG] Transaction $transactionId rejected via notification');
  } catch (e) {
    debugPrint('[BG] Reject error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN NOTIFICATION SERVICE CLASS
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ── Plugin instances ───────────────────────────────────────────────────────
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Notification action identifiers ─────────────────────────────────────
  /// Notification action IDs — must match AndroidManifest intent-filter values.
  static const String kAcceptActionId = 'ACCEPT_PAYMENT';
  static const String kRejectActionId = 'REJECT_PAYMENT';

  // ── Android notification channel IDs ─────────────────────────────────────
  static const String _channelPaymentReq = 'safepay_payment_req';
  static const String _channelGeneral = 'safepay_general';

  // ── iOS notification category ─────────────────────────────────────────────
  static const String _iosCategoryPaymentReq = 'PAYMENT_REQUEST';

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // 1. Request FCM permissions
    final permission = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[NotificationService] Notification permission: ${permission.authorizationStatus.name}');

    // iOS foreground presentation options for notification payload messages.
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Configure Android notification actions
    // NOTE: AndroidNotificationAction with titleColor is NOT const-compatible.
    const acceptAction = AndroidNotificationAction(
      kAcceptActionId,
      '✅ ACCEPT',
      titleColor: Color(0xFF22C55E),
      showsUserInterface: false,
      cancelNotification: true,
    );

    const rejectAction = AndroidNotificationAction(
      kRejectActionId,
      '❌ REJECT',
      titleColor: Color(0xFFEF4444),
      showsUserInterface: false,
      cancelNotification: true,
    );

    // 3. Configure iOS notification actions & category
    // NOTE: DarwinNotificationAction.plain() is NOT a const factory.
    final iosAcceptAction = DarwinNotificationAction.plain(
      kAcceptActionId,
      'Accept',
      options: {DarwinNotificationActionOption.foreground},
    );

    final iosRejectAction = DarwinNotificationAction.plain(
      kRejectActionId,
      'Reject',
      options: {DarwinNotificationActionOption.destructive},
    );

    final iosPaymentReqCategory = DarwinNotificationCategory(
      _iosCategoryPaymentReq,
      actions: [iosAcceptAction, iosRejectAction],
    );

    // 4. Initialize flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      notificationCategories: [iosPaymentReqCategory],
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(
      initSettings,
      // Foreground tap handler (app is open)
      onDidReceiveNotificationResponse: _onNotificationTapped,
      // Background action handler (app is closed/background)
      onDidReceiveBackgroundNotificationResponse: notificationActionHandler,
    );

    // 5. Create Android notification channels
    await _createAndroidChannels(
      acceptAction: acceptAction,
      rejectAction: rejectAction,
    );

    // 6. FCM foreground message handler (show local notification instead)
    FirebaseMessaging.onMessage.listen(_handleForegroundFcm);

    // 7. FCM background / terminated tap handler
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

    // Keep backend token fresh after refresh events.
    _fcm.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || token.isEmpty) return;
      debugPrint('[NotificationService] FCM token refreshed for uid=$uid');
      await _persistToken(uid: uid, token: token, reason: 'refresh');
    });

    // 8. Check if app was launched from a terminated-state notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleFcmTap(initial);
    }

    debugPrint('[NotificationService] Initialized');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANDROID CHANNEL SETUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _createAndroidChannels({
    required AndroidNotificationAction acceptAction,
    required AndroidNotificationAction rejectAction,
  }) async {
    final androidPlugin = _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    // High-priority channel for payment requests (with action buttons)
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelPaymentReq,
        'Payment Requests',
        description: 'Accept or reject incoming payment requests',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        // Note: enableLights + ledColor require ledOnMs+ledOffMs on pre-Oreo.
        // Omitted here to avoid PlatformException on older devices.
      ),
    );

    // General info channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelGeneral,
        'SafePay Notifications',
        description: 'SafePay status and info notifications',
        importance: Importance.high,
        playSound: true,
      ),
    );

    debugPrint('[NotificationService] Android channels ensured');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOKEN MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Save the FCM token into the user's Firestore document so the backend
  /// (Cloud Function or other device) can send targeted push messages.
  Future<void> saveFcmToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[NotificationService] FCM token generated for $userId');
        await _persistToken(uid: userId, token: token, reason: 'login_or_app_start');
      }
    } catch (e) {
      debugPrint('[NotificationService] Error saving FCM token: $e');
    }
  }

  /// Removes the current token from user doc on logout to avoid stale token sends.
  Future<void> clearFcmToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      await _db.collection('users').doc(userId).set({
        if (token != null) 'fcmTokens': FieldValue.arrayRemove([token]),
        'fcmToken': FieldValue.delete(),
        'deviceToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
      debugPrint('[NotificationService] Cleared FCM token for $userId');
    } catch (e) {
      debugPrint('[NotificationService] Error clearing FCM token: $e');
    }
  }

  Future<void> _persistToken({
    required String uid,
    required String token,
    required String reason,
  }) async {
    await _db.collection('users').doc(uid).set({
      'fcmToken': token,
      'deviceToken': token,
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokenUpdatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));

    debugPrint('[NotificationService] FCM token upserted for $uid ($reason)');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOREGROUND FCM HANDLER
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleForegroundFcm(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'] as String?;
    debugPrint('[NotificationService] Foreground message received type=$type data=${message.data}');

    if (type == 'payment_request') {
      // Show actionable local notification
      await showPaymentRequestNotification(
        transactionId: data['transactionId'] ?? '',
        senderName: data['senderName'] ?? 'Someone',
        amount: double.tryParse(data['amount'] ?? '0') ?? 0,
        senderId: data['senderId'] ?? '',
        receiverId: data['receiverId'] ?? '',
        riskLevel: data['riskLevel'] ?? 'Low Risk',
        riskEmoji: data['riskEmoji'] ?? '🟢',
      );
    } else {
      // Generic notification
      await _showGeneralNotification(
        title: message.notification?.title ?? 'SafePay',
        body: message.notification?.body ?? '',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FCM TAP HANDLER (background/terminated)
  // ─────────────────────────────────────────────────────────────────────────

  void _handleFcmTap(RemoteMessage message) {
    debugPrint('[NotificationService] FCM tap: ${message.data}');
    // Deep-linking is handled by go_router after this fires.
    // The notification stores transactionId — the router can use it.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOREGROUND TAP HANDLER (user tapped notification body, not action)
  // ─────────────────────────────────────────────────────────────────────────

  void _onNotificationTapped(NotificationResponse response) {
    // Action buttons are handled by notificationActionHandler (top-level fn).
    // This callback fires only when the notification *body* is tapped.
    if (response.actionId == null && response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        final txId = data['transactionId'] as String?;
        debugPrint('[NotificationService] Notification body tapped, txId=$txId');
        // Navigation handled by go_router deep link (payment-approval/:id)
      } catch (_) {}
    } else if (response.actionId != null) {
      // Foreground action — delegate to the same handler used for background.
      notificationActionHandler(response);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: SHOW ACTIONABLE PAYMENT REQUEST NOTIFICATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Shows the rich, actionable payment-request notification with ACCEPT/REJECT
  /// buttons.  Called both from foreground FCM handler and from the
  /// TransactionService when in "foreground-only" prototype mode.
  Future<void> showPaymentRequestNotification({
    required String transactionId,
    required String senderName,
    required double amount,
    required String senderId,
    required String receiverId,
    String riskLevel = 'Low Risk',
    String riskEmoji = '🟢',
  }) async {
    final payload = jsonEncode({
      'transactionId': transactionId,
      'senderId': senderId,
      'receiverId': receiverId,
      'amount': amount,
      'type': 'payment_request',
    });

    final amountStr = '₹${amount.toStringAsFixed(0)}';
    final body = '$senderName wants to send you $amountStr\n'
        'Risk Level: $riskEmoji $riskLevel';

    // ── Android ───────────────────────────────────────────────────────────
    final androidDetails = AndroidNotificationDetails(
      _channelPaymentReq,
      'Payment Requests',
      channelDescription: 'Accept or reject incoming payment requests',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'New payment request from $senderName',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: '💸 SafePay Payment Request',
        summaryText: 'Tap to review',
        htmlFormatBigText: false,
        htmlFormatContentTitle: false,
      ),
      // Inline action buttons
      // NOTE: Cannot use const list — AndroidNotificationAction with Color is not const.
      actions: [
        const AndroidNotificationAction(
          kAcceptActionId,
          '✅ ACCEPT',
          titleColor: Color(0xFF22C55E),
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          kRejectActionId,
          '❌ REJECT',
          titleColor: Color(0xFFEF4444),
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
      // Note: color/ledColor/enableLights omitted — pre-Oreo devices require
      // ledOnMs+ledOffMs alongside ledColor, causing PlatformException otherwise.
      enableVibration: true,
      playSound: true,
      ongoing: false,
      autoCancel: true,
    );

    // ── iOS ───────────────────────────────────────────────────────────────
    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: _iosCategoryPaymentReq,
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use transactionId's hashCode as notification ID so duplicate FCM
    // deliveries don't show duplicate notifications.
    final notifId = transactionId.hashCode.abs() % 100000;

    await _fln.show(
      notifId,
      '💸 SafePay Payment Request',
      body,
      details,
      payload: payload,
    );

    debugPrint('[NotificationService] Local notification shown (payment_request) tx=$transactionId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERAL NOTIFICATION (non-actionable)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showGeneralNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelGeneral,
      'SafePay Notifications',
      channelDescription: 'SafePay status and info notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    await _fln.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );

    debugPrint('[NotificationService] Local notification shown (general) title=$title');
  }

  Future<void> showBackgroundFallbackNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showGeneralNotification(
      title: title,
      body: body,
      payload: payload,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STORED (FIRESTORE) NOTIFICATIONS — for in-app notification centre
  // ─────────────────────────────────────────────────────────────────────────

  /// Store a payment-request notification in Firestore and optionally trigger
  /// an FCM push to the receiver.
  ///
  /// **Notification preference gate:** If the receiver has set
  /// `notificationsEnabled = false` in their Firestore user document, we still
  /// persist the in-app notification (they can view it inside the app) but we
  /// do **NOT** trigger an FCM push or local notification.
  ///
  /// The local [showPaymentRequestNotification] is intentionally NOT called here.
  /// Reason: this method runs on the SENDER's device.  Showing a local
  /// notification here would display "Accept/Reject" to the sender, not the
  /// receiver.
  ///
  /// In production, the SafePay Express backend listens for new 'pending'
  /// transactions and sends an FCM *data* message to [receiverFcmToken].
  /// The receiver's device then handles it via [_firebaseMessagingBackgroundHandler]
  /// (terminated/background) or [_handleForegroundFcm] (foreground), both of
  /// which call [showPaymentRequestNotification] on the RECEIVER's device.
  ///
  /// For local testing without backend push setup: the receiver can also see
  /// incoming requests inside the app via the Notifications screen, which
  /// streams this Firestore document in real-time.
  Future<void> sendPaymentRequestNotification({
    required String receiverId,
    required String receiverFcmToken,
    required String senderName,
    required String senderId,
    required double amount,
    required String transactionId,
    required RiskAssessment risk,
  }) async {
    final riskLabel = risk.levelLabel;
    final riskEmoji = risk.levelEmoji;

    // ── Check receiver's notification preference ─────────────────────────────
    final receiverNotificationsEnabled = await getNotificationPreference(receiverId);

    // Always persist to Firestore so the in-app notification centre shows it.
    await _storeNotification(
      userId: receiverId,
      title: '💸 Payment Request',
      body: '$senderName wants to send you ₹${amount.toStringAsFixed(0)} | '
          '$riskEmoji $riskLabel',
      type: 'payment_request',
      data: {
        'transactionId': transactionId,
        'senderId': senderId,
        'amount': amount.toString(),
        'riskLevel': riskLabel,
        'riskScore': risk.score,
        'riskFlags': risk.flags,
      },
    );

    // ── FCM (production path) ────────────────────────────────────────────────
    // If the receiver has disabled notifications, skip FCM entirely.
    if (!receiverNotificationsEnabled) {
      debugPrint('[NotificationService] Receiver $receiverId has notifications '
          'disabled — skipping FCM push.');
      return;
    }

    // ── Backend FCM API Call ─────────────────────────────────────────────────
    debugPrint('[NotificationService] Requesting backend to send FCM to $receiverId');
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        await ApiService().post(
          '/notifications/send-payment-request',
          {
            'transactionId': transactionId,
            'receiverId': receiverId,
            'senderId': senderId,
            'senderName': senderName,
            'amount': amount,
            'riskLevel': riskLabel,
            'riskEmoji': riskEmoji,
          },
          bearerToken: token,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Backend notification fallback failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NOTIFICATION PREFERENCE MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Check whether a user has notifications enabled.
  /// Returns `true` by default if the field doesn't exist yet.
  Future<bool> getNotificationPreference(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return true;
      return (doc.data()?['notificationsEnabled'] as bool?) ?? true;
    } catch (e) {
      debugPrint('[NotificationService] Error reading notification pref: $e');
      return true; // Safe default
    }
  }

  /// Update the user's notification preference in Firestore.
  Future<void> updateNotificationPreference({
    required String userId,
    required bool enabled,
  }) async {
    try {
      await _db.collection('users').doc(userId).update({
        'notificationsEnabled': enabled,
      });
      debugPrint('[NotificationService] Notification pref for $userId → $enabled');
    } catch (e) {
      debugPrint('[NotificationService] Error updating notification pref: $e');
      rethrow;
    }
  }

  /// Stream the user's notification preference for real-time UI updates.
  Stream<bool> watchNotificationPreference(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return true;
      return (doc.data()?['notificationsEnabled'] as bool?) ?? true;
    });
  }

  Future<void> sendApprovalNotification({
    required String senderId,
    required String receiverName,
    required double amount,
    required String transactionId,
  }) async {
    const title = 'Payment Approved! 🎉';
    final body =
        '$receiverName accepted your ₹${amount.toStringAsFixed(0)} request. Enter your UPI PIN to complete.';

    // Store in Firestore — the SENDER's device will pick this up via the
    // in-app notification stream.  Do NOT call _showGeneralNotification here
    // because this code runs on the RECEIVER's device (who just approved),
    // not the sender's device.
    await _storeNotification(
      userId: senderId,
      title: title,
      body: body,
      type: 'payment_approved',
      data: {'transactionId': transactionId},
    );

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        await ApiService().post(
          '/notifications/send-status-update',
          {
            'transactionId': transactionId,
            'userId': senderId,
            'title': title,
            'body': body,
            'type': 'payment_approved',
          },
          bearerToken: token,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Failed to send push: $e');
    }
  }

  Future<void> sendRejectionNotification({
    required String senderId,
    required String receiverName,
    required double amount,
    required String transactionId,
  }) async {
    const title = 'Payment Rejected';
    final body =
        '$receiverName rejected your ₹${amount.toStringAsFixed(0)} payment. Amount refunded.';

    // Store in Firestore — the SENDER's device will pick this up via the
    // in-app notification stream.  Do NOT call _showGeneralNotification here
    // because this code runs on the RECEIVER's device (who just rejected),
    // not the sender's device.
    await _storeNotification(
      userId: senderId,
      title: title,
      body: body,
      type: 'payment_rejected',
      data: {'transactionId': transactionId},
    );

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        await ApiService().post(
          '/notifications/send-status-update',
          {
            'transactionId': transactionId,
            'userId': senderId,
            'title': title,
            'body': body,
            'type': 'payment_rejected',
          },
          bearerToken: token,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Failed to send push: $e');
    }
  }

  Future<void> sendPaymentCompletedNotification({
    required String receiverId,
    required String senderName,
    required double amount,
    required String transactionId,
  }) async {
    const title = 'Money Received! 💰';
    final body =
        'You received ₹${amount.toStringAsFixed(0)} from $senderName';

    // Store in Firestore — the RECEIVER's device will pick this up via the
    // in-app notification stream.  Do NOT call _showGeneralNotification here
    // because this code runs on the SENDER's device (who just entered the PIN),
    // not the receiver's device.
    await _storeNotification(
      userId: receiverId,
      title: title,
      body: body,
      type: 'payment_completed',
      data: {'transactionId': transactionId},
    );

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        await ApiService().post(
          '/notifications/send-status-update',
          {
            'transactionId': transactionId,
            'userId': receiverId,
            'title': title,
            'body': body,
            'type': 'payment_completed',
          },
          bearerToken: token,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Failed to send push: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: FIRESTORE WRITE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _storeNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _db.collection('notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('[NotificationService] Error storing notification: $e');
    }
  }
}
