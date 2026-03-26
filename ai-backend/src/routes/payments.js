const express = require('express');
const { z } = require('zod');

const { validate } = require('../middleware/validation');
const {
  sendPayment,
  approvePayment,
  rejectPayment,
  emergencyCancel,
  fetchHistory,
  fetchPending,
  fetchLogs,
  fetchDashboard,
  verifyRisk,
} = require('../services/paymentsEngine');
const { sendPushToUser } = require('../services/push');

const router = express.Router();

const MAX_DELAY_MINUTES = 60;

function mapErrorToStatus(error) {
  const msg = String(error && error.message ? error.message : 'Request failed');
  if (msg.includes('not found')) return 404;
  if (msg.includes('Only receiver') || msg.includes('Only sender')) return 403;
  if (
    msg.includes('Insufficient balance') ||
    msg.includes('cannot be cancelled') ||
    msg.includes('window has expired') ||
    msg.includes('Release delay active')
  ) {
    return 409;
  }
  if (msg.includes('cannot be the same') || msg.includes('missing')) return 400;
  return 500;
}

function errorResponse(res, error) {
  const message = String(error && error.message ? error.message : 'Internal error');
  const status = mapErrorToStatus(error);
  return res.status(status).json({
    ok: false,
    error: {
      message,
    },
  });
}

