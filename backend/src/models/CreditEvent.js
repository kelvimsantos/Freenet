'use strict';

const mongoose = require('mongoose');

// Evento de crédito idempotente (eventId único). Origens: 'ads_watch',
// 'robot_chat', 'daily_bonus', 'redeem' (lançamento negativo).
const CreditEventSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  amount: { type: Number, required: true }, // +ganho / -gasto
  adType: { type: String, required: true, index: true },
  eventId: { type: String, required: true, unique: true },
  meta: { type: mongoose.Schema.Types.Mixed, default: {} }
}, { timestamps: { createdAt: true, updatedAt: false }, collection: 'CreditEvent' });

CreditEventSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('CreditEvent', CreditEventSchema);
