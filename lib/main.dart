import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/wallet_service.dart';
import 'services/transaction_service.dart';
import 'services/contacts_service.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';
import 'utils/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FCM BACKGROUND MESSAGE HANDLER
//
// This top-level function is called by Firebase Messaging when a DATA message
// arrives and the app is in the BACKGROUND or TERMINATED state.
//
// Rules:
//  • Must be a top-level function (not a class method).
//  • Must be annotated with @pragma('vm:entry-point').
//  • Runs in a separate Dart isolate — do NOT use Flutter widgets here.
//  • Firebase is available. Call NotificationService().showPaymentRequestNotification
//    to display the actionable local notification.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be re-initialised in the background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  final type = data['type'] as String?;
  debugPrint('[main] Background handler triggered. type=$type data=${message.data}');

  if (type == 'payment_request') {
    // Show the actionable local notification so the user sees
    // ACCEPT / REJECT buttons in their notification shade.
    await NotificationService().showPaymentRequestNotification(
      transactionId: data['transactionId'] ?? '',
      senderName: data['senderName'] ?? 'Someone',
      amount: double.tryParse(data['amount'] ?? '0') ?? 0,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      riskLevel: data['riskLevel'] ?? 'Low Risk',
      riskEmoji: data['riskEmoji'] ?? '🟢',
    );
    debugPrint('[main] Background local notification shown for tx=${data['transactionId']}');
  } else {
    final title = message.notification?.title ?? (data['title'] as String?) ?? 'SafePay';
    final body = message.notification?.body ?? (data['body'] as String?) ?? 'New update';
    final payload = jsonEncode({
      'transactionId': data['transactionId'] ?? '',
      'type': type ?? 'general',
    });

    await NotificationService().showBackgroundFallbackNotification(
      title: title,
      body: body,
      payload: payload,
    );
    debugPrint('[main] Background fallback notification shown. type=$type');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity,
      );
      debugPrint(
        '[AppCheck] Activated on Android using ${kDebugMode ? 'debug' : 'playIntegrity'} provider.',
      );
    } catch (e) {
      debugPrint('[AppCheck] Activation failed: $e');
    }
  }

  // Register the background FCM message handler BEFORE runApp.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications (permission request, channel creation,
  // action button callbacks, foreground FCM listener, etc.)
  await NotificationService().initialize();

  runApp(const SafePayApp());
}

class SafePayApp extends StatelessWidget {
  const SafePayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => WalletService()),
        ChangeNotifierProvider(create: (_) => TransactionService()),
        ChangeNotifierProvider(create: (_) => ContactsService()),
      ],
      child: const _AppWithRouter(),
    );
  }
}

class _AppWithRouter extends StatefulWidget {
  const _AppWithRouter();

  @override
  State<_AppWithRouter> createState() => _AppWithRouterState();
}

class _AppWithRouterState extends State<_AppWithRouter> {
  late final dynamic _router;

  @override
  void initState() {
    super.initState();
    final authService = context.read<AuthService>();
    _router = createRouter(authService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SafePay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

