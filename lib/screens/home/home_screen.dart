import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/wallet_service.dart';
import '../../services/transaction_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/trust_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _balanceVisible = true;
  bool _pinPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      if (auth.currentUser != null) {
        NotificationService().saveFcmToken(auth.currentUser!.uid);
      }
      _ensureUpiPinOnboarding();
    });
  }

  Future<void> _ensureUpiPinOnboarding() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (!mounted || user == null || user.hasUpiPin || _pinPromptShown) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;

    _pinPromptShown = true;
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    var selectedLength = user.upiPinLength ?? 4;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateModal) {
            return AlertDialog(
              backgroundColor: AppTheme.darkCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              title: Text(
                user.isMerchant ? 'Set Merchant Payment PIN' : 'Create UPI PIN',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your PIN is required to authorize payments securely.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [4, 6].map((len) {
                      return ChoiceChip(
                        label: Text('$len-digit'),
                        selected: selectedLength == len,
                        onSelected: isSaving
                            ? null
                            : (_) => setStateModal(() => selectedLength = len),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: pinController,
                    label: 'Enter PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: confirmController,
                    label: 'Confirm PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  const EncryptionLabel(),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!mounted || !ctx.mounted) return;
                          final pin = pinController.text.trim();
                          final confirm = confirmController.text.trim();

                          if (!RegExp(r'^\d+$').hasMatch(pin) || pin.length != selectedLength) {
                            if (mounted) {
                              AppSnackBar.showError(
                                context,
                                'PIN must be exactly $selectedLength digits.',
                              );
                            }
                            return;
                          }
                          if (pin != confirm) {
                            if (mounted) {
                              AppSnackBar.showError(
                                context,
                                'PIN confirmation does not match.',
                              );
                            }
                            return;
                          }

                          setStateModal(() => isSaving = true);
                          final result = await auth.setUpiPin(pin);
                          if (!mounted || !ctx.mounted) return;

                          setStateModal(() => isSaving = false);
                          if (!result.success) {
                            AppSnackBar.showError(context, result.message);
                            return;
                          }

                          AppSnackBar.showSuccess(context, result.message);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save PIN'),
                ),
              ],
            );
          },
        );
      },
    );

    pinController.dispose();
    confirmController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBg,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(context, auth),
              _buildBalanceCard(context, user.uid),
              _buildQuickActions(context),
              _buildPendingRequests(context, user.uid),
              _buildRecentTransactions(context, user.uid),
              _buildServicesSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HEADER — Clean, with security badge
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, AuthService auth) {
    final user = auth.currentUser!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Avatar
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: user.isMerchant
                    ? AppTheme.secondaryColor
                    : AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: ClipOval(
                  child: _HomeAvatar(
                    imageUrl: user.profileImageUrl,
                    displayName: user.displayName,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Greeting + Security badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Hello, ',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        user.displayName.split(' ').first,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                user.isMerchant
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.store_rounded,
                              size: 12, color: AppTheme.secondaryColor),
                          const SizedBox(width: 4),
                          Text(
                            'Merchant Account',
                            style: GoogleFonts.inter(
                              color: AppTheme.secondaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const SecurityBadge(),
              ],
            ),
          ),
          // Notification bell
          GestureDetector(
            onTap: () => context.push('/notifications'),
            child: _NotificationBell(userId: user.uid),
          ),
          const SizedBox(width: 8),
          // QR code
          GestureDetector(
            onTap: () => context.push('/qr-display'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppTheme.darkDivider),
              ),
              child: const Icon(Icons.qr_code_2_rounded,
                  color: AppTheme.textPrimary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // BALANCE CARD — Clean, no gradient glow
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildBalanceCard(BuildContext context, String userId) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: StreamBuilder(
        stream: context.read<WalletService>().watchWallet(userId),
        builder: (context, snapshot) {
          final balance = snapshot.data?.balance ?? 0.0;
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Wallet Balance',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _balanceVisible = !_balanceVisible),
                      child: Icon(
                        _balanceVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _balanceVisible
                      ? Formatters.formatCurrency(balance)
                      : '₹ ••••••',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                  ),
                ).animate(key: ValueKey(balance)).fadeIn(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _BalanceAction(
                        icon: Icons.add_rounded,
                        label: 'Add Money',
                        onTap: () => context.push('/top-up'),
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BalanceAction(
                        icon: Icons.send_rounded,
                        label: 'Send Money',
                        onTap: () => context.push('/send-money'),
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BalanceAction(
                        icon: Icons.receipt_long_rounded,
                        label: 'History',
                        onTap: () => context.push('/transactions'),
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  // ═══════════════════════════════════════════════════════════════════
  // QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildQuickActions(BuildContext context) {
    final isMerchant = context.read<AuthService>().currentUser?.isMerchant ?? false;

    final actions = [
      _QuickAction(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scan QR',
        color: AppTheme.primaryColor,
        onTap: () => context.push('/qr-scanner'),
      ),
      _QuickAction(
        icon: Icons.send_to_mobile_rounded,
        label: 'Send',
        color: AppTheme.secondaryColor,
        onTap: () => context.push('/send-money'),
      ),
      _QuickAction(
        icon: Icons.people_rounded,
        label: 'Contacts',
        color: AppTheme.accentOrange,
        onTap: () => context.push('/contacts'),
      ),
      _QuickAction(
        icon: Icons.shield_rounded,
        label: 'Risk Desk',
        color: AppTheme.primaryLight,
        onTap: () => context.push('/risk-dashboard'),
      ),
      _QuickAction(
        icon: Icons.auto_awesome_rounded,
        label: 'AI Coach',
        color: AppTheme.accentPink,
        onTap: () => context.push('/ai-assistant'),
      ),
      if (isMerchant)
        _QuickAction(
          icon: Icons.settings_rounded,
          label: 'Settings',
          color: AppTheme.primaryLight,
          onTap: () => context.push('/merchant-settings'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK ACTIONS',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: actions
                .take(4)
                .map((a) => _QuickActionButton(action: a))
                .toList(),
          ),
          if (actions.length > 4) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ...actions.skip(4).map((a) => _QuickActionButton(action: a)),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ═══════════════════════════════════════════════════════════════════
  // PENDING REQUESTS
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildPendingRequests(BuildContext context, String userId) {
    return StreamBuilder<List<TransactionModel>>(
      stream: context
          .read<TransactionService>()
          .watchPendingRequestsForReceiver(userId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.pendingColor,
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (c) => c.repeat())
                    .fadeIn(duration: 800.ms)
                    .then()
                    .fadeOut(duration: 800.ms),
                  const SizedBox(width: 8),
                  Text(
                    'PENDING APPROVALS (${requests.length})',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...requests.map(
                (tx) => _PendingRequestCard(
                  transaction: tx,
                  onApprove: () =>
                      context.push('/payment-approval/${tx.transactionId}'),
                  onReject: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppTheme.darkCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                        ),
                        title: Text('Reject Payment?',
                            style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600)),
                        content: Text(
                          'Reject ₹${tx.amount.toStringAsFixed(0)} from ${tx.senderName}?',
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Reject',
                                style: TextStyle(color: AppTheme.errorColor)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await context
                          .read<TransactionService>()
                          .rejectPayment(tx.transactionId);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // RECENT TRANSACTIONS
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildRecentTransactions(BuildContext context, String userId) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT TRANSACTIONS',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              GestureDetector(
                onTap: () => context.push('/transactions'),
                child: Text(
                  'See All',
                  style: GoogleFonts.inter(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<TransactionModel>>(
            stream: context
                .read<TransactionService>()
                .watchUserTransactions(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              final transactions = snapshot.data ?? [];
              if (transactions.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppTheme.darkDivider),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 44,
                            color: AppTheme.textDisabled),
                        const SizedBox(height: 12),
                        Text(
                          'No transactions yet',
                          style: GoogleFonts.inter(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your payment history will appear here',
                          style: GoogleFonts.inter(
                            color: AppTheme.textDisabled,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppTheme.darkDivider),
                ),
                child: Column(
                  children: transactions
                      .take(5)
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) => Column(
                            children: [
                              TransactionTile(
                                transaction: entry.value,
                                currentUserId: userId,
                                onTap: () => context.push(
                                  '/transaction/${entry.value.transactionId}',
                                ),
                              ),
                              if (entry.key < (transactions.take(5).length - 1))
                                const Divider(
                                  color: AppTheme.darkDivider,
                                  height: 1,
                                  indent: 64,
                                ),
                            ],
                          ))
                      .toList(),
                ),
              );
            },
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  // ═══════════════════════════════════════════════════════════════════
  // SERVICES SECTION
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildServicesSection() {
    final services = [
      _ServiceItem(Icons.phone_android_rounded, 'Mobile\nRecharge', AppTheme.primaryColor),
      _ServiceItem(Icons.receipt_rounded, 'Utility\nBills', AppTheme.secondaryColor),
      _ServiceItem(Icons.card_giftcard_rounded, 'Rewards &\nOffers', AppTheme.accentOrange),
      _ServiceItem(Icons.group_add_rounded, 'Refer &\nEarn', AppTheme.accentPink),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SERVICES',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: services.map((s) => _ServiceItemWidget(item: s)).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  // ═══════════════════════════════════════════════════════════════════
  // BOTTOM NAVIGATION — Clean, no gradient QR button
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildBottomNav(BuildContext context) {
    final auth = context.read<AuthService>();
    final isMerchant = auth.currentUser?.isMerchant ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(top: BorderSide(color: AppTheme.darkDivider)),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          switch (index) {
            case 0:
              break; // Home
            case 1:
              context.push('/wallet');
              break;
            case 2:
              context.push('/qr-scanner');
              break;
            case 3:
              context.push('/contacts');
              break;
            case 4:
              if (isMerchant) {
                context.push('/merchant-settings');
              } else {
                context.push('/profile');
              }
              break;
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white, size: 22),
            ),
            selectedIcon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white, size: 22),
            ),
            label: 'Scan',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(isMerchant
                ? Icons.store_outlined
                : Icons.person_outline_rounded),
            selectedIcon: Icon(isMerchant
                ? Icons.store_rounded
                : Icons.person_rounded),
            label: isMerchant ? 'Merchant' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeAvatar extends StatelessWidget {
  final String? imageUrl;
  final String displayName;

  const _HomeAvatar({
    required this.imageUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    if (hasImage) {
      return Image.network(
        imageUrl!,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Text(
      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
      style: GoogleFonts.inter(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUPPORTING WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _BalanceAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _BalanceAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.darkElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppTheme.darkDivider),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                      color: action.color.withValues(alpha: 0.12)),
                ),
                child: Icon(action.icon, color: action.color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingRequestCard({
    required this.transaction,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.pendingColor.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    transaction.senderName.isNotEmpty
                        ? transaction.senderName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${transaction.senderName} is sending you',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      Formatters.formatCurrency(transaction.amount),
                      style: GoogleFonts.inter(
                        color: AppTheme.secondaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.pendingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'PENDING',
                  style: GoogleFonts.inter(
                    color: AppTheme.pendingColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          if (transaction.note != null && transaction.note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '📝 ${transaction.note}',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: const BorderSide(
                        color: AppTheme.errorColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('Reject',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('View & Accept',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceItem {
  final IconData icon;
  final String label;
  final Color color;

  _ServiceItem(this.icon, this.label, this.color);
}

class _ServiceItemWidget extends StatelessWidget {
  final _ServiceItem item;

  const _ServiceItemWidget({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            AppSnackBar.showInfo(context, '${item.label.replaceAll('\n', ' ')} coming soon!'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTheme.darkDivider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: item.color, size: 26),
              const SizedBox(height: 6),
              Text(
                item.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final String userId;
  const _NotificationBell({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirestoreNotificationCount(userId).stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppTheme.darkDivider),
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: AppTheme.textPrimary, size: 20),
            ),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class FirestoreNotificationCount {
  final String userId;
  FirestoreNotificationCount(this.userId);

  Stream<int> get stream => FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: userId)
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);
}
