# SafePay Production Release Checklist

This checklist ensures judges can install and use SafePay without any local backend setup.

## 1. Deploy Firebase Services

1. Ensure Firebase project is `safepay-28ea2`.
2. Deploy Firestore rules:
   ```bash
   firebase deploy --only firestore:rules
   ```
3. Do NOT deploy Cloud Functions (Blaze not allowed).
4. Deploy Express backend to Render free tier:
   ```bash
   cd server
   npm install
   npm run start
   ```
5. Verify backend health endpoint:
   - `https://YOUR_RENDER_SERVICE.onrender.com/health`

## 2. Build Android Release APK/AAB

1. Ensure Flutter dependencies are up to date:
   ```bash
   flutter pub get
   ```
2. Configure Android release signing:
   - Copy `android/key.properties.example` to `android/key.properties`.
   - Create/import a release keystore (for example: `android/keystore/upload-keystore.jks`).
   - Fill all values in `android/key.properties`.
3. Register release SHA fingerprints in Firebase:
   ```bash
   keytool -list -v -keystore android/keystore/upload-keystore.jks -alias upload
   ```
   - Add BOTH SHA-1 and SHA-256 to your Android app in Firebase.
   - Re-download and replace `android/app/google-services.json`.
4. Verify App Check for Android uses Play Integrity in production.
5. Build release APK:
   ```bash
   flutter build apk --release
   ```
6. Optional Play Store bundle:
   ```bash
   flutter build appbundle --release
   ```

## 3. Distribute to Judges

### Option A: Direct APK (fastest for hackathon)
- Share file: `build/app/outputs/flutter-apk/app-release.apk`
- Share installation instructions (Allow unknown apps once).

### Option B: Firebase App Distribution
1. Add Firebase App Distribution plugin/CLI.
2. Upload release APK to tester group.
3. Send invite links to judges.

## 4. Mandatory Demo Data Setup

Before demo, create at least:
- 2 personal user accounts
- 1 merchant account
- wallet balances in `wallets` collection
- few historical transactions for assistant insights

## 5. Smoke Test (On Fresh Device)

1. Register new user.
2. Top up wallet.
3. Send payment with suspicious note:
   - Verify scam warning appears.
   - Verify high-risk extra verification appears when triggered.
4. Open receiver and approve/reject.
5. Use AI Coach and ask:
   - "How much did I spend this month?"
   - "Where did most of my money go?"
6. Confirm notifications and transaction history sync.

## 6. Rollback Plan

- Keep previous APK as fallback.
- Keep previous backend deployment tag.
- If backend AI endpoint is slow/down, app falls back to local AI heuristics automatically.
