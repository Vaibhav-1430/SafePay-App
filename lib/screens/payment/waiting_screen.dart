import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trust_badge.dart';

class WaitingScreen extends StatefulWidget {
  final String transactionId;
  const WaitingScreen({super.key, required this.transactionId});

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _remainingSeconds = 300; // 5 minutes
  Timer? _timer;
  bool _isCancelling = false;
  bool _navigationHandled = false;
  bool _terminalDialogShown = false;

  void _navigateOnce(String route) {
    if (_navigationHandled || !mounted) return;
    _navigationHandled = true;
    context.go(route);
  }

  @override
  void initState() {
    super.initState();
    // Slower pulse = calmer feel (2000ms vs 1500ms)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _timeDisplay {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

          // Handle status changes only once to avoid navigation races.
          if (!_navigationHandled) {
            if (tx.status == TransactionStatus.approved) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateOnce('/pin-entry/${widget.transactionId}');
              });
            } else if (tx.status == TransactionStatus.completed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateOnce('/success/${widget.transactionId}');
              });
            } else if (tx.status == TransactionStatus.rejected ||
                tx.status == TransactionStatus.timedOut ||
                tx.status == TransactionStatus.refunded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_terminalDialogShown) {
                  _terminalDialogShown = true;
                  _showRejectedDialog(context, tx);
                }
              });
            }
          }

          if (tx.cancelUntil != null) {
            final remaining = tx.cancelUntil!.difference(DateTime.now()).inSeconds;
            if (remaining >= 0 && remaining != _remainingSeconds) {
              _remainingSeconds = remaining;
            }
          }

          final auth = context.read<AuthService>();
          final uid = auth.currentUser?.uid;
          final canEmergencyCancel =
              uid != null &&
              uid == tx.senderId &&
              (tx.status == TransactionStatus.pending ||
                  tx.status == TransactionStatus.approved) &&
              (tx.cancelUntil == null || DateTime.now().isBefore(tx.cancelUntil!));

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // Top row: close + timer badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppTheme.darkDivider),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: AppTheme.textPrimary, size: 18),
                        ),
                      ),
                      // Timer badge — prominent at top
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: (_remainingSeconds < 60
                                  ? AppTheme.errorColor
                                  : AppTheme.pendingColor)
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: (_remainingSeconds < 60
                                    ? AppTheme.errorColor
                                    : AppTheme.pendingColor)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: _remainingSeconds < 60
                                  ? AppTheme.errorColor
                                  : AppTheme.pendingColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _timeDisplay,
                              style: GoogleFonts.inter(
                                color: _remainingSeconds < 60
                                    ? AppTheme.errorColor
                                    : AppTheme.pendingColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [
                                  const FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Calm pulsing indicator — reduced amplitude, no gradient
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring
                          Container(
                            width: 130 +
                                (_pulseController.value * 15),
                            height: 130 +
                                (_pulseController.value * 15),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor.withValues(alpha: 
                                  0.04 + (_pulseController.value * 0.03)),
                            ),
                          ),
                          // Inner pulse ring
                          Container(
                            width: 105 +
                                (_pulseController.value * 8),
                            height: 105 +
                                (_pulseController.value * 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor.withValues(alpha: 
                                  0.06 + (_pulseController.value * 0.04)),
                            ),
                          ),
                          // Center icon — solid, no gradient
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.15),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Waiting for Approval',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 8),
                  Text(
                    '${tx.receiverName} needs to approve\nyour payment',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 28),

                  // ── Status Timeline ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    child: StatusTimeline(
                      steps: [
                        TimelineStep(
                          label: 'Payment initiated',
                          time: Formatters.formatTime(tx.createdAt),
                          state: TimelineStepState.completed,
                        ),
                        const TimelineStep(
                          label: 'Waiting for approval',
                          time: 'Now',
                          state: TimelineStepState.active,
                        ),
                        const TimelineStep(
                          label: 'Complete payment',
                          time: 'Pending',
                          state: TimelineStepState.pending,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 16),

                  // Transaction details card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    child: Column(
                      children: [
                        _DetailRow(
                          label: 'To',
                          value: tx.receiverName,
                          valueColor: AppTheme.textPrimary,
                        ),
                        const Divider(
                            color: AppTheme.darkDivider, height: 20),
                        _DetailRow(
                          label: 'Amount',
                          value: Formatters.formatCurrency(tx.amount),
                          valueColor: AppTheme.secondaryColor,
                          isBold: true,
                        ),
                        if (tx.note != null &&
                            tx.note!.isNotEmpty) ...[
                          const Divider(
                              color: AppTheme.darkDivider, height: 20),
                          _DetailRow(
                            label: 'Note',
                            value: tx.note!,
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms),
                  const SizedBox(height: 16),

                  // Waiting indicator — pulsing dot instead of spinner
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.pendingColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                          color: AppTheme.pendingColor.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                          'Waiting for response...',
                          style: GoogleFonts.inter(
                            color: AppTheme.pendingColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 600.ms),
                  if (canEmergencyCancel) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isCancelling
                            ? null
                            : () async {
                                final txService = context.read<TransactionService>();
                                setState(() => _isCancelling = true);
                              final result = await txService
                                .emergencyCancelPayment(widget.transactionId);
                                if (!context.mounted) return;
                                setState(() => _isCancelling = false);
                                if (result['success'] == true) {
                                  AppSnackBar.showSuccess(
                                    context,
                                    'Payment cancelled and amount refunded.',
                                  );
                                } else {
                                  AppSnackBar.showError(
                                    context,
                                    (result['error'] as String?) ??
                                        'Unable to cancel now.',
                                  );
                                }
                              },
                        icon: _isCancelling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.gpp_bad_rounded, size: 18),
                        label: const Text('Emergency Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorColor,
                          side: BorderSide(
                            color: AppTheme.errorColor.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRejectedDialog(
      BuildContext context, TransactionModel tx) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppTheme.errorColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              tx.status == TransactionStatus.timedOut
                  ? 'Payment Timed Out'
                : tx.status == TransactionStatus.refunded
                  ? 'Payment Cancelled'
                  : 'Payment Rejected',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${Formatters.formatCurrency(tx.amount)} has been refunded to your wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _navigateOnce('/home');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text('Back to Home',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: valueColor ?? AppTheme.textPrimary,
            fontSize: isBold ? 18 : 14,
            fontWeight:
                isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
