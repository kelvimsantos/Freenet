'use strict';

const mongoose = require('mongoose');

const AdSchema = new mongoose.Schema({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  imageUrl: { type: String, default: '' },
  videoUrl: { type: String, default: '' }, // mp4/vídeo; se vazio, usa temporizador
  durationSec: { type: Number, default: 15 }, // tempo mínimo de exibição
  reward: { type: Number, default: 1 }, // créditos por visualização
  network: { type: String, default: 'internal' }, // internal | adsense | admob | custom
  externalSlot: { type: String, default: '' }, // id do slot na rede externa
  active: { type: Boolean, default: true }
}, { timestamps: true, collection: 'Ad' });

module.exports = mongoose.model('Ad', AdSchema);
