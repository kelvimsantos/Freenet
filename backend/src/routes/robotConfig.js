'use strict';

const express = require('express');
const UserRobotConfig = require('../models/UserRobotConfig');
const cryptoService = require('../services/cryptoService');
const { dropUserConnection } = require('../services/userDb');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

// Salva/atualiza a config BYOK/BYOD do robô (segredos cifrados).
// Body: { provider: grok|gemini|openai|anthropic, model, apiKey, userMongoUri }
router.put('/', async (req, res) => {
  try {
    const body = req.body || {};
    const providers = ['grok', 'gemini', 'openai', 'anthropic'];
    const data = { userId: req.user.id };
    if (body.provider) {
      if (providers.indexOf(body.provider) < 0) {
        return res.status(400).json({ error: 'provider inválido.' });
      }
      data.provider = body.provider;
    }
    if (body.model != null) data.model = String(body.model).slice(0, 120);
    if (body.apiKey) data.apiKeyEncrypted = cryptoService.encrypt(String(body.apiKey));
    if (body.userMongoUri) data.userMongoUriEncrypted = cryptoService.encrypt(String(body.userMongoUri));
    const cfg = await UserRobotConfig.findOneAndUpdate(
      { userId: req.user.id }, { $set: data }, { new: true, upsert: true }
    );
    await dropUserConnection(req.user.id); // força reconexão com a nova URI
    res.json({ ok: true, provider: cfg.provider, model: cfg.model, configured: !!(cfg.apiKeyEncrypted && cfg.userMongoUriEncrypted) });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao salvar configuração.' });
  }
});

router.get('/', async (req, res) => {
  try {
    const cfg = await UserRobotConfig.findOne({ userId: req.user.id }).lean();
    if (!cfg) return res.json({ configured: false });
    res.json({ configured: !!(cfg.apiKeyEncrypted && cfg.userMongoUriEncrypted), provider: cfg.provider, model: cfg.model || '' });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao ler configuração.' });
  }
});

router.delete('/', async (req, res) => {
  try {
    await UserRobotConfig.deleteOne({ userId: req.user.id });
    await dropUserConnection(req.user.id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao remover configuração.' });
  }
});

module.exports = router;
