import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus {
  pending,
  approved,
  rejected,
  completed,
  refunded,
  timedOut,
}

enum TransactionType {
  send,
  receive,
  topUp,
  refund,
}

class TransactionModel {
  final String transactionId;
  final String senderId;
  final String receiverId;
  final String senderName;
  final String receiverName;
  final String senderUpiId;
  final String receiverUpiId;
  final double amount;
  final TransactionStatus status;
  final TransactionType type;
  final String? note;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final DateTime? releaseAt;
  final DateTime? cancelUntil;
  final int delayMinutes;
  final String? cancellationReason;
  final bool isEscrow;
  final bool isTrustedContact;

  // AI Risk Scoring fields (present on pending consent-based transactions)
  final int? riskScore;     // 0–100
  final String? riskLevel;  // 'Low Risk' | 'Medium Risk' | 'High Risk'
  final List<String>? riskFlags; // Human-readable risk factors

  TransactionModel({
    required this.transactionId,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.receiverName,
    required this.senderUpiId,
    required this.receiverUpiId,
    required this.amount,
    required this.status,
    required this.type,
    this.note,
    required this.createdAt,
    this.completedAt,
    this.expiresAt,
    this.releaseAt,
    this.cancelUntil,
    this.delayMinutes = 0,
    this.cancellationReason,
    this.isEscrow = false,
    this.isTrustedContact = false,
    this.riskScore,
    this.riskLevel,
    this.riskFlags,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      transactionId: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      senderName: data['senderName'] ?? '',
      receiverName: data['receiverName'] ?? '',
      senderUpiId: data['senderUpiId'] ?? '',
      receiverUpiId: data['receiverUpiId'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => TransactionStatus.pending,
      ),
      type: TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.send,
      ),
      note: data['note'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
        releaseAt: (data['releaseAfter'] as Timestamp?)?.toDate() ??
          (data['releaseAt'] as Timestamp?)?.toDate(),
        cancelUntil: (data['cancelUntil'] as Timestamp?)?.toDate(),
        delayMinutes: (data['delayMinutes'] as num?)?.toInt() ?? 0,
        cancellationReason: data['cancellationReason'] as String?,
      isEscrow: data['isEscrow'] ?? false,
      isTrustedContact: data['isTrustedContact'] ?? false,
      riskScore: (data['riskScore'] as num?)?.toInt(),
      riskLevel: data['riskLevel'] as String?,
      riskFlags: (data['riskFlags'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'senderName': senderName,
      'receiverName': receiverName,
      'senderUpiId': senderUpiId,
      'receiverUpiId': receiverUpiId,
      'amount': amount,
      'status': status.name,
      'type': type.name,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'releaseAfter': releaseAt != null ? Timestamp.fromDate(releaseAt!) : null,
      'cancelUntil': cancelUntil != null ? Timestamp.fromDate(cancelUntil!) : null,
      'delayMinutes': delayMinutes,
      'cancellationReason': cancellationReason,
      'isEscrow': isEscrow,
      'isTrustedContact': isTrustedContact,
      if (riskScore != null) 'riskScore': riskScore,
      if (riskLevel != null) 'riskLevel': riskLevel,
      if (riskFlags != null) 'riskFlags': riskFlags,
    };
  }

  TransactionModel copyWith({
    TransactionStatus? status,
    DateTime? completedAt,
    DateTime? releaseAt,
    DateTime? cancelUntil,
    int? delayMinutes,
    String? cancellationReason,
  }) {
    return TransactionModel(
      transactionId: transactionId,
      senderId: senderId,
      receiverId: receiverId,
      senderName: senderName,
      receiverName: receiverName,
      senderUpiId: senderUpiId,
      receiverUpiId: receiverUpiId,
      amount: amount,
      status: status ?? this.status,
      type: type,
      note: note,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      expiresAt: expiresAt,
      releaseAt: releaseAt ?? this.releaseAt,
      cancelUntil: cancelUntil ?? this.cancelUntil,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      isEscrow: isEscrow,
      isTrustedContact: isTrustedContact,
      riskScore: riskScore,
      riskLevel: riskLevel,
      riskFlags: riskFlags,
    );
  }

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  String get id => transactionId;

  DateTime get timestamp => createdAt;

  String get statusLabel {
    switch (status) {
      case TransactionStatus.pending:
        return 'Pending';
      case TransactionStatus.approved:
        return 'Approved';
      case TransactionStatus.rejected:
        return 'Rejected';
      case TransactionStatus.completed:
        return 'Completed';
      case TransactionStatus.refunded:
        return 'Refunded';
      case TransactionStatus.timedOut:
        return 'Timed Out';
    }
  }
}
