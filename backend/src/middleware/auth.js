'use strict';

const jwt = require('jsonwebtoken');

function getSecret() {
  return process.env.JWT_SECRET || 'dev-secret';
}

function sign(user) {
  const id = user.id || String(user._id);
  return jwt.sign({ id }, getSecret(), { expiresIn: '7d' });
}

function verify(token) {
  return jwt.verify(token, getSecret());
}

function authMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  if (header.slice(0, 7).toLowerCase() !== 'bearer ') {
    return res.status(401).json({ error: 'Token ausente. Use Authorization: Bearer <token>.' });
  }
  try {
    const decoded = verify(header.slice(7));
    req.user = { id: String(decoded.id || decoded._id || decoded.sub || '') };
    if (!req.user.id) return res.status(401).json({ error: 'Token inválido.' });
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Token inválido ou expirado.' });
  }
}

const auth = authMiddleware;
const protect = authMiddleware;
const requireAuth = authMiddleware;

module.exports = { sign, verify, authMiddleware, auth, protect, requireAuth };
