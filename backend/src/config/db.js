'use strict';

const mongoose = require('mongoose');

let memoryServer = null;
let dbMode = 'unknown'; // 'atlas' | 'memory'

// Sem MONGO_URI real (placeholder do .env.example) ou com USE_MEMORY_DB=true,
// sobe um Mongo em memória — só para teste local (dados voláteis).
function isPlaceholderUri(uri) {
  if (!uri) return true;
  const t = String(uri).trim();
  if (t.length < 16) return true;
  // Placeholder do .env.example — NÃO confundir com cluster real do Atlas.
  // Antigo: uri.indexOf('cluster.mongodb.net') >= 0 derrubava cluster real
  // cujo host termina com .mongodb.net. Agora só casa o placeholder exato.
  if (t.indexOf('usuario:senha') >= 0) return true;
  if (t.indexOf('@cluster.mongodb.net/') >= 0) return true;
  return false;
}

function isMemoryDb() {
  return memoryServer !== null;
}

function getDbMode() {
  return dbMode;
}

function maskUri(uri) {
  if (!uri) return '(vazio)';
  const s = String(uri);
  if (s.length <= 12) return '(curto demais — placeholder?)';
  return s.slice(0, 14) + '...' + s.slice(-12);
}

async function connectMainDb() {
  const explicit = process.env.USE_MEMORY_DB === 'true';
  const useMemory = explicit || isPlaceholderUri(process.env.MONGO_URI);
  // Em produção (Render: RENDER=true ou NODE_ENV=production) NUNCA usar
  // memória silenciosamente — isso apaga todos os logins a cada restart.
  const isProd = process.env.RENDER === 'true' || process.env.NODE_ENV === 'production' || !!process.env.RENDER_SERVICE_ID;
  if (useMemory && isProd && !explicit) {
    console.error('[db] ERRO FATAL: MONGO_URI ausente/placeholder em produção. '
      + 'Recebido: ' + maskUri(process.env.MONGO_URI) + '. '
      + 'No Render, defina MONGO_URI (Atlas) no Dashboard ou via scripts/render-env.sh. '
      + 'Recusando subir em modo memória para não perder logins.');
    const err = new Error('MONGO_URI ausente em produção (abortado para não perder dados).');
    err.code = 'NO_MONGO_URI';
    throw err;
  }
  if (useMemory) {
    console.log('[db] usando MongoDB em memória (teste local, dados voláteis). Defina MONGO_URI real para usar o Atlas.');
    const { MongoMemoryServer } = require('mongodb-memory-server');
    memoryServer = await MongoMemoryServer.create();
    await mongoose.connect(memoryServer.getUri('internet_gratis'));
    dbMode = 'memory';
    return mongoose.connection;
  }
  console.log('[db] conectando no MongoDB Atlas: ' + maskUri(process.env.MONGO_URI));
  await mongoose.connect(process.env.MONGO_URI);
  dbMode = 'atlas';
  console.log('[db] conectado (atlas).');
  return mongoose.connection;
}

module.exports = { connectMainDb, isMemoryDb, getDbMode, isPlaceholderUri };
