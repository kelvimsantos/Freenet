'use strict';

// Cache de conexões dos bancos dos usuários (BYOD), reutilizado pelo
// connectionManager do robô (add-robot.sh). TTL configurável por env.
const mongoose = require('mongoose');

const TTL_MINUTES = Number(process.env.USER_DB_CACHE_TTL_MINUTES || 30);
const TEST_TIMEOUT = Number(process.env.USER_DB_TEST_TIMEOUT || 5000);

const cache = new Map(); // userId -> { conn, expiresAt }

async function getConnection(userId, uri) {
  const key = String(userId);
  const hit = cache.get(key);
  if (hit && hit.expiresAt > Date.now() && hit.conn.readyState === 1) return hit.conn;
  if (hit && hit.conn) { try { await hit.conn.close(); } catch (_) {} }
  const conn = await mongoose.createConnection(uri, {
    serverSelectionTimeoutMS: TEST_TIMEOUT,
    maxPoolSize: 5
  }).asPromise();
  cache.set(key, { conn, expiresAt: Date.now() + TTL_MINUTES * 60 * 1000 });
  return conn;
}

async function dropConnection(userId) {
  const hit = cache.get(String(userId));
  cache.delete(String(userId));
  if (hit && hit.conn) { try { await hit.conn.close(); } catch (_) {} }
}

const connectUserDb = getConnection;
const getUserDbConnection = getConnection;
const connectionFor = getConnection;
const closeUserConnection = dropConnection;
const evict = dropConnection;

module.exports = { getConnection, connectUserDb, getUserDbConnection, connectionFor, dropConnection, closeUserConnection, evict };
