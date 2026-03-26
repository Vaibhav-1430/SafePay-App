import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _balanceVisible = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: Text('My Wallet',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/transactions'),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: context.read<WalletService>().watchWallet(userId),
        builder: (context, snapshot) {
          final wallet = snapshot.data;
          final balance = wallet?.balance ?? 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Balance card — solid, no gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Available Balance',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(
                                () => _balanceVisible = !_balanceVisible),
                            child: Icon(
                              _balanceVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppTheme.textMuted,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _balanceVisible
                            ? Formatters.formatCurrency(balance, decimal: true)
                            : '₹ ••••••',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.5,
                        ),
                      ).animate(key: ValueKey(balance)).fadeIn(),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.darkDivider.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          auth.currentUser!.upiId,
                          style: GoogleFonts.inter(
                            color: AppTheme.textDisabled,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.1),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  children: [
                    _WalletActionCard(
                      icon: Icons.add_rounded,
                      label: 'Add Money',
                      color: AppTheme.secondaryColor,
                      onTap: () => context.push('/top-up'),
                    ),
                    const SizedBox(width: 12),
                    _WalletActionCard(
                      icon: Icons.send_rounded,
                      label: 'Send Money',
                      color: AppTheme.primaryColor,
                      onTap: () => context.push('/send-money'),
                    ),
                    const SizedBox(width: 12),
                    _WalletActionCard(
                      icon: Icons.qr_code_rounded,
                      label: 'Your QR',
                      color: AppTheme.accentOrange,
                      onTap: () => context.push('/qr-display'),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 24),
                // Stats cards
                const Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.arrow_upward_rounded,
                        label: 'Sent',
                        color: AppTheme.errorColor,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.arrow_downward_rounded,
                        label: 'Received',
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 300.ms),
                const SizedBox(height: 24),
                // Transaction history link
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/transactions'),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Ink(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppTheme.darkDivider),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.10),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                color: AppTheme.primaryColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'View Transaction History',
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: AppTheme.textMuted, size: 14),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WalletActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _WalletActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                'This Month',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
