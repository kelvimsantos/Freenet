'use strict';

const mongoose = require('mongoose');

let memoryServer = null;

// Sem MONGO_URI real (placeholder do .env.example) ou com USE_MEMORY_DB=true,
// sobe um Mongo em memória — só para teste local (dados voláteis).
function isPlaceholderUri(uri) {
  if (!uri) return true;
  return uri.indexOf('usuario:senha') >= 0 || uri.indexOf('cluster.mongodb.net') >= 0;
}

function isMemoryDb() {
  return memoryServer !== null;
}

async function connectMainDb() {
  const explicit = process.env.USE_MEMORY_DB === 'true';
  if (explicit || isPlaceholderUri(process.env.MONGO_URI)) {
    console.log('[db] usando MongoDB em memória (teste local, dados voláteis). Defina MONGO_URI real para usar o Atlas.');
    const { MongoMemoryServer } = require('mongodb-memory-server');
    memoryServer = await MongoMemoryServer.create();
    await mongoose.connect(memoryServer.getUri('internet_gratis'));
    return mongoose.connection;
  }
  await mongoose.connect(process.env.MONGO_URI);
  return mongoose.connection;
}

module.exports = { connectMainDb, isMemoryDb };
