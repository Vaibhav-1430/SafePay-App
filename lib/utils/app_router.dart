import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/auth/set_pin_screen.dart';
import '../screens/auth/app_lock_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/payment/send_money_screen.dart';
import '../screens/payment/waiting_screen.dart';
import '../screens/payment/payment_approval_screen.dart';
import '../screens/payment/pin_entry_screen.dart';
import '../screens/payment/transaction_success_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import '../screens/wallet/top_up_screen.dart';
import '../screens/wallet/transaction_history_screen.dart';
import '../screens/wallet/transaction_detail_screen.dart';
import '../screens/merchant/merchant_settings_screen.dart';
import '../screens/home/qr_scanner_screen.dart';
import '../screens/home/qr_display_screen.dart';
import '../screens/home/notifications_screen.dart';
import '../screens/home/contacts_screen.dart';
import '../screens/home/profile_screen.dart';
import '../screens/home/ai_assistant_screen.dart';
import '../screens/home/risk_dashboard_screen.dart';
import '../screens/settings/notification_settings_screen.dart';
import '../screens/settings/edit_profile_screen.dart';
import '../services/auth_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      const publicAuthRoutes = {
        '/auth/login',
        '/auth/register',
        '/auth/otp',
        '/auth/role-selection',
      };

      final isAuthenticated = authService.isAuthenticated;
      final path = state.matchedLocation;
      final isSplash = path == '/splash';
      final isPublicAuthRoute = publicAuthRoutes.contains(path);
      final isAppLockRoute = path == '/auth/app-lock';
      final isSetPinRoute = path == '/auth/set-pin';

      if (!authService.isSessionReady) {
        return isSplash ? null : '/splash';
      }

      if (isSplash) {
        if (!isAuthenticated) {
          return '/auth/login';
        }
        return authService.isAppUnlocked ? '/home' : '/auth/app-lock';
      }

      if (!isAuthenticated && !isPublicAuthRoute && !isSplash) {
        return '/auth/login';
      }

      if (isAuthenticated && !authService.isAppUnlocked && !isAppLockRoute && !isSetPinRoute) {
        return '/auth/app-lock';
      }

      if (isAuthenticated && authService.isAppUnlocked && (isPublicAuthRoute || isSplash)) {
        return '/home';
      }

      return null;
    },
    refreshListenable: authService,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, state) {
          final role = state.uri.queryParameters['role'] ?? 'personal';
          return RegisterScreen(role: role);
        },
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (_, __) => const OtpScreen(),
      ),
      GoRoute(
        path: '/auth/role-selection',
        builder: (_, __) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/auth/set-pin',
        builder: (_, __) => const SetPinScreen(),
      ),
      GoRoute(
        path: '/auth/app-lock',
        builder: (_, __) => const AppLockScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/send-money',
        builder: (_, state) {
          final upiId = state.uri.queryParameters['upiId'];
          return SendMoneyScreen(prefilledUpiId: upiId);
        },
      ),
      GoRoute(
        path: '/payment-request',
        builder: (_, state) {
          final upiId = state.uri.queryParameters['upiId'];
          return SendMoneyScreen(prefilledUpiId: upiId);
        },
      ),
      GoRoute(
        path: '/waiting/:transactionId',
        builder: (_, state) => WaitingScreen(
          transactionId: state.pathParameters['transactionId']!,
        ),
      ),
      GoRoute(
        path: '/payment-approval/:transactionId',
        builder: (_, state) => PaymentApprovalScreen(
          transactionId: state.pathParameters['transactionId']!,
        ),
      ),
      GoRoute(
        path: '/pin-entry/:transactionId',
        builder: (_, state) => PinEntryScreen(
          transactionId: state.pathParameters['transactionId']!,
        ),
      ),
      GoRoute(
        path: '/success/:transactionId',
        builder: (_, state) => TransactionSuccessScreen(
          transactionId: state.pathParameters['transactionId']!,
        ),
      ),
      GoRoute(
        path: '/wallet',
        builder: (_, __) => const WalletScreen(),
      ),
      GoRoute(
        path: '/top-up',
        builder: (_, __) => const TopUpScreen(),
      ),
      GoRoute(
        path: '/transactions',
        builder: (_, __) => const TransactionHistoryScreen(),
      ),
      GoRoute(
        path: '/transaction/:transactionId',
        builder: (_, state) => TransactionDetailScreen(
          transactionId: state.pathParameters['transactionId']!,
        ),
      ),
      GoRoute(
        path: '/merchant-settings',
        builder: (_, __) => const MerchantSettingsScreen(),
      ),
      GoRoute(
        path: '/qr-scanner',
        builder: (_, __) => const QrScannerScreen(),
      ),
      GoRoute(
        path: '/qr-display',
        builder: (_, __) => const QrDisplayScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/contacts',
        builder: (_, __) => const ContactsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/ai-assistant',
        builder: (_, __) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: '/risk-dashboard',
        builder: (_, __) => const RiskDashboardScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (_, __) => const EditProfileScreen(),
      ),
    ],
  );
}
