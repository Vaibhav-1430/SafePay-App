# SafePay Production Upgrade Guide

This guide documents the production implementation added to this repository and how to deploy it for real users.

## 1. What Was Implemented

### Backend (Node.js API)

Implemented in:
- `ai-backend/src/config/firebase.js`
- `ai-backend/src/services/paymentsEngine.js`
- `ai-backend/src/services/push.js`
- `ai-backend/src/routes/payments.js`

Features:
- Firestore-backed escrow payment engine (no in-memory state)
- Atomic wallet updates using Firestore transactions
- Idempotent transaction creation (`idempotency_keys`)
- Fraud scoring (`riskScore` in 0..1 and 0..100 variants)
- Audit-chain style transaction logs with hash linkage
- FCM push to receiver/sender on payment state transitions
- Dashboard aggregation endpoint for risk analytics

### Flutter Auth + Notification hardening

Implemented in:
- `lib/services/auth_service.dart`
- `lib/services/notification_service.dart`

Features:
- OTP request throttling (attempt window + cooldown)
- OTP verification failure lockout protection
- Device binding (`users/{uid}.deviceBinding`)
- FCM token refresh listener and persistence

### Security and Data Layer

Implemented in:
- `firestore.rules`
- `firestore.indexes.json`

Features:
- Backend-owned write controls for wallets/transactions/payment_requests
- Least-privilege user + notification update rules
- Additional composite indexes for transaction logs and payment requests

## 2. Payment Flow (Escrow)

### sendPayment (`POST /api/payments/transactions/request`)

1. Validate payload
2. Compute fraud risk
3. Firestore transaction:
   - Debit sender `wallets/{senderId}.balance`
   - Credit sender `wallets/{senderId}.reservedBalance`
   - Create `transactions/{txId}` in `pending`
   - Create `payment_requests/{txId}` in `pending`
   - Create `idempotency_keys/{senderId_txId}`
   - Append hash-linked record in `transaction_logs`
4. Push notification to receiver

### approvePayment (`POST /api/payments/{id}/approve`)

1. Validate receiver ownership and pending status
2. Firestore transaction:
   - Debit sender reserved
   - Credit receiver available balance
   - Mark transaction as `completed`
   - Append audit log block
3. Push notification to sender

### rejectPayment (`POST /api/payments/{id}/reject`)

1. Validate receiver ownership and pending status
2. Firestore transaction:
   - Move sender reserved -> sender available (refund)
   - Mark transaction as `rejected`
   - Append audit log block
3. Push notification to sender

## 3. Firebase / Firestore Structure

Collections used in production path:

### users
- uid
- name
- phone
- fcmToken
- deviceToken
- deviceBinding.activeDeviceId
- deviceBinding.platform
- deviceBinding.lastSeenAt

### wallets
- balance (available)
- reservedBalance
- updatedAt

### payment_requests
- senderId
- receiverId
- amount
- status (`pending|completed|rejected|refunded`)
- riskScore01
- riskScore
- riskLevel
- riskFlags
- createdAt
- updatedAt

### transactions
- same core fields as payment_requests
- audit fields: `blockIndex`, `previousHash`, `hash`

### transaction_logs
- blockIndex
- eventType
- transactionId
- senderId
- receiverId
- amount
- status
- riskLevel
- riskScore
- previousHash
- hash
- createdAt

### idempotency_keys
- senderId
- transactionId
- createdAt

### system/audit_meta
- blockIndex
- lastHash
- updatedAt

## 4. Setup Steps (Exact)

## 4A. Firebase Phone Auth Authorization Fix (Android)

Use this checklist to fix the "This build is not authorized for Firebase Phone Auth" error.

1. Verify package name in app:
  - `android/app/build.gradle.kts` uses `com.safepay.safepay`.
2. Verify package in Firebase config:
  - `android/app/google-services.json` has `package_name: com.safepay.safepay`.
3. Add Android SHA fingerprints in Firebase Console for this app:
  - SHA-1: `2B:46:42:CC:85:48:CB:78:6A:5C:8A:B2:23:A5:86:E1:62:FA:2D:1B`
  - SHA-256: `3F:0E:A1:79:7F:15:0D:93:D2:6F:F0:72:CB:80:F3:E4:A8:70:79:43:7E:29:32:A3:70:50:AC:0A:74:68:4F:F0`
4. Re-download Firebase Android config and replace:
  - `android/app/google-services.json`
5. Firebase Console > Authentication > Sign-in method:
  - Enable `Phone` provider.
6. Google Cloud Console:
  - Enable `Play Integrity API` for project `safepay-28ea2`.
7. Firebase Console > App Check > Android app:
  - Provider: `Play Integrity`.
  - For local debug, add debug token when prompted in logs.
