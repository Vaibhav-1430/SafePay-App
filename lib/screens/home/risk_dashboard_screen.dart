import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_theme.dart';

class RiskDashboardScreen extends StatefulWidget {
  const RiskDashboardScreen({super.key});

  @override
  State<RiskDashboardScreen> createState() => _RiskDashboardScreenState();
}

class _RiskDashboardScreenState extends State<RiskDashboardScreen> {
  bool _loading = true;
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _logs = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final txService = context.read<TransactionService>();
    final stats = await txService.fetchSecurityDashboard(uid);
    final logs = await txService.fetchAuditLogs(uid, limit: 30);

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _logs = logs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Risk Dashboard'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.primaryColor,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  _SummaryGrid(stats: _stats),
                  const SizedBox(height: 18),
                  _RiskSplitBar(stats: _stats),
                  const SizedBox(height: 24),
                  Text(
                    'BLOCKCHAIN-STYLE AUDIT LOG',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_logs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppTheme.darkDivider),
                      ),
                      child: Text(
                        'No audit events yet.',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary),
                      ),
                    ),
                  ..._logs.map((log) => _AuditBlock(log: log)),
                ],
              ),
            ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _SummaryGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = (stats['totalTransactions'] as num?)?.toInt() ?? 0;
    final prevented = (stats['preventedFraudCount'] as num?)?.toInt() ?? 0;
    final highRisk = (stats['highRiskTransactions'] as num?)?.toInt() ?? 0;
    final highRiskVolume = (stats['highRiskVolume'] as num?)?.toDouble() ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: [
        _MetricTile(
          title: 'Total Txns',
          value: '$total',
          color: AppTheme.primaryColor,
          icon: Icons.receipt_long_rounded,
        ),
        _MetricTile(
          title: 'Fraud Prevented',
          value: '$prevented',
          color: AppTheme.secondaryColor,
          icon: Icons.gpp_good_rounded,
        ),
        _MetricTile(
          title: 'High Risk Txns',
          value: '$highRisk',
          color: AppTheme.errorColor,
          icon: Icons.warning_amber_rounded,
        ),
        _MetricTile(
          title: 'High Risk Volume',
          value: Formatters.formatCurrency(highRiskVolume),
          color: AppTheme.accentOrange,
          icon: Icons.account_balance_wallet_rounded,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskSplitBar extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _RiskSplitBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final safe = (stats['safeTransactions'] as num?)?.toDouble() ?? 0;
    final medium = (stats['mediumRiskTransactions'] as num?)?.toDouble() ?? 0;
    final high = (stats['highRiskTransactions'] as num?)?.toDouble() ?? 0;
    final total = (safe + medium + high).clamp(1, 9999999);

    final safeFraction = safe / total;
    final mediumFraction = medium / total;
    final highFraction = high / total;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Risk Distribution (30 Days)',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: (safeFraction * 1000).round().clamp(1, 1000),
                child: Container(height: 9, color: AppTheme.secondaryColor),
              ),
              Expanded(
                flex: (mediumFraction * 1000).round().clamp(1, 1000),
                child: Container(height: 9, color: AppTheme.accentOrange),
              ),
              Expanded(
                flex: (highFraction * 1000).round().clamp(1, 1000),
                child: Container(height: 9, color: AppTheme.errorColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Safe: ${safe.toInt()}  Medium: ${medium.toInt()}  High: ${high.toInt()}',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditBlock extends StatelessWidget {
  final Map<String, dynamic> log;

  const _AuditBlock({required this.log});

  @override
  Widget build(BuildContext context) {
    final event = (log['eventType'] ?? 'EVENT').toString();
    final amount = (log['amount'] as num?)?.toDouble() ?? 0;
    final status = (log['status'] ?? 'unknown').toString();
    final blockIndex = (log['blockIndex'] ?? '-').toString();
    final hash = (log['hash'] ?? '').toString();
    final previousHash = (log['previousHash'] ?? '').toString();
    final createdAtRaw = (log['createdAt'] ?? '').toString();
    final createdAt = DateTime.tryParse(createdAtRaw);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$blockIndex',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                event,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                status.toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.formatCurrency(amount),
            style: GoogleFonts.inter(
              color: AppTheme.secondaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Prev: ${_shortHash(previousHash)}',
            style: GoogleFonts.robotoMono(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
          Text(
            'Hash: ${_shortHash(hash)}',
            style: GoogleFonts.robotoMono(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          if (createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                Formatters.formatDate(createdAt),
                style: GoogleFonts.inter(
                  color: AppTheme.textDisabled,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _shortHash(String hash) {
    if (hash.isEmpty) return '-';
    if (hash.length < 16) return hash;
    return '${hash.substring(0, 8)}...${hash.substring(hash.length - 8)}';
    }
}
