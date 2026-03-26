import 'package:cloud_firestore/cloud_firestore.dart';

class TrustedContact {
  final String id;
  final String ownerUserId;
  final String contactUserId;
  final String contactName;
  final String contactUpiId;
  final String? contactPhone;
  final DateTime addedAt;

  TrustedContact({
    required this.id,
    required this.ownerUserId,
    required this.contactUserId,
    required this.contactName,
    required this.contactUpiId,
    this.contactPhone,
    required this.addedAt,
  });

  factory TrustedContact.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrustedContact(
      id: doc.id,
      ownerUserId: data['ownerUserId'] ?? '',
      contactUserId: data['contactUserId'] ?? '',
      contactName: data['contactName'] ?? '',
      contactUpiId: data['contactUpiId'] ?? '',
      contactPhone: data['contactPhone'],
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerUserId': ownerUserId,
      'contactUserId': contactUserId,
      'contactName': contactName,
      'contactUpiId': contactUpiId,
      'contactPhone': contactPhone,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }
}

class MerchantSettings {
  final String merchantId;
  final bool fastMode;
  final double? approvalThreshold;
  final bool autoAcceptBelow;

  MerchantSettings({
    required this.merchantId,
    this.fastMode = true,
    this.approvalThreshold,
    this.autoAcceptBelow = false,
  });

  factory MerchantSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MerchantSettings(
      merchantId: doc.id,
      fastMode: data['fastMode'] ?? true,
      approvalThreshold: (data['approvalThreshold'] as num?)?.toDouble(),
      autoAcceptBelow: data['autoAcceptBelow'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchantId': merchantId,
      'fastMode': fastMode,
      'approvalThreshold': approvalThreshold,
      'autoAcceptBelow': autoAcceptBelow,
    };
  }

  MerchantSettings copyWith({
    bool? fastMode,
    double? approvalThreshold,
    bool? autoAcceptBelow,
  }) {
    return MerchantSettings(
      merchantId: merchantId,
      fastMode: fastMode ?? this.fastMode,
      approvalThreshold: approvalThreshold ?? this.approvalThreshold,
      autoAcceptBelow: autoAcceptBelow ?? this.autoAcceptBelow,
    );
  }
}
