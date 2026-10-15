'use strict';

const mongoose = require('mongoose');

const RedemptionSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  plan: { type: String, required: true }, // internet_100mb | internet_1gb | ...
  cost: { type: Number, required: true },
  status: { type: String, enum: ['pending', 'delivered', 'failed'], default: 'pending' }
}, { timestamps: true, collection: 'Redemption' });

module.exports = mongoose.model('Redemption', RedemptionSchema);
