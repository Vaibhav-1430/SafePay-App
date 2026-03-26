const express = require('express');
const { z } = require('zod');

const { authenticateJwt } = require('../middleware/auth');
const { validate } = require('../middleware/validation');
const { getUser, upsertUser } = require('../services/store');

const router = express.Router();

router.get('/:userId', authenticateJwt, async (req, res) => {
  const { userId } = req.params;
  if (req.auth.uid !== userId) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const user = await getUser(userId);
  if (!user) return res.status(404).json({ error: 'User not found' });
  return res.json({
    uid: user.uid,
    email: user.email,
    name: user.name,
    phone: user.phone,
    upiId: user.upiId,
  });
});

router.put(
  '/:userId',
  authenticateJwt,
  validate(
    z.object({
      params: z.object({ userId: z.string().min(2) }),
      body: z.object({
        name: z.string().min(2).optional(),
        phone: z.string().min(8).optional(),
        upiId: z.string().min(3).optional(),
      }),
      query: z.object({}).optional(),
    })
  ),
  async (req, res) => {
    const { userId } = req.validated.params;
    if (req.auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const existing = await getUser(userId);
    if (!existing) return res.status(404).json({ error: 'User not found' });

    const updated = await upsertUser({ ...existing, ...req.validated.body, uid: userId });
    return res.json({
      uid: updated.uid,
      email: updated.email,
      name: updated.name,
      phone: updated.phone,
      upiId: updated.upiId,
    });
  }
);

module.exports = router;
