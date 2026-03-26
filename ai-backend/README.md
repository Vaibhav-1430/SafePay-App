# SafePay Backend (Production Mode)

Production-grade backend for SafePay payment orchestration, escrow, fraud scoring, and notification dispatch.

## Endpoints

- `GET /health`
- `POST /api/ai/analyze-transaction`
- `POST /api/ai/security-check`
- `POST /api/ai/chat-assistant`
- `POST /api/payments/verify`
- `POST /api/payments/transactions/request`
- `POST /api/payments/transactions/:transactionId/approve`
- `POST /api/payments/transactions/:transactionId/reject`
- `POST /api/payments/transactions/:transactionId/emergency-cancel`
- `GET /api/payments/transactions/history/:userId`
- `GET /api/payments/transactions/pending/:userId`
- `GET /api/payments/transactions/logs/:userId`
- `GET /api/payments/dashboard/:userId`

All `/api/*` routes require header `x-api-key`.

## Local Run

```bash
cd ai-backend
copy .env.example .env
npm install
npm run dev
```

## Render Deploy

1. Create Web Service from repo.
2. Set root directory to `ai-backend`.
3. Build command: `npm ci`
4. Start command: `npm start`
5. Add env vars:
   - `NODE_ENV=production`
   - `MOBILE_API_KEY=<strong-random-key>`
   - `ALLOWED_ORIGINS=https://your-netlify-site.netlify.app`
  - `FIREBASE_PROJECT_ID=<project-id>`
  - `FIREBASE_CLIENT_EMAIL=<service-account-client-email>`
  - `FIREBASE_PRIVATE_KEY=<service-account-private-key-with-\\n>`

## Response Shape

Success:

```json
{ "ok": true, "data": { } }
```

Error:

```json
{
  "ok": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed.",
    "details": []
  }
}
```

## Notes

- Payment state is persisted in Firestore collections: `transactions`, `payment_requests`, `transaction_logs`, and `idempotency_keys`.
- Wallet movement is atomic via Firestore transactions using `balance` and `reservedBalance` fields.
- FCM push is sent via Admin SDK using `users/{uid}.fcmToken` (fallback `deviceToken`).