router.post(
  '/transactions/request',
  validate(
    z.object({
      body: z.object({
        clientTransactionId: z.string().min(1).optional(),
        senderId: z.string().min(1),
        receiverId: z.string().min(1),
        senderName: z.string().optional(),
        receiverName: z.string().optional(),
        senderUpiId: z.string().optional(),
        receiverUpiId: z.string().optional(),
        amount: z.number().positive(),
        note: z.string().nullable().optional(),
        delayMinutes: z.number().int().min(0).max(MAX_DELAY_MINUTES).optional(),
      }),
      params: z.object({}).optional(),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const payload = req.validated.body;
      const tx = await sendPayment({
        clientTransactionId: payload.clientTransactionId,
        senderId: payload.senderId,
        receiverId: payload.receiverId,
        senderName: payload.senderName,
        receiverName: payload.receiverName,
        senderUpiId: payload.senderUpiId,
        receiverUpiId: payload.receiverUpiId,
        amount: payload.amount,
        note: payload.note,
        delayMinutes: payload.delayMinutes,
      });

      await sendPushToUser({
        userId: tx.receiverId,
        title: 'New payment request',
        body: `${tx.senderName} requested INR ${Math.round(tx.amount)} from you`,
        data: {
          type: 'payment_request',
          transactionId: tx.transactionId,
          senderId: tx.senderId,
          senderName: tx.senderName,
          receiverId: tx.receiverId,
          amount: tx.amount,
          riskLevel: tx.riskLevel,
        },
      });

      return res.status(201).json({ ok: true, data: tx });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/send',
  validate(
    z.object({
      body: z.object({
        clientTransactionId: z.string().min(1).optional(),
        senderId: z.string().min(1),
        receiverId: z.string().min(1),
        senderName: z.string().optional(),
        receiverName: z.string().optional(),
        senderUpiId: z.string().optional(),
        receiverUpiId: z.string().optional(),
        amount: z.number().positive(),
        note: z.string().nullable().optional(),
        delayMinutes: z.number().int().min(0).max(MAX_DELAY_MINUTES).optional(),
      }),
      params: z.object({}).optional(),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const payload = req.validated.body;
      const tx = await sendPayment({
        clientTransactionId: payload.clientTransactionId,
        senderId: payload.senderId,
        receiverId: payload.receiverId,
        senderName: payload.senderName,
        receiverName: payload.receiverName,
        senderUpiId: payload.senderUpiId,
        receiverUpiId: payload.receiverUpiId,
        amount: payload.amount,
        note: payload.note,
        delayMinutes: payload.delayMinutes,
      });

      await sendPushToUser({
        userId: tx.receiverId,
        title: 'New payment request',
        body: `${tx.senderName} requested INR ${Math.round(tx.amount)} from you`,
        data: {
          type: 'payment_request',
          transactionId: tx.transactionId,
          senderId: tx.senderId,
          senderName: tx.senderName,
          receiverId: tx.receiverId,
          amount: tx.amount,
          riskLevel: tx.riskLevel,
        },
      });

      return res.status(201).json({ ok: true, data: tx });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/transactions/:transactionId/approve',
  validate(
    z.object({
      params: z.object({ transactionId: z.string().min(1) }),
      body: z.object({
        receiverId: z.string().min(1),
        addToTrustedContacts: z.boolean().optional(),
      }),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { transactionId } = req.validated.params;
      const { receiverId, addToTrustedContacts = false } = req.validated.body;

      const tx = await approvePayment({
        transactionId,
        receiverId,
        addToTrustedContacts,
      });

      await sendPushToUser({
        userId: tx.senderId,
        title: 'Payment approved',
        body: `${tx.receiverName} approved your payment request`,
        data: {
          type: 'payment_approved',
          transactionId: tx.transactionId,
        },
      });

      return res.json({
        ok: true,
        data: {
          transaction: tx,
          addToTrustedContacts,
        },
      });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/transactions/:transactionId/reject',
  validate(
    z.object({
      params: z.object({ transactionId: z.string().min(1) }),
      body: z.object({
        receiverId: z.string().min(1),
        reason: z.string().optional(),
      }),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { transactionId } = req.validated.params;
      const { receiverId, reason } = req.validated.body;

      const tx = await rejectPayment({
        transactionId,
        receiverId,
        reason,
      });

      await sendPushToUser({
        userId: tx.senderId,
        title: 'Payment rejected',
        body: `${tx.receiverName} rejected your payment request. Amount refunded.`,
        data: {
          type: 'payment_rejected',
          transactionId: tx.transactionId,
        },
      });

      return res.json({ ok: true, data: { transaction: tx } });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/transactions/:transactionId/emergency-cancel',
  validate(
    z.object({
      params: z.object({ transactionId: z.string().min(1) }),
      body: z.object({
        senderId: z.string().min(1),
        reason: z.string().optional(),
      }),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { transactionId } = req.validated.params;
      const { senderId, reason } = req.validated.body;
      const tx = await emergencyCancel({
        transactionId,
        senderId,
        reason,
      });

      await sendPushToUser({
        userId: tx.receiverId,
        title: 'Payment cancelled',
        body: `${tx.senderName} cancelled the pending payment request`,
        data: {
          type: 'payment_cancelled',
          transactionId: tx.transactionId,
        },
      });

      return res.json({ ok: true, data: { transaction: tx } });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/verify',
  validate(
    z.object({
      body: z.object({
        senderId: z.string().min(1),
        receiverId: z.string().min(1),
        amount: z.number().positive(),
      }).passthrough(),
      params: z.object({}).optional(),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const risk = await verifyRisk(req.validated.body);
      return res.json({ ok: true, data: risk });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.post(
  '/transactions/log',
  validate(
    z.object({
      body: z.object({
        transactionId: z.string().min(1),
        senderId: z.string().min(1),
        receiverId: z.string().min(1),
        amount: z.number().positive(),
        status: z.string().min(1),
        riskLevel: z.string().optional(),
        riskScore: z.number().optional(),
        note: z.string().nullable().optional(),
      }),
      params: z.object({}).optional(),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    // Backward compatibility endpoint: no-op (write path is server owned).
    return res.json({ ok: true, data: { logged: true } });
  }
);

router.get(
  '/transactions/history/:userId',
  validate(
    z.object({
      params: z.object({ userId: z.string().min(1) }),
      query: z
        .object({
          limit: z
            .string()
            .regex(/^\d+$/)
            .optional(),
        })
        .optional(),
      body: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { userId } = req.validated.params;
      const limit = Number(req.validated.query?.limit || 50);
      const data = await fetchHistory(userId, limit);
      return res.json({ ok: true, data });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.get(
  '/transactions/pending/:userId',
  validate(
    z.object({
      params: z.object({ userId: z.string().min(1) }),
      query: z
        .object({
          limit: z
            .string()
            .regex(/^\d+$/)
            .optional(),
        })
        .optional(),
      body: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { userId } = req.validated.params;
      const limit = Number(req.validated.query?.limit || 50);
      const data = await fetchPending(userId, limit);
      return res.json({ ok: true, data });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.get(
  '/transactions/logs/:userId',
  validate(
    z.object({
      params: z.object({ userId: z.string().min(1) }),
      query: z
        .object({
          limit: z
            .string()
            .regex(/^\d+$/)
            .optional(),
        })
        .optional(),
      body: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { userId } = req.validated.params;
      const limit = Number(req.validated.query?.limit || 40);
      const data = await fetchLogs(userId, limit);
      return res.json({ ok: true, data });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.get(
  '/dashboard/:userId',
  validate(
    z.object({
      params: z.object({ userId: z.string().min(1) }),
      query: z
        .object({
          days: z
            .string()
            .regex(/^\d+$/)
            .optional(),
        })
        .optional(),
      body: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { userId } = req.validated.params;
      const days = Number(req.validated.query?.days || 30);
      const data = await fetchDashboard(userId, days);
      return res.json({ ok: true, data });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

router.get(
  '/transactions/:userId',
  validate(
    z.object({
      params: z.object({ userId: z.string().min(1) }),
      query: z
        .object({
          limit: z
            .string()
            .regex(/^\d+$/)
            .optional(),
        })
        .optional(),
      body: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    try {
      const { userId } = req.validated.params;
      const limit = Number(req.validated.query?.limit || 50);
      const data = await fetchHistory(userId, limit);
      return res.json({ ok: true, data });
    } catch (error) {
      return errorResponse(res, error);
    }
  }
);

module.exports = router;
