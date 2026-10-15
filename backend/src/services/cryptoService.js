'use strict';

const crypto = require('crypto');

// AES-256-GCM para cifrar segredos do usuário (apiKey + mongo URI do robô).
// Formato: ivHex:cipherHex:tagHex
const ALGO = 'aes-256-gcm';

function getKey() {
  const hex = process.env.ENCRYPTION_KEY || '';
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error('ENCRYPTION_KEY inválida — use 64 caracteres hex (openssl rand -hex 32).');
  }
  return Buffer.from(hex, 'hex');
}

function encrypt(plain) {
  if (plain == null || plain === '') return '';
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, getKey(), iv);
  const enc = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  return iv.toString('hex') + ':' + enc.toString('hex') + ':' + cipher.getAuthTag().toString('hex');
}

function decrypt(payload) {
  if (!payload) return null;
  const parts = String(payload).split(':');
  if (parts.length !== 3) return null;
  const decipher = crypto.createDecipheriv(ALGO, getKey(), Buffer.from(parts[0], 'hex'));
  decipher.setAuthTag(Buffer.from(parts[2], 'hex'));
  return Buffer.concat([decipher.update(Buffer.from(parts[1], 'hex')), decipher.final()]).toString('utf8');
}

module.exports = { encrypt, decrypt, decryptField: decrypt, decryptText: decrypt, decryptString: decrypt };
