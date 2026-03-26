# SafePay Server (Free Tier)

Express backend that replaces Firebase Cloud Functions for Spark-compatible deployments.

## Features
- JWT auth endpoints
- Payment verification + transaction log APIs
- AI APIs (`/api/ai/*`) used by Flutter
- Firestore persistence via Firebase Admin (optional)
- Secure defaults: helmet, CORS allowlist, rate limiting, request validation

## Run Locally

```bash
cd server
npm install
copy .env.example .env
npm run dev
```

Health check: `GET http://localhost:8080/health`

## Deploy Free
- Backend: Render free web service
- Database: Firestore Spark or Supabase (optional)

Set environment variables from `.env.example` in Render dashboard.
