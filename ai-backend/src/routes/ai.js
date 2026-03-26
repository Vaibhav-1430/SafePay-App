const express = require('express');
const { z } = require('zod');
const { validate } = require('../middleware/validation');
const { analyzeTransaction, securityCheck } = require('../services/risk');
const { chatAssistant } = require('../services/assistant');

const router = express.Router();

const txSchema = z.object({
  body: z.object({
    amount: z.number().positive(),
    known_receiver: z.boolean().optional(),
    tx_count_last_24h: z.number().int().nonnegative().optional(),
    unusual_spending_pattern: z.boolean().optional(),
    historical_amounts: z.array(z.number().nonnegative()).optional(),
    is_new_merchant: z.boolean().optional(),
    tx_hour: z.number().int().min(0).max(23).optional(),
  }).passthrough(),
  params: z.object({}).optional(),
  query: z.object({}).optional(),
});

router.post('/analyze-transaction', validate(txSchema), (req, res) => {
  const data = analyzeTransaction(req.validated.body);
  return res.json({ ok: true, data });
});

router.post('/security-check', validate(txSchema), (req, res) => {
  const data = securityCheck(req.validated.body);
  return res.json({ ok: true, data });
});

router.post(
  '/chat-assistant',
  validate(
    z.object({
      body: z.object({
        question: z.string().default(''),
        transactions: z.array(z.record(z.any())).default([]),
      }).passthrough(),
      params: z.object({}).optional(),
      query: z.object({}).optional(),
    })
  ),
  (req, res) => {
    const { question, transactions } = req.validated.body;
    const data = chatAssistant(question, transactions);
    return res.json({ ok: true, data });
  }
);

module.exports = router;
