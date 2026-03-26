# SafePay AI Upgrade Architecture

## 1. Updated Architecture

### Components
- Flutter App (SafePay frontend)
- Firebase Auth + Firestore + FCM
- Node.js + Express backend (`/server`)
- Modular AI engines (`/ai`) with deterministic scoring

### Data/Decision Flow
1. User initiates payment in app.
2. App calls AI risk + behavior analysis.
3. Decision engine computes final risk score (0-1) and classifies:
   - Safe
   - Medium Risk
   - High Risk
4. If high risk:
   - Show warning
   - Require OTP simulation verification
   - Force consent/escrow flow and optional delay recommendation
5. Transaction is persisted in Firestore with AI fields.
6. Receiver gets payment request notification.
7. On receiver side, note/message is checked with scam detector and warning is shown if suspicious.
8. Smart assistant screen summarizes spending and answers user questions.

## 2. AI Modules Added

### Transaction Fraud Detection
- Endpoint: `POST /risk/transaction`
- Inputs:
  - amount
  - known/new receiver
  - frequency in last 24h
  - device/location mismatch flags
  - unusual spending pattern
  - historical amounts
- Output:
  - `risk_score` (0-1)
  - class (`Safe`, `Medium Risk`, `High Risk`)
  - trigger reasons
  - verification + delay recommendation flags

### Scam Message Detection
- Endpoint: `POST /detect/scam`
- NLP logic:
  - TF-IDF + Logistic Regression classifier
  - scam phrase pattern checks
- Output:
  - scam probability
  - warning message
  - matched scam patterns

### Behavioral Security
- Endpoint: `POST /behavior/anomaly`
- Uses Isolation Forest + rules on:
  - unusual amount
  - unknown recipient
  - unusual transaction time
- Output:
  - anomaly score
  - anomaly boolean
  - action (`allow` or `trigger_verification`)

### Smart Financial Assistant
- Endpoint: `POST /assistant/summary`
- Uses transaction history + category inference from notes.
- Answers questions like:
  - "How much did I spend this month?"
  - "Where did most of my money go?"

## 3. Firebase API Gateway

Express backend exposes AI routes:
- `POST /api/ai/risk/transaction`
- `POST /api/ai/detect/scam`
- `POST /api/ai/behavior/anomaly`
- `POST /api/ai/assistant/summary`
- `GET /health`

## 4. Flutter Integration Points

### Added Service
- `lib/services/ai_security_service.dart`

### Updated Payment Flow
- `TransactionService.initiatePayment(...)` now:
  - computes historical context
  - calls AI transaction risk + behavior analysis
  - merges with local risk engine
  - enforces high-risk extra verification
  - stores AI fields in transaction document

### Updated Screens
- `SendMoneyScreen`
  - scam detection for note text
  - high-risk verification OTP simulation before final submission
- `PaymentApprovalScreen`
  - incoming note scam detection warning card
- `HomeScreen`
  - AI Coach quick action
- New: `AiAssistantScreen`

## 5. Local Run Steps

SafePay now defaults to production Firebase Functions endpoint (`safepay-28ea2`) and embedded fallbacks, so the app can still demonstrate AI behavior even if remote AI APIs are temporarily unreachable.

### Backend server
```bash
cd server
npm install
copy .env.example .env
npm run dev
```

### Flutter app (with server URL)
```bash
flutter pub get
flutter run --dart-define=SAFEPAY_API_BASE_URL=http://10.0.2.2:8081/api --dart-define=SAFEPAY_MOBILE_API_KEY=replace-with-strong-random-key
```

## 6. Live Demo Script (2-3 minutes)

1. Open Home and show AI Coach entry.
2. Start Send Money:
   - Enter unknown recipient + high amount + suspicious note.
3. Show scam warning prompt in send flow.
4. Proceed and show high-risk verification requirement (OTP simulation).
5. Complete verification and submit payment.
6. Open receiver approval page and show:
   - AI risk badge
   - scam message warning for note
7. Approve transaction and complete sender PIN flow.
8. Open AI Financial Assistant:
   - Ask: "How much did I spend this month?"
   - Ask: "Where did most of my money go?"
9. End with architecture slide: App -> Express API -> AI modules -> decision gate.
