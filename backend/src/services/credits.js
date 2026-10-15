'use strict';

// Serviço central de créditos (banco PRINCIPAL).
// addCredits é idempotente por eventId: reenvios seguros não duplicam.
// Usado por ads (adType 'ads_watch') e pelo robô (adType 'robot_chat').
const User = require('../models/User');
const CreditEvent = require('../models/CreditEvent');

async function addCredits(payload) {
  const userId = payload.userId;
  const amount = Number(payload.amount != null ? payload.amount : payload.credits);
  const adType = payload.adType || 'manual';
  const eventId = payload.eventId;
  if (!userId || !Number.isFinite(amount) || amount === 0) {
    throw Object.assign(new Error('Parâmetros de crédito inválidos.'), { status: 400 });
  }
  if (!eventId) throw Object.assign(new Error('eventId é obrigatório.'), { status: 400 });

  let created;
  try {
    created = await CreditEvent.create({ userId, amount, adType, eventId, meta: payload.meta || {} });
  } catch (err) {
    if (err && err.code === 11000) { // eventId duplicado → já creditado
      const existing = await CreditEvent.findOne({ eventId }).lean();
      const user = await User.findById(userId).lean();
      return { ok: true, duplicate: true, balance: user ? user.balance : null, event: existing };
    }
    throw err;
  }
  const user = await User.findByIdAndUpdate(userId, { $inc: { balance: amount } }, { new: true });
  return { ok: true, duplicate: false, balance: user ? user.balance : null, event: created };
}

async function getBalance(userId) {
  const user = await User.findById(userId).lean();
  if (!user) throw Object.assign(new Error('Usuário não encontrado.'), { status: 404 });
  return { balance: user.balance || 0 };
}

async function history(userId, limit) {
  const n = Math.min(Math.max(Number(limit) || 20, 1), 100);
  const events = await CreditEvent.find({ userId }).sort({ createdAt: -1 }).limit(n).lean();
  return { events };
}

const grantCredits = addCredits;
const awardCredits = addCredits;
const registerCredit = addCredits;
const credit = addCredits;
const creditUser = addCredits;

module.exports = { addCredits, grantCredits, awardCredits, registerCredit, credit, creditUser, getBalance, history };
