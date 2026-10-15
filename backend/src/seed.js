'use strict';

// Seed: cria anúncios de exemplo (internos) se a coleção estiver vazia.
// Uso: npm run seed (com .env configurado).
require('dotenv').config();
const { connectMainDb } = require('./config/db');
const Ad = require('./models/Ad');

const SAMPLE_ADS = [
  {
    title: 'Patrocinador Exemplo — Plano Turbo',
    description: 'Assista até o fim e ganhe créditos para trocar por internet.',
    durationSec: 15, reward: 2, network: 'internal', active: true
  },
  {
    title: 'Parceiro Local — Loja do Bairro',
    description: 'Conheça as ofertas do comércio local.',
    durationSec: 10, reward: 1, network: 'internal', active: true
  },
  {
    title: 'Vídeo Promocional — Novidades do App',
    description: 'Veja o que há de novo no Internet Grátis.',
    durationSec: 20, reward: 3, network: 'internal', active: true
  }
];

async function ensureSampleAds() {
  const count = await Ad.countDocuments();
  if (count > 0) return count;
  await Ad.insertMany(SAMPLE_ADS);
  return SAMPLE_ADS.length;
}

async function main() {
  await connectMainDb();
  const total = await ensureSampleAds();
  console.log('[seed] anúncios no banco: ' + total + '.');
  process.exit(0);
}

if (require.main === module) {
  main().catch((err) => { console.error('[seed] erro:', err.message); process.exit(1); });
}

module.exports = { ensureSampleAds };
