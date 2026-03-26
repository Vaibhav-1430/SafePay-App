import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../services/contacts_service.dart';
import '../../services/ai_security_service.dart';
import '../../widgets/common_widgets.dart' hide SectionHeader;
import '../../widgets/trust_badge.dart';
import '../../widgets/send_money/recipient_selection_components.dart';

// Suggestion item combining trusted contacts + recent TX partners
class _Suggestion {
  final String name;
  final String upiId;
  final DateTime? lastTransactionAt;
  final int transferCount;
  final bool isTrusted;
  final bool isRecent;

  _Suggestion({
    required this.name,
    required this.upiId,
    this.lastTransactionAt,
    this.transferCount = 0,
    this.isTrusted = false,
    this.isRecent = false,
  });

  _Suggestion copyWith({
    String? name,
    String? upiId,
    DateTime? lastTransactionAt,
    int? transferCount,
    bool? isTrusted,
    bool? isRecent,
  }) {
    return _Suggestion(
      name: name ?? this.name,
      upiId: upiId ?? this.upiId,
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
      transferCount: transferCount ?? this.transferCount,
      isTrusted: isTrusted ?? this.isTrusted,
      isRecent: isRecent ?? this.isRecent,
    );
  }
}

enum _RecipientUiState { empty, typing, results, noResults }

class SendMoneyScreen extends StatefulWidget {
  final String? prefilledUpiId;

  const SendMoneyScreen({super.key, this.prefilledUpiId});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _upiController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _upiFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();

  UserModel? _receiver;
  bool _isSearching = false;
  bool _isSending = false;
  bool _isTrusted = false;
  bool _isMerchantFastMode = false;
  int _delayMinutes = 0;
  String? _fraudWarning;
  bool _hasPastTransactionsWithReceiver = false;

  // Suggestions
  List<_Suggestion> _allSuggestions = [];
  List<_Suggestion> _recentSuggestions = [];
  List<_Suggestion> _filteredSuggestions = [];
  bool _suggestionsLoaded = false;
  bool _isTyping = false;
  Timer? _searchDebounce;
  final AiSecurityService _aiSecurityService = AiSecurityService();

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _upiController.addListener(_onUpiChanged);

