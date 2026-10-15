'use strict';

const express = require('express');
const User = require('../models/User');
const { sign, authMiddleware } = require('../middleware/auth');
const credits = require('../services/credits');

const router = express.Router();

router.post('/register', async (req, res) => {
  try {
    const name = String((req.body && req.body.name) || '').trim();
    const email = String((req.body && req.body.email) || '').trim().toLowerCase();
    const password = String((req.body && req.body.password) || '');
    if (!name || !email || !password) {
      return res.status(400).json({ error: 'Informe nome, email e senha.' });
    }
    if (await User.findOne({ email })) {
      return res.status(409).json({ error: 'Email já cadastrado.' });
    }
    const user = new User({ name, email, passwordHash: 'x' });
    await user.setPassword(password);
    await user.save();
    await credits.addCredits({
      userId: user._id, amount: 2, adType: 'welcome_bonus', eventId: 'welcome:' + String(user._id)
    }).catch(() => null);
    const fresh = await User.findById(user._id);
    res.status(201).json({ token: sign(fresh), user: fresh.toSafeJSON() });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao registrar.' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const email = String((req.body && req.body.email) || '').trim().toLowerCase();
    const password = String((req.body && req.body.password) || '');
    const user = await User.findOne({ email });
    if (!user || !(await user.checkPassword(password))) {
      return res.status(401).json({ error: 'Email ou senha inválidos.' });
    }
    res.json({ token: sign(user), user: user.toSafeJSON() });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao entrar.' });
  }
});

router.get('/me', authMiddleware, async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) return res.status(404).json({ error: 'Usuário não encontrado.' });
    res.json({ user: user.toSafeJSON() });
  } catch (err) {
    res.status(500).json({ error: 'Erro interno.' });
  }
});

module.exports = router;
