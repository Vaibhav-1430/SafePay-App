# Deployment Notes

- Frontend: Vercel (Flutter web build output)
- Backend: Render free web service using `/server`
- Database: Firestore Spark (or Supabase free tier)
- AI: local deterministic modules in `/ai` consumed by backend APIs

Keep all secrets in host environment variables. Never commit private keys.