    if (widget.prefilledUpiId != null) {
      _upiController.text = widget.prefilledUpiId!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchUser());
    }
  }

  Future<void> _loadSuggestions() async {
    final auth = context.read<AuthService>();
    final contacts = context.read<ContactsService>();
    final txService = context.read<TransactionService>();
    final userId = auth.currentUser?.uid;
    if (userId == null) return;

    final suggestions = <String, _Suggestion>{};
    final recentMap = <String, _Suggestion>{};

    // 1. Trusted contacts
    final trusted = await contacts.watchTrustedContacts(userId).first;
    for (final c in trusted) {
      suggestions[c.contactUpiId] = _Suggestion(
        name: c.contactName,
        upiId: c.contactUpiId,
        lastTransactionAt: c.addedAt,
        transferCount: 0,
        isTrusted: true,
        isRecent: false,
      );
    }

    // 2. Recent transaction partners from recent history (sent + completed)
    final recentTxs = await txService.getRecentTransactions(userId);
    for (final tx in recentTxs) {
      if (tx.senderId != userId || tx.status.name != 'completed') continue;
      final key = tx.receiverUpiId;

      final existingRecent = recentMap[key];
      recentMap[key] = _Suggestion(
        name: tx.receiverName,
        upiId: key,
        lastTransactionAt: existingRecent == null
            ? tx.createdAt
            : (existingRecent.lastTransactionAt != null &&
                    existingRecent.lastTransactionAt!.isAfter(tx.createdAt)
                ? existingRecent.lastTransactionAt
                : tx.createdAt),
        transferCount: (existingRecent?.transferCount ?? 0) + 1,
        isTrusted: suggestions[key]?.isTrusted ?? false,
        isRecent: true,
      );
    }

    for (final entry in recentMap.entries) {
      final existing = suggestions[entry.key];
      final recent = entry.value;
      if (existing == null) {
        suggestions[entry.key] = recent;
        continue;
      }
      suggestions[entry.key] = existing.copyWith(
        lastTransactionAt: recent.lastTransactionAt,
        transferCount: recent.transferCount,
        isRecent: true,
      );
    }

    if (mounted) {
      final all = suggestions.values.toList()
        ..sort((a, b) {
          final trustComp = (b.isTrusted ? 1 : 0).compareTo(a.isTrusted ? 1 : 0);
          if (trustComp != 0) return trustComp;
          final freqComp = b.transferCount.compareTo(a.transferCount);
          if (freqComp != 0) return freqComp;
          final aTime = a.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      final recent = all
          .where((s) => s.isRecent)
          .toList()
        ..sort((a, b) {
          final aTime = a.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      setState(() {
        _allSuggestions = all;
        _recentSuggestions = recent.take(10).toList();
        _filteredSuggestions = [];
        _suggestionsLoaded = true;
      });
    }
  }

  void _onUpiChanged() {
    if (!_suggestionsLoaded) return;
    final query = _normalize(_upiController.text);

    if (query.isEmpty) {
      _searchDebounce?.cancel();
      setState(() {
        _isTyping = false;
        _filteredSuggestions = [];
        _receiver = null;
      });
      return;
    }

    setState(() {
      _isTyping = true;
      _receiver = null;
    });

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applySmartSearch(query);
    });
  }

  void _applySmartSearch(String query) {
    final results = _allSuggestions.where((s) {
      return _matchRank(s, query) != null;
    }).toList()
      ..sort((a, b) {
        final rankA = _matchRank(a, query) ?? 999;
        final rankB = _matchRank(b, query) ?? 999;
        if (rankA != rankB) return rankA.compareTo(rankB);

        final freqComp = b.transferCount.compareTo(a.transferCount);
        if (freqComp != 0) return freqComp;

        final aTime = a.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    final nextResults = results.take(10).toList();
    final hasChanged = !_sameSuggestionOrder(_filteredSuggestions, nextResults);
    if (hasChanged || _isTyping) {
      setState(() {
        _filteredSuggestions = nextResults;
        _isTyping = false;
      });
    }
  }

  int? _matchRank(_Suggestion suggestion, String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return null;

    final name = _normalize(suggestion.name);
    final upi = _normalize(suggestion.upiId);
    final maskedUpi = _normalize(MaskedUPIText.mask(suggestion.upiId));

    if (name == normalizedQuery || upi == normalizedQuery || maskedUpi == normalizedQuery) {
      return 0;
    }
    if (name.startsWith(normalizedQuery) ||
        upi.startsWith(normalizedQuery) ||
        maskedUpi.startsWith(normalizedQuery)) {
      return 1;
    }
    if (name.contains(normalizedQuery) ||
        upi.contains(normalizedQuery) ||
        maskedUpi.contains(normalizedQuery)) {
      return 2;
    }
    if (_isSubsequence(normalizedQuery, name)) {
      return 3;
    }

    return null;
  }

  String _normalize(String value) => value.trim().toLowerCase();

  bool _sameSuggestionOrder(List<_Suggestion> oldList, List<_Suggestion> newList) {
    if (oldList.length != newList.length) return false;
    final oldKeys = oldList.map((e) => e.upiId).toList();
    final newKeys = newList.map((e) => e.upiId).toList();
    return listEquals(oldKeys, newKeys);
  }

  bool _isSubsequence(String query, String source) {
    if (query.isEmpty) return true;
    var i = 0;
    for (var j = 0; j < source.length && i < query.length; j++) {
      if (source[j] == query[i]) i++;
    }
    return i == query.length;
  }

  void _selectSuggestion(_Suggestion suggestion) {
    _upiController.text = suggestion.upiId;
    setState(() {
      _receiver = null;
    });
    _upiFocusNode.unfocus();
    _searchUser();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _upiController.removeListener(_onUpiChanged);
    _upiController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _upiFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  _RecipientUiState _recipientState() {
    final query = _normalize(_upiController.text);
    if (query.isEmpty) return _RecipientUiState.empty;
    if (_isTyping) return _RecipientUiState.typing;
    if (_filteredSuggestions.isEmpty) return _RecipientUiState.noResults;
    return _RecipientUiState.results;
  }

  _Suggestion? _mostLikelyRecipient() {
    if (_allSuggestions.isEmpty) return null;
    final ranked = List<_Suggestion>.from(_allSuggestions)
      ..sort((a, b) {
        final aScore = (a.transferCount * 3) + (a.isTrusted ? 2 : 0) + (a.isRecent ? 1 : 0);
        final bScore = (b.transferCount * 3) + (b.isTrusted ? 2 : 0) + (b.isRecent ? 1 : 0);
        if (aScore != bScore) return bScore.compareTo(aScore);
        final aTime = a.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastTransactionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    return ranked.first;
  }

  Future<void> _searchUser() async {
    final upiId = _upiController.text.trim();
    if (upiId.isEmpty || !upiId.contains('@')) return;

    setState(() {
      _isSearching = true;
    });

    final auth = context.read<AuthService>();
    final contacts = context.read<ContactsService>();
    final receiver = await auth.getUserByUpiId(upiId);

    if (receiver == null) {
      if (mounted) {
        setState(() {
          _receiver = null;
          _isSearching = false;
        });
        AppSnackBar.showError(context, 'User not found with UPI ID: $upiId');
      }
      return;
    }

    bool isTrusted = false;
    bool isMerchantFastMode = false;
    String? fraudWarning;

    if (auth.currentUser != null) {
      isTrusted = await contacts.isTrustedContact(
        ownerUserId: auth.currentUser!.uid,
        contactUserId: receiver.uid,
      );
    }

    if (receiver.isMerchant) {
      final settings = await contacts.getMerchantSettings(receiver.uid);
      isMerchantFastMode = settings?.fastMode ?? false;
    }

    if (!isTrusted && receiver.reputationScore < 3.0) {
      fraudWarning = '⚠️ This sender has a low reputation score. Proceed with caution.';
    } else if (!isTrusted) {
      final daysSinceJoined = DateTime.now().difference(receiver.createdAt).inDays;
      if (daysSinceJoined < 30) {
        fraudWarning = '⚠️ New account (${daysSinceJoined}d old). Verify before sending.';
      }
    }

    if (mounted) {
      setState(() {
        _receiver = receiver;
        _isTrusted = isTrusted;
        _isMerchantFastMode = isMerchantFastMode;
        _fraudWarning = fraudWarning;
        _hasPastTransactionsWithReceiver = _allSuggestions
            .any((s) => s.upiId.toLowerCase() == receiver.upiId.toLowerCase());
        _isSearching = false;
      });
      _amountFocusNode.requestFocus();
    }
  }

  Future<void> _sendMoney() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receiver == null) {
      AppSnackBar.showError(context, 'Please search for a receiver first');
      return;
    }

    final auth = context.read<AuthService>();
    if (!auth.hasUpiPinSet) {
      AppSnackBar.showError(
        context,
        'Please create your UPI PIN before sending money.',
      );
      if (mounted) {
        context.push('/auth/set-pin');
      }
      return;
    }

    setState(() => _isSending = true);
    final txService = context.read<TransactionService>();
    final amount = double.parse(_amountController.text.trim());
    final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

    bool shouldAutoAccept = _isTrusted || _isMerchantFastMode;
    if (_receiver!.isMerchant && !_isMerchantFastMode) {
      final contacts = context.read<ContactsService>();
      final settings = await contacts.getMerchantSettings(_receiver!.uid);
      if (settings != null && !settings.fastMode && settings.approvalThreshold != null) {
        shouldAutoAccept = amount < settings.approvalThreshold!;
      }
    }

    if (note != null) {
      final scamResult = await _aiSecurityService.detectScamMessage(note);
      if (scamResult != null && scamResult.isScam && mounted) {
        setState(() => _isSending = false);
        final proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.darkCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                title: Text('Scam Warning', style: AppTypography.headline),
                content: Text(
                  '${scamResult.warning}\n\nScam probability: ${(scamResult.scamProbability * 100).toStringAsFixed(0)}%',
                  style: AppTypography.body,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Send Anyway'),
                  ),
                ],
              ),
            ) ??
            false;

        if (!proceed) return;
        setState(() => _isSending = true);
      }
    }

    var result = await txService.initiatePayment(
      sender: auth.currentUser!,
      receiver: _receiver!,
      amount: amount,
      note: note,
      delayMinutes: _delayMinutes,
      isTrustedContact: _isTrusted,
      isMerchantFastMode: shouldAutoAccept && !_isTrusted,
    );

    if (result['requiresVerification'] == true) {
      if (mounted) {
        final verified = await _runAdditionalVerification(
          riskLevel: (result['riskLevel'] as String?) ?? 'High Risk',
          riskScore: (result['riskScore'] as int?) ?? 0,
          delayRecommended: (result['delayRecommended'] as bool?) ?? false,
        );
        if (!verified) {
          setState(() => _isSending = false);
          return;
        }
      }

      result = await txService.initiatePayment(
        sender: auth.currentUser!,
        receiver: _receiver!,
        amount: amount,
        note: note,
        delayMinutes: _delayMinutes,
        isTrustedContact: _isTrusted,
        isMerchantFastMode: shouldAutoAccept && !_isTrusted,
        verifiedHighRisk: true,
      );
    }

    if (mounted) {
      setState(() => _isSending = false);
      if (result['success'] == true) {
        if (result['isInstant'] == true) {
          context.go('/success/${result['transactionId']}');
        } else {
          context.go('/waiting/${result['transactionId']}');
        }
      } else {
        debugPrint('[SendMoneyScreen] Transaction failed: $result');
        AppSnackBar.showError(context, result['error'] ?? 'Transaction failed');
      }
    }
  }

  Future<bool> _runAdditionalVerification({
    required String riskLevel,
    required int riskScore,
    required bool delayRecommended,
  }) async {
    final otpController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('Additional Verification',
            style: AppTypography.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI classified this transaction as $riskLevel ($riskScore/100).',
              style: AppTypography.body,
            ),
            const SizedBox(height: 10),
            if (delayRecommended)
              const Text(
                'A short delay is recommended before approval.',
                style: TextStyle(color: AppTheme.accentOrange),
              ),
            const SizedBox(height: 12),
            Text(
              'Simulation OTP: 123456',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: otpController,
              label: 'Enter OTP',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final valid = otpController.text.trim() == '123456';
              Navigator.pop(ctx, valid);
            },
            child: const Text('Verify & Continue'),
          ),
        ],
      ),
    );
    otpController.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final amountValue = double.tryParse(_amountController.text.trim()) ?? 0;
    final riskPreview = _receiver == null || amountValue <= 0
        ? null
        : context.read<TransactionService>().evaluateRuleBasedRiskPreview(
              isTrustedContact: _isTrusted,
              hasPastTransactionsWithReceiver: _hasPastTransactionsWithReceiver,
              amount: amountValue,
            );

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Send Money'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () {
          _upiFocusNode.unfocus();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(label: 'SEND TO'),
                const SizedBox(height: 8),
                SearchBar(
                  controller: _upiController,
                  focusNode: _upiFocusNode,
                  onChanged: (_) => _onUpiChanged(),
                  onSubmitted: (_) => _searchUser(),
                ).animate().fadeIn(),

                if (_isSearching) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],

                if (_receiver == null && _suggestionsLoaded) ...[
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: AppTheme.normal,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _recipientState() == _RecipientUiState.empty
                        ? _RecentRecipientPanel(
                            key: const ValueKey('recent-section'),
                            recentSuggestions: _recentSuggestions,
                            fallbackSuggestions: _allSuggestions,
                            mostLikely: _mostLikelyRecipient(),
                            onSelect: _selectSuggestion,
                          )
                        : _recipientState() == _RecipientUiState.typing
                            ? const _SearchTypingState(key: ValueKey('typing-search'))
                            : _recipientState() == _RecipientUiState.noResults
                            ? const RecipientEmptyState(key: ValueKey('empty-search'))
                            : _RecipientSection(
                                key: const ValueKey('result-section'),
                                title: 'SEARCH RESULTS',
                                suggestions: _filteredSuggestions,
                                query: _upiController.text.trim(),
                                onSelect: _selectSuggestion,
                              ),
                  ),
                ],

                // Receiver info card
                if (_receiver != null) ...[
                  const SizedBox(height: 16),
                  _ReceiverCard(
                    receiver: _receiver!,
                    isTrusted: _isTrusted,
                    isMerchantFastMode: _isMerchantFastMode,
                    fraudWarning: _fraudWarning,
                  ).animate().fadeIn().slideY(begin: 0.2),
                ],

                const SizedBox(height: 24),
                // Amount
                const SectionHeader(label: 'AMOUNT'),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  label: '',
                  hint: '₹ 100',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.currency_rupee_rounded,
                  validator: Validators.validateAmount,
                  style: AppTypography.amountDisplay.copyWith(fontSize: 24),
                ).animate().fadeIn(delay: 100.ms),
                const SizedBox(height: 8),
                // Quick amount chips
                Wrap(
                  spacing: 8,
                  children: [100, 200, 500, 1000, 2000].map((amt) {
                    return ActionChip(
                      label: Text('₹$amt'),
                      onPressed: () => _amountController.text = amt.toString(),
                      backgroundColor: AppTheme.darkCard,
                      labelStyle: AppTypography.caption.copyWith(color: AppTheme.textSecondary),
                      side: const BorderSide(color: AppTheme.darkDivider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    );
                  }).toList(),
                ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          color: AppTheme.textMuted, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Release delay',
                        style: AppTypography.body.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [0, 2, 5, 10].map((minutes) {
                      final selected = _delayMinutes == minutes;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(
                          minutes == 0 ? 'No Delay' : '$minutes min',
                        ),
                        selectedColor:
                          AppTheme.primaryColor.withValues(alpha: 0.18),
                        backgroundColor: AppTheme.darkCard,
                        labelStyle: TextStyle(
                          color: selected
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: selected
                              ? AppTheme.primaryColor
                              : AppTheme.darkDivider,
                        ),
                        onSelected: (_) => setState(() => _delayMinutes = minutes),
                      );
                    }).toList(),
                  ),
                  if (riskPreview != null)
                    _RiskPreviewCard(
                      score: riskPreview['score'] as int,
                      level: riskPreview['riskLevel'] as String,
                      warnings: (riskPreview['warnings'] as List)
                          .map((e) => e.toString())
                          .toList(),
                    ).animate().fadeIn(delay: 150.ms),
                  if (riskPreview != null) const SizedBox(height: 16),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _noteController,
                  label: 'Note (optional)',
                  hint: 'For lunch, bill, etc.',
                  prefixIcon: Icons.note_outlined,
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 32),
                // Send button
                PrimaryButton(
                  label: _receiver == null
                      ? 'Find Receiver First'
                      : _isTrusted
                          ? 'Pay Instantly'
                          : _isMerchantFastMode
                              ? 'Pay via Fast Mode'
                              : 'Send for Approval',
                  onPressed: _receiver != null ? _sendMoney : null,
                  isLoading: _isSending,
                  icon: _isTrusted || _isMerchantFastMode
                      ? Icons.flash_on_rounded
                      : Icons.send_rounded,
                ).animate().fadeIn(delay: 300.ms),

                if (!_isTrusted && !_isMerchantFastMode && _receiver != null) ...[
                  const SizedBox(height: 12),
                  const EscrowBanner().animate().fadeIn(delay: 400.ms),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RiskPreviewCard extends StatelessWidget {
  final int score;
  final String level;
  final List<String> warnings;

  const _RiskPreviewCard({
    required this.score,
    required this.level,
    required this.warnings,
  });

  Color _riskColor() {
    if (score >= 75) return AppTheme.errorColor;
    if (score >= 40) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: riskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: riskColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: riskColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Risk Score: $score% ($level)',
                style: GoogleFonts.inter(
                  color: riskColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...warnings.take(3).map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $warning',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _SearchTypingState extends StatelessWidget {
  const _SearchTypingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Searching recipients...',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRecipientPanel extends StatelessWidget {
  final List<_Suggestion> recentSuggestions;
  final List<_Suggestion> fallbackSuggestions;
  final _Suggestion? mostLikely;
  final void Function(_Suggestion) onSelect;

  const _RecentRecipientPanel({
    super.key,
    required this.recentSuggestions,
    required this.fallbackSuggestions,
    required this.mostLikely,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final listToRender = recentSuggestions.isNotEmpty
        ? recentSuggestions
        : fallbackSuggestions;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostLikely != null) ...[
          const SectionHeader(label: 'MOST LIKELY RECIPIENT'),
          const SizedBox(height: 10),
          ContactListItem(
            name: mostLikely!.name,
            upiId: mostLikely!.upiId,
            isTrusted: mostLikely!.isTrusted,
            isRecent: mostLikely!.isRecent,
            lastTransactionLabel: mostLikely!.lastTransactionAt != null
                ? 'Paid ${Formatters.formatRelativeTime(mostLikely!.lastTransactionAt!)} • ${mostLikely!.transferCount} transfers'
                : null,
            query: '',
            onTap: () => onSelect(mostLikely!),
          ),
          const SizedBox(height: 12),
        ],
        _RecipientSection(
          title: 'RECENT CONTACTS',
          suggestions: listToRender,
          query: '',
          onSelect: onSelect,
        ),
      ],
    );
  }
}

class _RecipientSection extends StatelessWidget {
  final String title;
  final List<_Suggestion> suggestions;
  final String query;
  final void Function(_Suggestion) onSelect;

  const _RecipientSection({
    super.key,
    required this.title,
    required this.suggestions,
    required this.query,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: title),
        const SizedBox(height: 10),
        ...suggestions.take(8).map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ContactListItem(
                  name: s.name,
                  upiId: s.upiId,
                  isTrusted: s.isTrusted,
                  isRecent: s.isRecent,
                  lastTransactionLabel: s.lastTransactionAt != null
                      ? 'Last paid ${Formatters.formatRelativeTime(s.lastTransactionAt!)}'
                      : null,
                  query: query,
                  onTap: () => onSelect(s),
                ),
              ),
            ),
      ],
    );
  }
}

