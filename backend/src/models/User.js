'use strict';

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const UserSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true, index: true },
  passwordHash: { type: String, required: true },
  balance: { type: Number, default: 0 }, // saldo de créditos
  adsWatchedToday: { type: Number, default: 0 },
  adsDay: { type: String, default: '' }, // YYYY-MM-DD do contador
  lastDailyBonusAt: { type: Date, default: null }
}, { timestamps: true, collection: 'User' });

UserSchema.methods.setPassword = async function setPassword(password) {
  this.passwordHash = await bcrypt.hash(String(password), 10);
};

UserSchema.methods.checkPassword = function checkPassword(password) {
  return bcrypt.compare(String(password), this.passwordHash);
};

UserSchema.methods.toSafeJSON = function toSafeJSON() {
  return { id: String(this._id), name: this.name, email: this.email, balance: this.balance };
};

module.exports = mongoose.model('User', UserSchema);
