'use strict';

const express = require('express');
const Ad = require('../models/Ad');
const User = require('../models/User');
const credits = require('../services/credits');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

// Lista anúncios ativos. O frontend pode intercalar slots externos
// (AdSense/AdMob) usando ad.network + ad.externalSlot.
router.get('/', async (req, res) => {
  try {
    const ads = await Ad.find({ active: true }).sort({ createdAt: 1 }).lean();
    res.json({ ads, networks: { adsense: process.env.ADSENSE_CLIENT_ID || null, admob: process.env.ADMOB_APP_ID || null } });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao listar anúncios.' });
  }
});

// Confirma visualização completa e credita a recompensa (idempotente).
// Body: { adId, watchToken } — o frontend gera um watchToken único por exibição.
router.post('/:id/complete', async (req, res) => {
  try {
    const ad = await Ad.findById(req.params.id);
    if (!ad || !ad.active) return res.status(404).json({ error: 'Anúncio indisponível.' });

    const watchToken = String((req.body && req.body.watchToken) || '').trim();
    if (!watchToken) return res.status(400).json({ error: 'watchToken é obrigatório.' });

    const cap = Number(process.env.ADS_DAILY_CAP || 20);
    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ error: 'Usuário não encontrado.' });

    const today = todayISO();
    if (user.adsDay !== today) { user.adsDay = today; user.adsWatchedToday = 0; }
    if (user.adsWatchedToday >= cap) {
      return res.status(429).json({ error: 'Limite diário de anúncios atingido.', balance: user.balance });
    }

    const out = await credits.addCredits({
      userId: user._id,
      amount: ad.reward,
      adType: 'ads_watch',
      eventId: 'ads_watch:' + String(user._id) + ':' + watchToken,
      meta: { adId: String(ad._id), network: ad.network }
    });
    if (!out.duplicate) {
      user.adsWatchedToday += 1;
      await user.save();
    }
    res.json({ ok: true, duplicate: out.duplicate, reward: ad.reward, balance: out.balance });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao registrar visualização.' });
  }
});

module.exports = router;
