'use strict';

const mongoose = require('mongoose');

// Config BYOK/BYOD do robô por usuário (lida pelo add-robot.sh via
// services/robot/credentials.js). Segredos ficam cifrados (AES-256-GCM).
const UserRobotConfigSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
  provider: { type: String, enum: ['grok', 'gemini', 'openai', 'anthropic'], default: 'grok' },
  model: { type: String, default: '' },
  apiKeyEncrypted: { type: String, default: '' },
  userMongoUriEncrypted: { type: String, default: '' }
}, { timestamps: true, collection: 'UserRobotConfig' });

module.exports = mongoose.model('UserRobotConfig', UserRobotConfigSchema);
