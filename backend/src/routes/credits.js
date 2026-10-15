'use strict';

const express = require('express');
const Redemption = require('../models/Redemption');
const credits = require('../services/credits');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

const PLANS = [
  { id: 'internet_100mb', label: '100 MB de internet', cost: 10 },
  { id: 'internet_500mb', label: '500 MB de internet', cost: 40 },
  { id: 'internet_1gb', label: '1 GB de internet', cost: 70 }
];

router.get('/plans', (req, res) => res.json({ plans: PLANS }));

router.get('/balance', async (req, res) => {
  try {
    res.json(await credits.getBalance(req.user.id));
  } catch (err) {
    res.status(500).json({ error: 'Erro ao ler saldo.' });
  }
});

router.get('/history', async (req, res) => {
  try {
    res.json(await credits.history(req.user.id, req.query.limit));
  } catch (err) {
    res.status(500).json({ error: 'Erro ao ler histórico.' });
  }
});

// Bônus diário: +3 créditos, 1x por dia (idempotente por data).
router.post('/daily-bonus', async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const out = await credits.addCredits({
      userId: req.user.id,
      amount: 3,
      adType: 'daily_bonus',
      eventId: 'daily_bonus:' + String(req.user.id) + ':' + today
    });
    res.json({ ok: true, duplicate: out.duplicate, balance: out.balance });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao resgatar bônus diário.' });
  }
});

// Resgata um plano de internet com o saldo (lançamento negativo idempotente).
router.post('/redeem', async (req, res) => {
  try {
    const plan = PLANS.find((p) => p.id === String((req.body && req.body.plan) || ''));
    if (!plan) return res.status(400).json({ error: 'Plano inválido.' });
    const bal = await credits.getBalance(req.user.id);
    if (bal.balance < plan.cost) {
      return res.status(402).json({ error: 'Saldo insuficiente.', balance: bal.balance });
    }
    const redemption = await Redemption.create({
      userId: req.user.id, plan: plan.id, cost: plan.cost, status: 'delivered'
    });
    const out = await credits.addCredits({
      userId: req.user.id,
      amount: -plan.cost,
      adType: 'redeem',
      eventId: 'redeem:' + String(redemption._id),
      meta: { plan: plan.id }
    });
    res.json({ ok: true, redemption, balance: out.balance });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao resgatar.' });
  }
});

module.exports = router;
