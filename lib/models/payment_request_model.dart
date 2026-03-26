// =============================================================================
// PAYMENT REQUEST MODEL
// lib/models/payment_request_model.dart
//
// Lightweight model for the `payment_requests` Firestore collection.
// Kept separate from TransactionModel for clarity — this represents the
// consent stage before a transaction is created/completed.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentRequestStatus { pending, approved, rejected, expired }

class PaymentRequestModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String senderName;
  final double amount;
  final PaymentRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  /// The transaction ID this request maps to (if one was created).
  final String? transactionId;

  /// Optional note from sender.
  final String? note;

  PaymentRequestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.transactionId,
    this.note,
  });

  factory PaymentRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentRequestModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      senderName: data['senderName'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      status: PaymentRequestStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => PaymentRequestStatus.pending,
      ),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      transactionId: data['transactionId'] as String?,
      note: data['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'senderName': senderName,
      'amount': amount,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (respondedAt != null)
        'respondedAt': Timestamp.fromDate(respondedAt!),
      if (transactionId != null) 'transactionId': transactionId,
      if (note != null) 'note': note,
    };
  }

  PaymentRequestModel copyWith({
    PaymentRequestStatus? status,
    DateTime? respondedAt,
    String? transactionId,
  }) {
    return PaymentRequestModel(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      senderName: senderName,
      amount: amount,
      status: status ?? this.status,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
      transactionId: transactionId ?? this.transactionId,
      note: note,
    );
  }

  bool get isPending => status == PaymentRequestStatus.pending;
  String get statusLabel => status.name[0].toUpperCase() + status.name.substring(1);
}
