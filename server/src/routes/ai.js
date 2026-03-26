const express = require('express');
const { z } = require('zod');

const { validate } = require('../middleware/validation');
const { evaluateTransactionRisk } = require('../../../ai/risk-engine');
const { detectScamMessage } = require('../../../ai/scam-engine');
const { evaluateBehavior } = require('../../../ai/behavior-engine');
const { summarizeAssistant } = require('../../../ai/assistant-engine');

const router = express.Router();

router.post(
  '/risk/transaction',
  validate(
    z.object({
      body: z.object({
        amount: z.number().nonnegative(),
        known_receiver: z.boolean().optional(),
        tx_count_last_24h: z.number().int().nonnegative().optional(),
        device_mismatch: z.boolean().optional(),
        location_mismatch: z.boolean().optional(),
        unusual_spending_pattern: z.boolean().optional(),
        historical_amounts: z.array(z.number().nonnegative()).optional(),
      }).passthrough(),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  (req, res) => {
    const result = evaluateTransactionRisk(req.validated.body);
    res.json(result);
  }
);

router.post(
  '/detect/scam',
  validate(
    z.object({
      body: z.object({ message: z.string().default('') }),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  (req, res) => {
    const result = detectScamMessage(req.validated.body.message);
    res.json(result);
  }
);

router.post(
  '/behavior/anomaly',
  validate(
    z.object({
      body: z.object({
        amount: z.number().nonnegative(),
        known_receiver: z.boolean().optional(),
        tx_hour: z.number().int().min(0).max(23).optional(),
        user_profile: z.record(z.any()).optional(),
      }).passthrough(),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  (req, res) => {
    const result = evaluateBehavior(req.validated.body);
    res.json(result);
  }
);

router.post(
  '/assistant/summary',
  validate(
    z.object({
      body: z.object({
        question: z.string().default(''),
        transactions: z.array(z.record(z.any())).default([]),
      }).passthrough(),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  (req, res) => {
    const { question, transactions } = req.validated.body;
    const result = summarizeAssistant(question, transactions);
    res.json(result);
  }
);

module.exports = router;
