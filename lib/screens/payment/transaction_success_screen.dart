import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../services/transaction_service.dart';
import '../../widgets/common_widgets.dart';

class TransactionSuccessScreen extends StatefulWidget {
  final String transactionId;
  const TransactionSuccessScreen({super.key, required this.transactionId});

  @override
  State<TransactionSuccessScreen> createState() =>
      _TransactionSuccessScreenState();
}

class _TransactionSuccessScreenState extends State<TransactionSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..forward();

    // Haptic feedback on success
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: StreamBuilder<TransactionModel?>(
        stream: context
            .read<TransactionService>()
            .watchTransaction(widget.transactionId),
        builder: (context, snapshot) {
          final tx = snapshot.data;
          if (tx == null) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primaryColor, strokeWidth: 2),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Success icon — premium double-ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.successColor.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Inner circle
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.successColor.withValues(alpha: 0.20),
                              blurRadius: 24,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 48),
                      ),
                    ],
                  )
                      .animate()
                      .scale(
                          duration: 600.ms,
                          curve: Curves.elasticOut)
                      .fadeIn(),
                  const SizedBox(height: 28),
                  Text(
                    tx.type == TransactionType.topUp
                        ? 'Wallet Topped Up!'
                        : 'Payment Successful!',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 6),
                  Text(
                    'Transaction completed successfully',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 36),
                  // Amount
                  Text(
                    Formatters.formatCurrency(tx.amount),
                    style: GoogleFonts.inter(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.successColor,
                      letterSpacing: -1.5,
                    ),
                  ).animate().fadeIn(delay: 500.ms).scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1.0, 1.0),
                        duration: 400.ms,
                      ),
                  const SizedBox(height: 32),
                  // Transaction details card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(
                          color: AppTheme.successColor.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      children: [
                        _DetailRow(
                          icon: Icons.person_outline_rounded,
                          label: 'To',
                          value: tx.receiverName,
                        ),
                        const Divider(
                            color: AppTheme.darkDivider, height: 24),
                        _DetailRow(
                          icon: Icons.alternate_email_rounded,
                          label: 'UPI ID',
                          value: Formatters.maskUpiId(tx.receiverUpiId),
                        ),
                        const Divider(
                            color: AppTheme.darkDivider, height: 24),
                        _DetailRow(
                          icon: Icons.access_time_rounded,
                          label: 'Time',
                          value: Formatters.formatDate(
                              tx.completedAt ?? tx.createdAt),
                        ),
                        const Divider(
                            color: AppTheme.darkDivider, height: 24),
                        _DetailRow(
                          icon: Icons.tag_rounded,
                          label: 'Ref',
                          value:
                              '#${tx.transactionId.substring(0, 8).toUpperCase()}',
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 600.ms).slideY(
                        begin: 0.1,
                        duration: 300.ms,
                        curve: Curves.easeOut,
                      ),
                  const Spacer(),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Share',
                          icon: Icons.share_outlined,
                          onPressed: () async {
                            final summary =
                                'SafePay Transaction\n'
                                'To: ${tx.receiverName}\n'
                                'Amount: ${Formatters.formatCurrency(tx.amount)}\n'
                                'Ref: #${tx.transactionId.substring(0, 8).toUpperCase()}\n'
                                'Time: ${Formatters.formatDate(tx.completedAt ?? tx.createdAt)}';
                            await Clipboard.setData(ClipboardData(text: summary));
                            if (!context.mounted) return;
                            AppSnackBar.showSuccess(
                              context,
                              'Transaction summary copied to clipboard.',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(
                          label: 'Back to Home',
                          icon: Icons.home_rounded,
                          onPressed: () => context.go('/home'),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 14),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 13,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
