# SafePay 🛡️

**The Future of Secure Digital Payments**

SafePay is a revolutionary consent-based UPI payment system that gives you complete control over every transaction. Approve or reject incoming payments before they land — your money, your consent.

🌐 **Website**: [https://safepayy.netlify.app/](https://safepayy.netlify.app/)

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Enabled-FFCA28?logo=firebase)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🚨 The Problem

Current payment systems in India are exploitable:
- **₹2,145 Crore** lost to UPI fraud in India (2023-24)
- **67% increase** in phishing via payments
- **54% increase** in unauthorized transactions
- Anyone can push money to your UPI account without your knowledge, opening doors to phishing, fraud, and manipulation

### Common Fraud Patterns:
- 🎣 **Phishing via Unknown Transfers**: Fraudsters send small amounts to build "trust"
- 💸 **No Pre-Approval Mechanism**: Any UPI ID can push money without consent
- 🕵️ **Identity Spoofing**: Scammers impersonate known contacts
- 🔓 **No Recourse**: Victims are legally entangled even without initiating transactions

---

## ✨ Our Solution

SafePay introduces a **consent-first architecture** where every incoming payment requires your explicit approval.

### How It Works:

1. **📤 Request Initiated**: Sender enters your SafePay ID
2. **🔔 Approval Alert**: You receive instant notification with full sender details
3. **👆 Approve or Reject**: One tap to accept or reject
4. **✅ Secure & Done**: Money moves only after your approval

---

## 🎯 Key Features

### 🤝 Consent-Based Payments
World-first incoming payment consent layer. Every transfer requires your active approval before processing.

### 👥 Trusted Contacts
Whitelist trusted contacts for auto-approval. All others go through consent flow — smart and friction-free.

### 🛡️ Fraud Protection Layer
Behavioral analysis flags suspicious senders before you open the notification. Firebase-powered security.

### 📊 Smart Transaction Logs
Every approved, rejected, and blocked transaction logged with timestamps, sender identity, and device info.

### ⚡ Instant Notifications
Sub-second push notifications via Firebase Cloud Messaging. Full sender context on your lock screen.

### 💰 Secure Wallet System
Encrypted wallet with OTP, biometric, and session-based tokens for multi-layer protection.

---

## 🛠️ Technology Stack

### Frontend
- **Flutter**: Cross-platform UI for native iOS & Android
- **Dart**: Strongly-typed language powering all app logic
- **Provider**: State management
- **Go Router**: Navigation

### Backend & Database
- **Express API (`/ai-backend`)**: Free-tier REST backend for AI and payment verification
- **Cloud Firestore**: NoSQL database with real-time listeners
- **Firebase Auth**: Multi-provider authentication
- **Firebase Messaging**: Push notifications
- **Modular AI (`/ai`)**: Fraud, scam, behavior, and assistant modules

### Security
- **OTP Verification**: Time-sensitive SMS verification
- **AES-256 Encryption**: All transaction data encrypted
- **Biometric Auth**: Local authentication support
- **Secure Auth Flows**: JWT tokens and session management

### UI/UX Libraries
- Google Fonts
- Lottie Animations
- Shimmer Effects
- Cached Network Images
- QR Code Scanner & Generator

---

## 📱 App Features

### Core Functionality
- ✅ Consent-based incoming payment approval
- 📤 Send money via UPI ID or phone number
- 📷 QR code scanning and generation
- 👥 Contact management with trusted contacts
- 💳 Secure wallet with balance tracking
- 📊 Transaction history with date grouping
- 🔔 Real-time push notifications
- 🔐 Biometric and PIN authentication

