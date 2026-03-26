import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/trusted_contact_model.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../widgets/common_widgets.dart';

class MerchantSettingsScreen extends StatefulWidget {
  const MerchantSettingsScreen({super.key});

  @override
  State<MerchantSettingsScreen> createState() =>
      _MerchantSettingsScreenState();
}

class _MerchantSettingsScreenState extends State<MerchantSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _fastMode = true;
  double _approvalThreshold = 2000;
  final _thresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final auth = context.read<AuthService>();
    final contacts = context.read<ContactsService>();
    final settings =
        await contacts.getMerchantSettings(auth.currentUser!.uid);
    if (mounted) {
      setState(() {
        _fastMode = settings?.fastMode ?? true;
        _approvalThreshold = settings?.approvalThreshold ?? 2000;
        _thresholdController.text = _approvalThreshold.toStringAsFixed(0);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final auth = context.read<AuthService>();
    final contacts = context.read<ContactsService>();

    final threshold = double.tryParse(_thresholdController.text) ?? 2000;

    await contacts.updateMerchantSettings(
      MerchantSettings(
        merchantId: auth.currentUser!.uid,
        fastMode: _fastMode,
        approvalThreshold: _fastMode ? null : threshold,
        autoAcceptBelow: !_fastMode,
      ),
    );

    if (mounted) {
      setState(() => _isSaving = false);
      AppSnackBar.showSuccess(context, 'Settings saved!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Merchant Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode selection
                  const Text(
                    'Payment Mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ).animate().fadeIn(),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how you receive payments',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 16),
                  // Fast Mode card
                  _ModeCard(
                    title: '⚡ Fast Mode',
                    description:
                        'Auto-accept all incoming payments instantly. No approval required.',
                    isSelected: _fastMode,
                    color: AppTheme.secondaryColor,
                    onTap: () => setState(() => _fastMode = true),
                    features: const [
                      'Instant payment acceptance',
                      'No manual approvals',
                      'Great for busy merchants',
                    ],
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 12),
                  // Safe Mode card
                  _ModeCard(
                    title: '🔒 Safe Mode',
                    description:
                        'Set a threshold. Large payments require your approval.',
                    isSelected: !_fastMode,
                    color: AppTheme.primaryColor,
                    onTap: () => setState(() => _fastMode = false),
                    features: const [
                      'Auto-accept small payments',
                      'Manual approval for large amounts',
                      'Extra security for big transactions',
                    ],
                  ).animate().fadeIn(delay: 300.ms),
                  if (!_fastMode) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Approval Threshold',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ).animate().fadeIn(delay: 400.ms),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _thresholdController,
                      label: 'Threshold Amount (₹)',
                      hint: '2000',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.currency_rupee_rounded,
                    ).animate().fadeIn(delay: 450.ms),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppTheme.primaryColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Payments below ₹${_thresholdController.text} will be auto-accepted. Payments above require your approval.',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 500.ms),
                  ],
                  const SizedBox(height: 32),
                  PrimaryButton(
                    label: 'Save Settings',
                    onPressed: _saveSettings,
                    isLoading: _isSaving,
                    icon: Icons.save_rounded,
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                  ).animate().fadeIn(delay: 600.ms),
                  const SizedBox(height: 24),
                  // Merchant stats section
                  _buildMerchantStats(),
                ],
              ),
            ),
    );
  }

  Widget _buildMerchantStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Stats',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Mode',
                value: _fastMode ? 'Fast' : 'Safe',
                icon: _fastMode
                    ? Icons.flash_on_rounded
                    : Icons.security_rounded,
                color: _fastMode
                    ? AppTheme.secondaryColor
                    : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Threshold',
                value: _fastMode
                    ? 'N/A'
                    : '₹${_thresholdController.text}',
                icon: Icons.tune_rounded,
                color: AppTheme.accentOrange,
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 700.ms);
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String description;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final List<String> features;

  const _ModeCard({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.color,
    required this.onTap,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppTheme.darkDivider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? color : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? color : AppTheme.darkDivider,
                      width: 2,
                    ),
                    color: isSelected ? color : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.arrow_right_rounded,
                        color: color.withValues(alpha: 0.7), size: 16),
                    const SizedBox(width: 4),
                    Text(f,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
