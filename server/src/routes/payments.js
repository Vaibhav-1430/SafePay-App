const express = require('express');
const { z } = require('zod');

const { authenticateJwt } = require('../middleware/auth');
const { validate } = require('../middleware/validation');
const { evaluateTransactionRisk } = require('../../../ai/risk-engine');
const { logTransaction, listTransactionsForUser } = require('../services/store');
const { getFirestore } = require('../config/firebase');

const router = express.Router();

router.post(
  '/verify',
  authenticateJwt,
  validate(
    z.object({
      body: z.object({
        senderId: z.string().min(2),
        receiverId: z.string().min(2),
        amount: z.number().positive(),
        known_receiver: z.boolean().optional(),
        tx_count_last_24h: z.number().int().nonnegative().optional(),
        device_mismatch: z.boolean().optional(),
        location_mismatch: z.boolean().optional(),
        unusual_spending_pattern: z.boolean().optional(),
        historical_amounts: z.array(z.number()).optional(),
      }),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  (req, res) => {
    if (req.validated.body.senderId !== req.auth.uid) {
      return res.status(403).json({ error: 'Cannot verify payment for another sender' });
    }

    const risk = evaluateTransactionRisk(req.validated.body);
    return res.json({
      verified: true,
      ...risk,
      payment_gate: risk.require_extra_verification ? 'manual_review' : 'allow',
    });
  }
);

router.post(
  '/transactions/log',
  authenticateJwt,
  validate(
    z.object({
      body: z.object({
        transactionId: z.string().min(2),
        senderId: z.string().min(2),
        receiverId: z.string().min(2),
        amount: z.number().positive(),
        status: z.string().min(2),
        riskLevel: z.string().optional(),
        riskScore: z.number().optional(),
        note: z.string().optional(),
      }),
      query: z.object({}).optional(),
      params: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    const { senderId, receiverId } = req.validated.body;
    if (req.auth.uid !== senderId && req.auth.uid !== receiverId) {
      return res.status(403).json({ error: 'Not allowed to log this transaction' });
    }

    const entry = await logTransaction(req.validated.body);
    return res.status(201).json({ ok: true, entry });
  }
);

router.get('/transactions/:userId', authenticateJwt, async (req, res) => {
  const { userId } = req.params;
  if (req.auth.uid !== userId) {
    return res.status(403).json({ error: 'Cannot access another user transactions' });
  }

  const logs = await listTransactionsForUser(userId);
  return res.json({ count: logs.length, logs });
});

router.get('/dashboard/:userId', authenticateJwt, async (req, res) => {
  const { userId } = req.params;
  if (req.auth.uid !== userId) {
    return res.status(403).json({ error: 'Cannot access another user dashboard' });
  }

  try {
    const db = getFirestore();
    const snap = await db.collection('transactions')
      .where('senderId', '==', userId)
      .get();
      
    let totalTransactions = snap.size;
    let safeTransactions = 0;
    let mediumRiskTransactions = 0;
    let highRiskTransactions = 0;
    let preventedFraudCount = 0;
    let highRiskVolume = 0.0;
    
    snap.forEach(doc => {
      const data = doc.data();
      const level = data.riskLevel || 'Low Risk';
      if (level === 'Low Risk' || level === 'Safe') safeTransactions++;
      else if (level === 'Medium Risk') mediumRiskTransactions++;
      else if (level === 'High Risk') {
        highRiskTransactions++;
        highRiskVolume += (data.amount || 0);
        if (data.status === 'rejected' || data.status === 'refunded' || data.status === 'timedOut') {
          preventedFraudCount++;
        }
      }
    });

    res.json({
      data: {
        windowDays: 30,
        totalTransactions,
        safeTransactions,
        mediumRiskTransactions,
        highRiskTransactions,
        preventedFraudCount,
        highRiskVolume
      }
    });
  } catch (error) {
    console.error('Dashboard Error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard' });
  }
});

router.get('/transactions/logs/:userId', authenticateJwt, async (req, res) => {
  const { userId } = req.params;
  if (req.auth.uid !== userId) {
    return res.status(403).json({ error: 'Cannot access another user logs' });
  }
  const limitCount = parseInt(req.query.limit) || 40;
  
  try {
    const db = getFirestore();
    const snap = await db.collection('transactions')
      .where('senderId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limitCount)
      .get();
      
    const logs = [];
    snap.docs.forEach((doc, idx) => {
      const data = doc.data();
      logs.push({
        eventType: data.type === 'send' ? 'PAYMENT_SENT' : 'PAYMENT_RECEIVED',
        amount: data.amount,
        status: data.status,
        blockIndex: doc.id.substring(0, 6).toUpperCase(),
        hash: doc.id,
        previousHash: idx < snap.size - 1 ? snap.docs[idx+1].id : '00000000',
        createdAt: data.createdAt ? data.createdAt.toDate().toISOString() : new Date().toISOString()
      });
    });
    
    res.json({ data: logs });
  } catch (error) {
    console.error('Audit Logs Error:', error);
    res.status(500).json({ error: 'Failed to fetch logs' });
  }
});

module.exports = router;
