'use strict';

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { connectMainDb, isMemoryDb } = require('./config/db');

const app = express();
app.use(cors());
app.use(express.json());

// Serve o frontend na mesma origem quando a pasta existir (sem build, sem 2ª porta).
const frontendDir = path.join(__dirname, '..', '..', 'frontend');
if (fs.existsSync(path.join(frontendDir, 'index.html'))) {
  app.use(express.static(frontendDir));
}

app.get('/health', (req, res) => res.json({ ok: true, app: 'internet-gratis' }));

app.use('/api/auth', require('./routes/auth'));
app.use('/api/ads', require('./routes/ads'));
app.use('/api/credits', require('./routes/credits'));
app.use('/api/robot-config', require('./routes/robotConfig'));

app.use((req, res) => res.status(404).json({ error: 'Rota não encontrada.' }));

const PORT = process.env.PORT || 3000;
connectMainDb().then(async () => {
  if (isMemoryDb()) {
    const { ensureSampleAds } = require('./seed');
    const total = await ensureSampleAds();
    console.log('[server] modo memória: ' + total + ' anúncio(s) de exemplo garantidos.');
  }
  app.listen(PORT, () => console.log('[server] Internet Grátis rodando na porta ' + PORT));
}).catch((err) => {
  console.error('[server] falha ao conectar no Mongo:', err.message);
  process.exit(1);
});

module.exports = app;