8. Clean + rebuild after config changes:
  - `flutter clean`
  - `flutter pub get`
  - `cd android && gradlew.bat clean && cd ..`
  - `flutter run`

Notes:
- If using a release keystore, add that keystore's SHA-1 and SHA-256 as well.
- Mismatched SHA or package name is the most common root cause of authorization failure.

## Backend Setup

1. Go to `ai-backend`.
2. Install dependencies:
   - `npm install`
3. Set environment variables:
   - `NODE_ENV=production`
   - `PORT=8081`
   - `MOBILE_API_KEY=<strong-random-secret>`
   - `ALLOWED_ORIGINS=<comma-separated-origins>`
   - `FIREBASE_PROJECT_ID=<id>`
   - `FIREBASE_CLIENT_EMAIL=<service-account-email>`
   - `FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"`
4. Start backend:
   - `npm start`

## Firestore Rules / Indexes

1. Deploy rules:
   - `firebase deploy --only firestore:rules`
2. Deploy indexes:
   - `firebase deploy --only firestore:indexes`

## Flutter Setup

1. Ensure backend base URL and API key are set in app constants/env.
2. On login success, call notification token save flow (already implemented in service).
3. Ensure Firebase Messaging background handler remains configured in `main.dart`.

## 5. API Contracts

### Request payment
`POST /api/payments/transactions/request`

Body:
```json
{
  "clientTransactionId": "optional-uuid",
  "senderId": "uid_sender",
  "receiverId": "uid_receiver",
  "senderName": "Alice",
  "receiverName": "Bob",
  "senderUpiId": "alice@safepay",
  "receiverUpiId": "bob@safepay",
  "amount": 1200,
  "note": "Dinner",
  "delayMinutes": 0
}
```

### Approve payment
`POST /api/payments/transactions/{transactionId}/approve`

Body:
```json
{
  "receiverId": "uid_receiver",
  "addToTrustedContacts": true
}
```

### Reject payment
`POST /api/payments/transactions/{transactionId}/reject`

Body:
```json
{
  "receiverId": "uid_receiver",
  "reason": "Unknown request"
}
```

## 6. Debug Checklist

- Verify `x-api-key` header is present from Flutter requests.
- Verify backend can initialize Firebase Admin (service account env vars).
- Verify sender wallet has both `balance` and `reservedBalance` fields.
- Verify user docs contain `fcmToken` after login.
- Verify required Firestore indexes are built (no missing-index runtime errors).
- Verify transaction status changes in both `transactions` and `payment_requests`.
- Verify `transaction_logs` entries append on each state change.
- Verify risk dashboard endpoint returns data under `data` object.

## 7. Common Errors and Fixes

- `Server API key is not configured`
  - Set `MOBILE_API_KEY` in backend environment.

- `PERMISSION_DENIED` from Firestore writes in app
  - Expected for direct wallet/transaction writes after hardening; route all critical writes through backend APIs.

- `Wallet missing`
  - Create `wallets/{uid}` for each onboarded user.

- `Insufficient balance`
  - Sender wallet `balance` is below amount.

- `Release delay active until ...`
  - Payment has delay lock; approve after `releaseAt`.

- Missing index error
  - Deploy `firestore.indexes.json`.

- FCM not delivered
  - Check `users/{uid}.fcmToken`, OS notification permission, and token freshness.

## 8. Testing Matrix

### Core Success
- Send payment with enough balance
- Approve pending payment
- Reject pending payment
- Emergency cancel within 90s

### Security / Abuse
- OTP send > max window attempts
- OTP verify wrong code repeatedly
- Attempt approval by non-receiver
- Attempt reject by non-receiver
- Attempt create payment where sender==receiver

### Consistency / Idempotency
- Repeat same `clientTransactionId`
- Double-tap approve endpoint
- Approve and reject race on same tx

### Failure Scenarios
- Backend timeout after reserve step (must remain atomic)
- FCM unavailable (payment still persists)
- Missing user wallet docs

## 9. Deployment Steps

1. Deploy Firestore rules and indexes.
2. Deploy backend with production env vars.
3. Run smoke tests against:
   - `/health`
   - `/api/payments/transactions/request`
   - `/api/payments/dashboard/{uid}`
4. Roll out Flutter app pointing to production backend URL.
5. Monitor logs for:
   - reject reasons
   - idempotency collisions
   - FCM token cleanup

## 10. Operational Recommendations

- Add Redis for backend-side rate limiting and idempotency cache acceleration.
- Add App Check verification from mobile clients.
- Add KMS/Secret Manager for key management.
- Add scheduled reconciliation job to verify wallet invariants:
  - `sum(balance + reservedBalance)` consistency against ledger.