class _ReceiverCard extends StatelessWidget {
  final UserModel receiver;
  final bool isTrusted;
  final bool isMerchantFastMode;
  final String? fraudWarning;

  const _ReceiverCard({
    required this.receiver,
    required this.isTrusted,
    required this.isMerchantFastMode,
    this.fraudWarning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTrusted
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : AppTheme.darkDivider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: receiver.isMerchant
                      ? const LinearGradient(colors: [
                          AppTheme.secondaryColor,
                          AppTheme.secondaryDark
                        ])
                      : const LinearGradient(colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryDark
                        ]),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    receiver.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          receiver.displayName,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (receiver.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              color: AppTheme.primaryColor, size: 16),
                        ],
                      ],
                    ),
                    Text(
                      MaskedUPIText.mask(receiver.upiId),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isTrusted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded,
                              color: AppTheme.successColor, size: 12),
                          SizedBox(width: 4),
                          Text('Trusted',
                              style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (isMerchantFastMode && !isTrusted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on_rounded,
                              color: AppTheme.accentOrange, size: 12),
                          SizedBox(width: 4),
                          Text('Fast Mode',
                              style: TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (receiver.isMerchant)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('MERCHANT',
                            style: TextStyle(
                                color: AppTheme.secondaryColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (fraudWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.warningColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warningColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fraudWarning!,
                      style: const TextStyle(
                        color: AppTheme.warningColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
