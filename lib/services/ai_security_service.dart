import 'package:flutter/foundation.dart';

import '../models/transaction_model.dart';
import 'api_service.dart';

class AiTransactionRiskResult {
  final double riskScore;
  final String classification;
  final List<String> triggers;
  final bool requireExtraVerification;
  final bool delayRecommended;

  const AiTransactionRiskResult({
    required this.riskScore,
    required this.classification,
    required this.triggers,
    required this.requireExtraVerification,
    required this.delayRecommended,
  });
}

class AiScamDetectionResult {
  final double scamProbability;
  final bool isScam;
  final List<String> matchedPatterns;
  final String warning;

  const AiScamDetectionResult({
    required this.scamProbability,
    required this.isScam,
    required this.matchedPatterns,
    required this.warning,
  });
}

class AiBehaviorResult {
  final double anomalyScore;
  final bool isAnomaly;
  final List<String> reasons;
  final String action;

  const AiBehaviorResult({
    required this.anomalyScore,
    required this.isAnomaly,
    required this.reasons,
    required this.action,
  });
}

class AiAssistantResult {
  final String answer;
  final double monthlyTotal;
  final String? topCategory;
  final Map<String, double> categoryBreakdown;

  const AiAssistantResult({
    required this.answer,
    required this.monthlyTotal,
    required this.topCategory,
    required this.categoryBreakdown,
  });
}

class AiSecurityService {
  static final AiSecurityService _instance = AiSecurityService._internal();
  factory AiSecurityService() => _instance;
  AiSecurityService._internal();

  final ApiService _api = ApiService();

  static const Duration _timeout = Duration(seconds: 4);
  static const Duration _assistantTimeout = Duration(seconds: 6);
  static const Duration _remoteBackoff = Duration(minutes: 2);
  DateTime? _remoteUnavailableUntil;
  static const List<String> _scamPatterns = [
    'send money to unlock parcel',
    'urgent payment required',
    'your account will be blocked',
    'verify kyc now',
    'refund processing fee',
    'click this payment link',
    'otp share now',
    'account suspended',
    'pay now to avoid block',
  ];

  String _riskPath() => '/ai/analyze-transaction';

  String _scamPath() => '/ai/security-check';

  String _behaviorPath() => '/ai/security-check';

  String _assistantPath() => '/ai/chat-assistant';

  bool get _hasValidAiEndpoint {
    return _api.isEnabled;
  }

