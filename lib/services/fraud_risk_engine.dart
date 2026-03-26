// =============================================================================
// FRAUD RISK ENGINE
// lib/services/fraud_risk_engine.dart
//
// Architecture:
//   This module implements a lightweight, on-device ML-style heuristic model
//   that calculates a fraud risk score BEFORE the payment request notification
//   is dispatched to the receiver.
//
//   The engine reads historical transaction data from Firestore and computes
//   a weighted additive risk score across several independent risk factors.
//
//   Risk Score Breakdown:
//   ┌──────────────────────────────────────────┬───────┐
//   │ Factor                                   │ Score │
//   ├──────────────────────────────────────────┼───────┤
//   │ First-time sender                        │  25   │
//   │ Sender NOT in receiver's trusted contacts│  20   │
//   │ Amount > 2× avg past amount              │  20   │
//   │ Amount > 3× avg past amount              │  +15  │
//   │ >3 requests from sender in last 60 min   │  25   │
//   │ Non-verified sender account              │  10   │
//   └──────────────────────────────────────────┴───────┘
//   Max raw score = 100+ → clamped to 100
//   Classification:
//     0–29   → Low
//     30–59  → Medium
//     60–100 → High
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Three-tier risk classification returned to the caller.
enum RiskLevel { low, medium, high }

/// Detailed result object containing score, level, and human-readable summary.
class RiskAssessment {
  final int score; // 0–100
  final RiskLevel level;
  final List<String> flags; // Specific risk factors that were triggered

  const RiskAssessment({
    required this.score,
    required this.level,
    required this.flags,
  });

  /// Short label for display in notification and UI.
  String get levelLabel {
    switch (level) {
      case RiskLevel.low:
        return 'Low Risk';
      case RiskLevel.medium:
        return 'Medium Risk';
      case RiskLevel.high:
        return 'High Risk';
    }
  }

  /// Emoji indicator for at-a-glance colour coding.
  String get levelEmoji {
    switch (level) {
      case RiskLevel.low:
        return '🟢';
      case RiskLevel.medium:
        return '🟡';
      case RiskLevel.high:
        return '🔴';
    }
  }

  /// Hex-style colour string usable in notification payloads.
  String get levelColor {
    switch (level) {
      case RiskLevel.low:
        return '#22C55E';
      case RiskLevel.medium:
        return '#F59E0B';
      case RiskLevel.high:
        return '#EF4444';
    }
  }

  @override
  String toString() =>
      'RiskAssessment(score: $score, level: $levelLabel, flags: $flags)';
}

/// Singleton service — call [analyze] before dispatching a payment notification.
class FraudRiskEngine {
  static final FraudRiskEngine _instance = FraudRiskEngine._internal();
  factory FraudRiskEngine() => _instance;
  FraudRiskEngine._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Weight constants ──────────────────────────────────────────────────────

  static const int _wtFirstTimeSender = 25;
  static const int _wtNotTrusted = 20;
  static const int _wtAmountAnomaly2x = 20;
  static const int _wtAmountAnomaly3x = 15; // additive on top of 2x flag
  static const int _wtFrequencyBurst = 25;
  static const int _wtUnverifiedSender = 10;

  // ── Thresholds ─────────────────────────────────────────────────────────────

  /// Minimum number of past completed transactions to compute an average.
  static const int _minHistoryForAvg = 3;

  /// Max requests from the same sender in this window before flagging.
  static const int _burstThreshold = 3;

