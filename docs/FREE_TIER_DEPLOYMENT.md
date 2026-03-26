# SafePay Free-Tier Deployment Guide

This guide keeps SafePay fully functional without Firebase Blaze billing.

## 1. Services Matrix (Free)

- Client: Vercel (Flutter Web static hosting)
- Backend: Render free web service (`/ai-backend`)
- Auth + DB: Firebase Auth + Firestore Spark
- AI: deterministic backend routes in `/ai-backend` (no paid API)

## 2. Backend Deployment (Render)

1. Push repository to GitHub.
2. In Render, create a new Web Service from this repo.
3. Set root directory to `ai-backend`.
4. Build command: `npm ci`
5. Start command: `npm start`
6. Add environment variables from `ai-backend/.env.example`.
7. Deploy and verify `GET /health`.

## 3. Frontend Deployment (Vercel)

1. Build Flutter web locally:
   ```bash
   flutter build web --release --dart-define=SAFEPAY_API_BASE_URL=https://YOUR_RENDER_URL/api --dart-define=SAFEPAY_MOBILE_API_KEY=YOUR_MOBILE_API_KEY
   ```
2. Deploy `build/web` to Vercel as a static site.
3. Confirm app calls `https://YOUR_RENDER_URL/api/*` endpoints.

## 4. Firebase Spark Safe Checklist

- Do not deploy Cloud Functions.
- Keep Firestore indexes and reads/writes within Spark quota.
- Prefer Firestore batching and limited query windows (`limit()` already used).
- Monitor Firebase usage dashboard weekly.

## 5. Security Checklist

- Strong `JWT_SECRET` in Render env vars.
- Strong `MOBILE_API_KEY` in Render env vars and client define.
- CORS allowlist set to Vercel domain only.
- Rate limiting enabled (`/api` routes).
- Input validation enabled via Zod.
- Secrets only in environment variables.