  bool get _isRemoteTemporarilyDisabled {
    final until = _remoteUnavailableUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _markRemoteDown() {
    _remoteUnavailableUntil = DateTime.now().add(_remoteBackoff);
  }

  void _markRemoteHealthy() {
    _remoteUnavailableUntil = null;
  }

  double _clamp(double v, [double min = 0, double max = 1]) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  double _avg(List<double> values) {
    final valid = values.where((v) => v > 0).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  String _classify(double score) {
    if (score >= 0.75) return 'High Risk';
    if (score >= 0.4) return 'Medium Risk';
    return 'Safe';
  }

  String _categoryFromText(String text) {
    final n = text.toLowerCase();
    if (['food', 'dinner', 'restaurant', 'swiggy', 'zomato']
        .any((k) => n.contains(k))) {
      return 'food';
    }
    if (['cab', 'uber', 'ola', 'fuel', 'petrol', 'metro', 'travel']
        .any((k) => n.contains(k))) {
      return 'transport';
    }
    if (['rent', 'electricity', 'water', 'internet', 'bill']
        .any((k) => n.contains(k))) {
      return 'bills';
    }
    if (['movie', 'shopping', 'amazon', 'flipkart', 'entertainment']
        .any((k) => n.contains(k))) {
      return 'shopping';
    }
    if (['medicine', 'hospital', 'pharmacy', 'doctor']
        .any((k) => n.contains(k))) {
      return 'health';
    }
    return 'other';
  }

  Future<AiTransactionRiskResult?> assessTransactionRisk({
    required String userId,
    required String receiverId,
    required double amount,
    required bool knownReceiver,
    required int txCountLast24h,
    required bool deviceMismatch,
    required bool locationMismatch,
    required bool unusualSpendingPattern,
    required List<double> historicalAmounts,
  }) async {
    if (!_hasValidAiEndpoint || _isRemoteTemporarilyDisabled) {
      return _localRisk(
        amount: amount,
        knownReceiver: knownReceiver,
        txCountLast24h: txCountLast24h,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
        unusualSpendingPattern: unusualSpendingPattern,
        historicalAmounts: historicalAmounts,
      );
    }

    try {
      final data = await _api.post(
        _riskPath(),
        {
          'user_id': userId,
          'receiver_id': receiverId,
          'amount': amount,
          'known_receiver': knownReceiver,
          'tx_count_last_24h': txCountLast24h,
          'device_mismatch': deviceMismatch,
          'location_mismatch': locationMismatch,
          'unusual_spending_pattern': unusualSpendingPattern,
          'historical_amounts': historicalAmounts,
          'is_new_merchant': !knownReceiver,
          'tx_hour': DateTime.now().hour,
        },
        timeout: _timeout,
        retries: 2,
      );

      if (data == null) {
        _markRemoteDown();
        return _localRisk(
          amount: amount,
          knownReceiver: knownReceiver,
          txCountLast24h: txCountLast24h,
          deviceMismatch: deviceMismatch,
          locationMismatch: locationMismatch,
          unusualSpendingPattern: unusualSpendingPattern,
          historicalAmounts: historicalAmounts,
        );
      }
      _markRemoteHealthy();

      return AiTransactionRiskResult(
        riskScore: (data['risk_score'] as num?)?.toDouble() ?? 0,
        classification: (data['classification'] as String?) ?? 'Safe',
        triggers: ((data['triggers'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList(),
        requireExtraVerification:
            (data['require_extra_verification'] as bool?) ?? false,
        delayRecommended: (data['delay_recommended'] as bool?) ?? false,
      );
    } catch (e) {
      _markRemoteDown();
      debugPrint('[AiSecurityService] risk error: $e');
      return _localRisk(
        amount: amount,
        knownReceiver: knownReceiver,
        txCountLast24h: txCountLast24h,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
        unusualSpendingPattern: unusualSpendingPattern,
        historicalAmounts: historicalAmounts,
      );
    }
  }

  AiTransactionRiskResult _localRisk({
    required double amount,
    required bool knownReceiver,
    required int txCountLast24h,
    required bool deviceMismatch,
    required bool locationMismatch,
    required bool unusualSpendingPattern,
    required List<double> historicalAmounts,
  }) {
    var score = 0.08;
    final triggers = <String>[];
    if (amount > 5000) {
      score += 0.2;
      triggers.add('High transaction amount');
    }
    if (!knownReceiver) {
      score += 0.22;
      triggers.add('Receiver not in known contacts');
    }
    if (txCountLast24h > 8) {
      score += 0.18;
      triggers.add('Unusual transaction frequency');
    }
    if (deviceMismatch || locationMismatch) {
      score += 0.2;
      triggers.add('Device or location mismatch');
    }
    if (unusualSpendingPattern) {
      score += 0.15;
      triggers.add('Unusual spending pattern');
    }
    final avg = _avg(historicalAmounts);
    if (avg > 0 && amount > avg * 3) {
      score += 0.15;
      triggers.add('Amount is far above historical average');
    }
    final normalized = _clamp(score);
    final cls = _classify(normalized);
    return AiTransactionRiskResult(
      riskScore: normalized,
      classification: cls,
      triggers: triggers,
      requireExtraVerification: cls == 'High Risk',
      delayRecommended: cls == 'High Risk' && amount > 7000,
    );
  }

  Future<AiScamDetectionResult?> detectScamMessage(String message) async {
    if (message.trim().isEmpty) return null;

    if (!_hasValidAiEndpoint || _isRemoteTemporarilyDisabled) {
      return _localScam(message);
    }

    try {
      final data = await _api.post(
        _scamPath(),
        {
          'amount': 0,
          'known_receiver': true,
          'tx_count_last_24h': 0,
          'unusual_spending_pattern': _localScam(message).isScam,
          'historical_amounts': const <double>[],
          'is_new_merchant': false,
        },
        timeout: _timeout,
        retries: 1,
      );

      if (data == null) {
        _markRemoteDown();
        return _localScam(message);
      }
      _markRemoteHealthy();
      final local = _localScam(message);

      return AiScamDetectionResult(
        scamProbability: (data['risk_score'] as num?)?.toDouble() ?? local.scamProbability,
        isScam: ((data['risk_score'] as num?)?.toDouble() ?? 0) >= 0.6 || local.isScam,
        matchedPatterns: local.matchedPatterns,
        warning: local.warning,
      );
    } catch (e) {
      _markRemoteDown();
      debugPrint('[AiSecurityService] scam error: $e');
      return _localScam(message);
    }
  }

  AiScamDetectionResult _localScam(String message) {
    final text = message.toLowerCase().trim();
    final matched = _scamPatterns.where((p) => text.contains(p)).toList();
    var score = matched.isNotEmpty ? 0.84 : 0.08;
    if (RegExp(r'urgent|immediately|now|blocked|suspended|otp|link')
        .hasMatch(text)) {
      score += 0.2;
    }
    if (RegExp(r'(pay|send|transfer).*(fee|charge|unlock|verify)')
        .hasMatch(text)) {
      score += 0.15;
    }
    final probability = _clamp(score);
    final isScam = probability >= 0.6;
    return AiScamDetectionResult(
      scamProbability: probability,
      isScam: isScam,
      matchedPatterns: matched,
      warning: isScam
          ? 'Warning: This message appears similar to known payment scams.'
          : 'Message appears safe, but always verify sender identity.',
    );
  }

  Future<AiBehaviorResult?> analyzeBehavior({
    required String userId,
    required String receiverId,
    required double amount,
    required bool knownReceiver,
    required int txCountLast24h,
    required bool deviceMismatch,
    required bool locationMismatch,
    required bool unusualSpendingPattern,
  }) async {
    if (!_hasValidAiEndpoint || _isRemoteTemporarilyDisabled) {
      return _localBehavior(
        amount: amount,
        txCountLast24h: txCountLast24h,
        knownReceiver: knownReceiver,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
      );
    }

    try {
      final now = DateTime.now();
      final data = await _api.post(
        _behaviorPath(),
        {
          'user_id': userId,
          'amount': amount,
          'receiver_id': receiverId,
          'tx_hour': now.hour,
          'known_receiver': knownReceiver,
          'tx_count_last_24h': txCountLast24h,
          'device_mismatch': deviceMismatch,
          'location_mismatch': locationMismatch,
          'unusual_spending_pattern': unusualSpendingPattern,
          'is_new_merchant': !knownReceiver,
        },
        timeout: _timeout,
        retries: 2,
      );

      if (data == null) {
        _markRemoteDown();
        return _localBehavior(
          amount: amount,
          txCountLast24h: txCountLast24h,
          knownReceiver: knownReceiver,
          deviceMismatch: deviceMismatch,
          locationMismatch: locationMismatch,
        );
      }
      _markRemoteHealthy();

      return AiBehaviorResult(
        anomalyScore: (data['risk_score'] as num?)?.toDouble() ?? 0,
        isAnomaly: ((data['risk_score'] as num?)?.toDouble() ?? 0) >= 0.65,
        reasons: ((data['triggers'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList(),
        action: ((data['risk_score'] as num?)?.toDouble() ?? 0) >= 0.65
          ? 'trigger_verification'
          : 'allow',
      );
    } catch (e) {
      _markRemoteDown();
      debugPrint('[AiSecurityService] behavior error: $e');
      return _localBehavior(
        amount: amount,
        txCountLast24h: txCountLast24h,
        knownReceiver: knownReceiver,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
      );
    }
  }

  AiBehaviorResult _localBehavior({
    required double amount,
    required int txCountLast24h,
    required bool knownReceiver,
    required bool deviceMismatch,
    required bool locationMismatch,
  }) {
    var score = 0.05;
    final reasons = <String>[];
    final hour = DateTime.now().hour;
    if (amount > 8000) {
      score += 0.25;
      reasons.add('Large payment compared to common range');
    }
    if (!knownReceiver) {
      score += 0.2;
      reasons.add('Unknown recipient');
    }
    if (hour < 5 || hour > 23) {
      score += 0.12;
      reasons.add('Unusual activity time');
    }
    if (txCountLast24h > 10) {
      score += 0.18;
      reasons.add('High transaction burst in 24h');
    }
    if (deviceMismatch || locationMismatch) {
      score += 0.2;
      reasons.add('Context mismatch (device/location)');
    }

    final normalized = _clamp(score);
    final isAnomaly = normalized >= 0.65;
    return AiBehaviorResult(
      anomalyScore: normalized,
      isAnomaly: isAnomaly,
      reasons: reasons,
      action: isAnomaly ? 'trigger_verification' : 'allow',
    );
  }

  Future<AiAssistantResult?> assistantSummary({
    required String userId,
    required String question,
    required List<TransactionModel> transactions,
  }) async {
    if (!_hasValidAiEndpoint || _isRemoteTemporarilyDisabled) {
      return _localAssistant(question, userId, transactions);
    }

    try {
      final data = await _api.post(
        _assistantPath(),
        {
          'user_id': userId,
          'question': question,
          'transactions': transactions
              .where((tx) => tx.senderId == userId && tx.status == TransactionStatus.completed)
              .map((tx) => {
                    'amount': tx.amount,
                    'note': tx.note,
                    'receiver_name': tx.receiverName,
                    'created_at': tx.createdAt.toIso8601String(),
                  })
              .toList(),
        },
        timeout: _assistantTimeout,
        retries: 1,
        cacheable: true,
        cacheTtl: const Duration(minutes: 1),
      );

      if (data == null) {
        _markRemoteDown();
        return _localAssistant(question, userId, transactions);
      }
      _markRemoteHealthy();

      final breakdownRaw = (data['category_breakdown'] as Map<String, dynamic>?) ?? {};
      final breakdown = <String, double>{
        for (final entry in breakdownRaw.entries)
          entry.key: (entry.value as num).toDouble(),
      };

      return AiAssistantResult(
        answer: (data['answer'] as String?) ?? 'No insights available.',
        monthlyTotal: (data['monthly_total'] as num?)?.toDouble() ?? 0,
        topCategory: data['top_category'] as String?,
        categoryBreakdown: breakdown,
      );
    } catch (e) {
      _markRemoteDown();
      debugPrint('[AiSecurityService] assistant error: $e');
      return _localAssistant(question, userId, transactions);
    }
  }

  AiAssistantResult _localAssistant(
    String question,
    String userId,
    List<TransactionModel> transactions,
  ) {
    final spendingTx = transactions
        .where(
            (tx) => tx.senderId == userId && tx.status == TransactionStatus.completed)
        .toList();

    final breakdown = <String, double>{};
    var total = 0.0;

    for (final tx in spendingTx) {
      total += tx.amount;
      final category = _categoryFromText('${tx.note ?? ''} ${tx.receiverName}');
      breakdown[category] = (breakdown[category] ?? 0) + tx.amount;
    }

    String? topCategory;
    if (breakdown.isNotEmpty) {
      topCategory = breakdown.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    final q = question.toLowerCase();
    String answer;
    if (q.contains('how much') || q.contains('spent')) {
      answer = 'You spent ₹${total.toStringAsFixed(0)} in this period.';
    } else if (q.contains('where') || q.contains('most')) {
      answer = topCategory == null
          ? 'I could not find enough transactions to infer top category yet.'
          : 'Most spending went to $topCategory (₹${(breakdown[topCategory] ?? 0).toStringAsFixed(0)}).';
    } else {
      answer = topCategory == null
          ? 'Total spending is ₹${total.toStringAsFixed(0)}. Not enough data for a top category.'
          : 'Total spending is ₹${total.toStringAsFixed(0)}. Top category is $topCategory.';
    }

    return AiAssistantResult(
      answer: answer,
      monthlyTotal: total,
      topCategory: topCategory,
      categoryBreakdown: breakdown,
    );
  }
}