  /// Time window for burst detection (minutes).
  static const int _burstWindowMinutes = 60;

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Evaluate fraud risk for an incoming payment request.
  ///
  /// [senderId]   – UID of the person sending money.
  /// [receiverId] – UID of the receiver (notification target).
  /// [amount]     – Transaction amount in ₹.
  Future<RiskAssessment> analyze({
    required String senderId,
    required String receiverId,
    required double amount,
    bool isTrustedContact = false,
  }) async {
    int score = 0;
    final List<String> flags = [];

    try {
      // Fetch data the SENDER is authorised to read (own transactions + own profile).
      final results = await Future.wait([
        _getPastTransactionsBetween(senderId, receiverId),
        _getSenderHistoricalTransactions(senderId),
        _getRecentRequestsFromSender(senderId),
        _isSenderVerified(senderId),
      ]);

      final pastBetween = results[0] as List<Map<String, dynamic>>;
      final senderHistory = results[1] as List<Map<String, dynamic>>;
      final recentRequests = results[2] as List<Map<String, dynamic>>;
      final isSenderVerified = results[3] as bool;

      // ── Factor 1: First-time receiver (no prior transactions to this person)
      if (pastBetween.isEmpty) {
        score += _wtFirstTimeSender;
        flags.add('First-time sender');
      }

      // ── Factor 2: Sender not in trusted contacts ─────────────────────────
      // This flag is passed in by the caller which already checked trusted status.
      if (!isTrustedContact) {
        score += _wtNotTrusted;
        flags.add('Not a trusted contact');
      }

      // ── Factor 3: Amount anomaly (based on sender's OWN history) ─────────
      if (senderHistory.length >= _minHistoryForAvg) {
        final amounts = senderHistory
            .map((t) => (t['amount'] as num?)?.toDouble() ?? 0.0)
            .where((a) => a > 0)
            .toList();
        if (amounts.isNotEmpty) {
          final avg = amounts.reduce((a, b) => a + b) / amounts.length;
          if (amount > avg * 3) {
            score += _wtAmountAnomaly2x + _wtAmountAnomaly3x;
            flags.add('Amount is 3× above average (₹${avg.toStringAsFixed(0)})');
          } else if (amount > avg * 2) {
            score += _wtAmountAnomaly2x;
            flags.add('Amount is 2× above average (₹${avg.toStringAsFixed(0)})');
          }
        }
      }

      // ── Factor 4: Rapid burst of requests ────────────────────────────────
      if (recentRequests.length >= _burstThreshold) {
        score += _wtFrequencyBurst;
        flags.add(
            '${recentRequests.length} requests in last $_burstWindowMinutes min');
      }

      // ── Factor 5: Unverified sender account ──────────────────────────────
      if (!isSenderVerified) {
        score += _wtUnverifiedSender;
        flags.add('Sender account is unverified');
      }
    } catch (e) {
      // Never block a payment due to a scoring error — default to Medium.
      debugPrint('[FraudRiskEngine] Error during analysis: $e');
      return const RiskAssessment(
        score: 35,
        level: RiskLevel.medium,
        flags: ['Risk scoring unavailable – review manually'],
      );
    }

    // Clamp to 100
    score = score.clamp(0, 100);

    final level = _classify(score);
    debugPrint(
        '[FraudRiskEngine] score=$score level=${level.name} flags=$flags');

    return RiskAssessment(score: score, level: level, flags: flags);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  RiskLevel _classify(int score) {
    if (score >= 60) return RiskLevel.high;
    if (score >= 30) return RiskLevel.medium;
    return RiskLevel.low;
  }

  /// Previous completed/approved transactions between this sender→receiver pair.
  Future<List<Map<String, dynamic>>> _getPastTransactionsBetween(
      String senderId, String receiverId) async {
    final snap = await _db
        .collection('transactions')
        .where('senderId', isEqualTo: senderId)
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: 'completed')
        .limit(10)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Sender's own historical completed transactions (for avg amount calc).
  /// The sender can read transactions where they are a participant.
  Future<List<Map<String, dynamic>>> _getSenderHistoricalTransactions(
      String senderId) async {
    final snap = await _db
        .collection('transactions')
        .where('senderId', isEqualTo: senderId)
        .where('status', isEqualTo: 'completed')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Count how many payment requests this sender has sent in the last hour.
  Future<List<Map<String, dynamic>>> _getRecentRequestsFromSender(
      String senderId) async {
    final windowStart = DateTime.now()
        .subtract(const Duration(minutes: _burstWindowMinutes));
    final snap = await _db
        .collection('transactions')
        .where('senderId', isEqualTo: senderId)
        .where('createdAt',
            isGreaterThan: Timestamp.fromDate(windowStart))
        .orderBy('createdAt')
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Returns the isVerified flag from the sender's user document.
  Future<bool> _isSenderVerified(String senderId) async {
    final doc = await _db.collection('users').doc(senderId).get();
    if (!doc.exists) return false;
    return (doc.data()?['isVerified'] as bool?) ?? false;
  }
}