### Security Features
- ⚠️ Unknown sender warnings
- 🛡️ Fraud signal detection
- 📝 Complete audit trail
- 🔒 Encrypted data storage
- 🔐 Multi-factor authentication
- 📱 Device binding

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0 <4.0.0)
- Dart SDK
- Node.js 18+
- Android Studio / Xcode
- Firebase account

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/safepay.git
cd safepay
```

2. **Install dependencies**
```bash
flutter pub get
cd server && npm install
```

3. **Configure Firebase**
   - Add your `google-services.json` to `android/app/`
   - Add your `GoogleService-Info.plist` to `ios/Runner/`
   - Update `.firebaserc` with your Firebase project ID

4. **Run backend (free-tier replacement for Cloud Functions)**
```bash
cd ai-backend
copy .env.example .env
npm run dev
```

5. **Run the app**
```bash
flutter run --dart-define=SAFEPAY_API_BASE_URL=http://10.0.2.2:8081/api --dart-define=SAFEPAY_MOBILE_API_KEY=replace-with-strong-random-key
```

---

## 📂 Project Structure

```
safepay/
├── ai-backend/                   # Node.js + Express AI + payments backend
│   ├── src/routes/               # AI and payment verification APIs
│   └── src/middleware/           # Security, validation, API-key auth
├── ai/                           # Modular AI/risk engines
├── config/                       # Environment templates
├── utils/                        # Deployment and ops notes
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/                   # Data models
│   ├── providers/                # Provider state containers
│   ├── screens/                  # UI screens
│   ├── widgets/                  # Reusable widgets
│   ├── services/                 # Firebase + backend API services
│   └── utils/                    # Helper functions
├── assets/
│   ├── images/                   # Image assets
│   ├── animations/               # Lottie animations
│   └── icons/                    # App icons
├── android/                      # Android native code
├── ios/                          # iOS native code
└── pubspec.yaml                  # Dependencies
```

---

## 🔐 Security Architecture

SafePay implements multiple security layers:

1. **Consent Layer**: No incoming payment without explicit approval
2. **Encryption**: AES-256 encryption for all sensitive data
3. **Authentication**: Multi-factor authentication (OTP + Biometric)
4. **Fraud Detection**: Real-time behavioral analysis
5. **Session Management**: Secure token-based sessions
6. **Device Binding**: Transactions tied to verified devices

---

## 🌍 Social Impact

### Protecting Millions from Digital Fraud

- **🏘️ Rural & Semi-Urban Users**: Simple consent UI empowers first-time digital payment users
- **👴 Senior Citizen Safety**: Mandatory consent prevents exploitation of elderly users
- **🏛️ RBI Alignment**: Supports RBI's push for safer digital transactions

### Real Fraud Cases SafePay Prevents:
- Prize scams
- Refund fraud
- Identity theft
- Investment scams
- Money mule schemes
- QR phishing

---

## 🗺️ Roadmap

### Phase 1 (Current)
✅ Consent-based payment foundation
✅ Trusted contacts system
✅ Fraud flagging
✅ Secure wallet

### Phase 2 (Q3 2026)
✅ AI-powered fraud detection engine
✅ Scam message detection + behavioral anomaly checks
✅ Smart Financial Assistant (monthly spend insights)

---

## 🤖 AI Upgrade (Hackathon Build)

SafePay now includes an AI security + assistant stack with four modules:

- AI Fraud Detection for every transaction
- AI Scam Message Detection for suspicious payment messages
- AI Behavioral Security for anomaly-based verification
- AI Smart Financial Assistant for spending insights

Architecture and implementation guide:

- See `docs/AI_UPGRADE.md` for full flow, setup, APIs, and demo script.
- See `docs/PRODUCTION_RELEASE_CHECKLIST.md` for no-local judge-ready deployment and distribution steps.

### Phase 3 (Q4 2026)
📅 Secure escrow payments
📅 Smart vault for buyer-seller protection

### Phase 4 (2027)
📅 Advanced risk scoring
📅 Public SafePay Risk Score API

### Phase 5 (2027+)
📅 Global expansion
📅 UPI 2.0 integration
📅 Banking partnerships

---

## 👥 Team

**Vaibhav Kumar Yadav** - Team Lead • Full Stack Developer  
Visionary behind SafePay's consent-based architecture. Leads product strategy, Flutter development, and Firebase backend engineering.

**Nandini Upadhyay** - Team Lead • UI/UX & Security Design  
Drives SafePay's user experience and security design. Ensures complex consent flows feel intuitive and accessible for all users.

**Ashutosh Kumar** - Research & Testing
Conducts product research and market analysis. Validates features against real fraud scenarios and ensures quality through comprehensive testing.


---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 📞 Contact

- 🌐 Website: [https://safepayy.netlify.app/](https://safepayy.netlify.app/)
- 📧 Email: [yadavvaibhav688@gmail.com](mailto:yadavvaibhav688@gmail.com)

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase for robust backend infrastructure
- The open-source community for invaluable packages
- RBI for driving digital payment security initiatives

---

**Made with ❤️ in India**

*SafePay - Your money moves only when you say so.*
