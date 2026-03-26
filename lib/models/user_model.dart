import 'package:cloud_firestore/cloud_firestore.dart';

enum UserType { personal, merchant }

enum MerchantType { shopkeeper, autoDriver, cab, streetVendor, other }

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserType userType;
  final String upiId;
  final String? profileImageUrl;
  final double reputationScore;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Merchant-specific fields
  final String? businessName;
  final MerchantType? merchantType;

  // PIN hash (stored securely)
  final String? upiPinHash;
  final DateTime? upiPinCreatedAt;
  final int? upiPinLength;

  // App lock PIN fields
  final String? appPinHash;
  final bool appPinSet;
  final DateTime? appPinCreatedAt;

  // ── Notification preferences ─────────────────────────────────────────
  /// When false, the backend / Cloud Function must NOT send FCM pushes
  /// for payment requests to this user.
  final bool notificationsEnabled;

  /// FCM device token for push notifications. Stored in Firestore as
  /// 'fcmToken' (aliased here as `deviceToken` for domain clarity).
  final String? deviceToken;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.userType,
    required this.upiId,
    this.profileImageUrl,
    this.reputationScore = 5.0,
    this.isVerified = false,
    required this.createdAt,
    this.updatedAt,
    this.businessName,
    this.merchantType,
    this.upiPinHash,
    this.upiPinCreatedAt,
    this.upiPinLength,
    this.appPinHash,
    this.appPinSet = false,
    this.appPinCreatedAt,
    this.notificationsEnabled = true,
    this.deviceToken,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromMap(data, uid: doc.id);
  }

  factory UserModel.fromMap(Map<String, dynamic> data, {required String uid}) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return UserModel(
      uid: uid,
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      userType: data['userType'] == 'merchant' ? UserType.merchant : UserType.personal,
      upiId: (data['upiId'] ?? '').toString(),
      profileImageUrl: data['profileImageUrl'] as String?,
      reputationScore: (data['reputationScore'] ?? 5.0).toDouble(),
      isVerified: data['isVerified'] == true,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseNullableDate(data['updatedAt']),
      businessName: data['businessName'] as String?,
      merchantType: data['merchantType'] != null
          ? MerchantType.values.firstWhere(
              (e) => e.name == data['merchantType'],
              orElse: () => MerchantType.other,
            )
          : null,
      upiPinHash: (data['upiPinHash'] ?? data['pinHash']) as String?,
      upiPinCreatedAt: parseNullableDate(data['upiPinCreatedAt']),
      upiPinLength: (data['upiPinLength'] as num?)?.toInt(),
      appPinHash: data['appPinHash'] as String?,
      appPinSet: data['appPinSet'] == true,
      appPinCreatedAt: parseNullableDate(data['appPinCreatedAt']),
      notificationsEnabled: data['notificationsEnabled'] != false,
      deviceToken: data['fcmToken'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'phoneNumber': phone,
      'phoneNormalized': phone,
      'userType': userType.name,
      'upiId': upiId,
      'profileImageUrl': profileImageUrl,
      'reputationScore': reputationScore,
      'isVerified': isVerified,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? createdAt),
      'businessName': businessName,
      'merchantType': merchantType?.name,
      // Keep both keys for backward compatibility with older app versions.
      'upiPinHash': upiPinHash,
      'pinHash': upiPinHash,
      'upiPinCreatedAt':
          upiPinCreatedAt != null ? Timestamp.fromDate(upiPinCreatedAt!) : null,
      'upiPinLength': upiPinLength,
        'appPinHash': appPinHash,
        'appPinSet': appPinSet,
        'appPinCreatedAt':
          appPinCreatedAt != null ? Timestamp.fromDate(appPinCreatedAt!) : null,
      'notificationsEnabled': notificationsEnabled,
      if (deviceToken != null) 'fcmToken': deviceToken,
    };
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'phoneNumber': phone,
      'phoneNormalized': phone,
      'userType': userType.name,
      'upiId': upiId,
      'profileImageUrl': profileImageUrl,
      'reputationScore': reputationScore,
      'isVerified': isVerified,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': (updatedAt ?? createdAt).toIso8601String(),
      'businessName': businessName,
      'merchantType': merchantType?.name,
      'upiPinHash': upiPinHash,
      'upiPinCreatedAt': upiPinCreatedAt?.toIso8601String(),
      'upiPinLength': upiPinLength,
      'appPinHash': appPinHash,
      'appPinSet': appPinSet,
      'appPinCreatedAt': appPinCreatedAt?.toIso8601String(),
      'notificationsEnabled': notificationsEnabled,
      if (deviceToken != null) 'fcmToken': deviceToken,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? upiId,
    String? profileImageUrl,
    double? reputationScore,
    bool? isVerified,
    String? businessName,
    MerchantType? merchantType,
    String? upiPinHash,
    DateTime? upiPinCreatedAt,
    int? upiPinLength,
    String? appPinHash,
    bool? appPinSet,
    DateTime? appPinCreatedAt,
    DateTime? updatedAt,
    bool? notificationsEnabled,
    String? deviceToken,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      userType: userType,
      upiId: upiId ?? this.upiId,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      reputationScore: reputationScore ?? this.reputationScore,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      businessName: businessName ?? this.businessName,
      merchantType: merchantType ?? this.merchantType,
      upiPinHash: upiPinHash ?? this.upiPinHash,
      upiPinCreatedAt: upiPinCreatedAt ?? this.upiPinCreatedAt,
      upiPinLength: upiPinLength ?? this.upiPinLength,
      appPinHash: appPinHash ?? this.appPinHash,
      appPinSet: appPinSet ?? this.appPinSet,
      appPinCreatedAt: appPinCreatedAt ?? this.appPinCreatedAt,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      deviceToken: deviceToken ?? this.deviceToken,
    );
  }

  String get phoneNumber => phone;

  String get displayName {
    final candidate = userType == UserType.merchant
        ? (businessName ?? name)
        : name;
    final trimmed = candidate.trim();
    return trimmed.isNotEmpty ? trimmed : 'User';
  }

  bool get isMerchant => userType == UserType.merchant;

  bool get hasUpiPin => (upiPinHash ?? '').isNotEmpty;
}
