#!/usr/bin/env bash
# =============================================================================
# add-robot.sh — Instala o Robô Pet multi-usuário (BYOK/BYOD) no backend
#                "Internet Grátis" (Node.js + Express + MongoDB + JWT).
#
# Uso: rode na pasta RAIZ do backend (aonde fica src/server.js):
#   bash add-robot.sh
#
# O que faz:
#   1) Cria (nunca sobrescreve) os arquivos do robô em src/services/robot/
#      e src/routes/robot.js
#   2) Injeta o mount da rota /robot no src/server.js (com fallback manual)
#   3) Acrescenta variáveis do robô no .env.example
#
# Coleções criadas no Mongo DO USUÁRIO (BYOD): Pet, PetMemory, PetConversation,
# PetCreditLog. Créditos ganhos no chat são registrados no banco PRINCIPAL
# via services/credits (adType: 'robot_chat', eventId idempotente).
#
# Regra de crédito (híbrida, padrão):
#   +1 a cada 5 mensagens válidas + bônus +1 por sessão de >= 5 min,
#   teto de 3 créditos/dia (configurável por env e por usuário).
# =============================================================================
set -euo pipefail

ROOT="$(pwd)"
[ -f "$ROOT/src/server.js" ] || { echo "ERRO: rode este script na pasta raiz do backend (src/server.js não encontrado)."; exit 1; }

note() { printf '\033[1;32m[add-robot]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[add-robot]\033[0m %s\n' "$*"; }

# Escreve o conteúdo do heredoc no destino APENAS se o arquivo ainda não
# existir (promessa de "nunca sobrescreve" do cabeçalho). Se já existe,
# consome o heredoc e avisa.
write_new() {
  local target="$1"
  if [ -e "$target" ]; then
    cat > /dev/null
    warn "mantido (já existe): $target"
    return 0
  fi
  cat > "$target"
}

mkdir -p src/services/robot

note "Criando src/services/robot/petSchemas.js"
write_new src/services/robot/petSchemas.js <<'PET_SCHEMAS_EOF'
'use strict';

const mongoose = require('mongoose');

// Schemas das coleções que vivem no Mongo DO USUÁRIO (BYOD).
// Não são registrados na conexão principal — são usados via conn.model().

const MoodEnum = ['feliz', 'neutro', 'triste', 'animado'];
const StageEnum = ['ovo', 'filhote', 'jovem', 'adulto', 'sabio'];

const PetSchema = new mongoose.Schema({
  userId: { type: String, required: true, index: true },
  name: { type: String, default: 'Luna' },
  level: { type: Number, default: 1 },
  xp: { type: Number, default: 0 },
  mood: { type: String, enum: MoodEnum, default: 'neutro' },
  personality: {
    humor: { type: Number, default: 0.7 },
    curiosidade: { type: Number, default: 0.9 },
    energia: { type: Number, default: 0.5 },
    carinho: { type: Number, default: 0.6 }
  },
  wants: [{
    _id: false,
    type: { type: String },
    priority: { type: Number, default: 0.5 }
  }],
  evolution: {
    stage: { type: String, enum: StageEnum, default: 'filhote' },
    unlockedSkills: { type: [String], default: ['falar'] }
  },
  lastInteractionAt: Date
}, { timestamps: true, collection: 'Pet' });

const PetMemorySchema = new mongoose.Schema({
  userId: { type: String, required: true, index: true },
  summary: { type: String, required: true },
  tags: { type: [String], default: [] },
  emotionalTone: { type: String, enum: ['positivo', 'neutro', 'negativo'], default: 'neutro' },
  date: { type: Date, default: Date.now },
  context: String
}, { timestamps: true, collection: 'PetMemory' });
PetMemorySchema.index({ userId: 1, date: -1 });

const PetConversationSchema = new mongoose.Schema({
  userId: { type: String, required: true, index: true },
  role: { type: String, enum: ['user', 'pet'], required: true },
  content: { type: String, required: true },
  tokensUsed: { type: Number, default: 0 }
}, { timestamps: { createdAt: true, updatedAt: false }, collection: 'PetConversation' });
PetConversationSchema.index({ userId: 1, createdAt: -1 });

// Uma linha por usuário por dia — controle anti-farm de créditos do chat.
const PetCreditLogSchema = new mongoose.Schema({
  userId: { type: String, required: true, unique: true },
  date: { type: String, required: true }, // YYYY-MM-DD
  messagesCount: { type: Number, default: 0 },
  creditsEarnedToday: { type: Number, default: 0 },
  sessionStartedAt: Date,
  sessionBonusAwarded: { type: Boolean, default: false },
  lastMessageAt: Date
}, { timestamps: true, collection: 'PetCreditLog' });

module.exports = {
  PetSchema,
  PetMemorySchema,
  PetConversationSchema,
  PetCreditLogSchema,
  MoodEnum,
  StageEnum
};
PET_SCHEMAS_EOF
note "Criando src/services/robot/connectionManager.js"
write_new src/services/robot/connectionManager.js <<'CONN_EOF'
'use strict';

// Conexões por usuário (BYOD) com cache + TTL — reusa o cache do
// services/userDb se ele existir; caso contrário usa cache próprio.

const mongoose = require('mongoose');
const { PetSchema, PetMemorySchema, PetConversationSchema, PetCreditLogSchema } = require('./petSchemas');

const TTL_MINUTES = Number(process.env.USER_DB_CACHE_TTL_MINUTES || 30);
const TEST_TIMEOUT = Number(process.env.USER_DB_TEST_TIMEOUT || 5000);

let shared = null;
try { shared = require('../userDb'); } catch (_) { shared = null; }

const localCache = new Map(); // userId -> { conn, expiresAt }

function getModels(conn) {
  return {
    Pet: conn.models.Pet || conn.model('Pet', PetSchema),
    PetMemory: conn.models.PetMemory || conn.model('PetMemory', PetMemorySchema),
    PetConversation: conn.models.PetConversation || conn.model('PetConversation', PetConversationSchema),
    PetCreditLog: conn.models.PetCreditLog || conn.model('PetCreditLog', PetCreditLogSchema)
  };
}

async function connectForUser(userId, uri) {
  // 1) tenta o cache/compartilamento já existente em services/userDb
  if (shared) {
    for (const fnName of ['getConnection', 'connectUserDb', 'getUserDbConnection', 'connectionFor']) {
      if (typeof shared[fnName] === 'function') {
        const conn = await shared[fnName](userId, uri, { serverSelectionTimeoutMS: TEST_TIMEOUT });
        if (conn) return getModels(conn);
      }
    }
  }
  // 2) cache local
  const hit = localCache.get(String(userId));
  if (hit && hit.expiresAt > Date.now() && hit.conn.readyState === 1) {
    return getModels(hit.conn);
  }
  if (hit && hit.conn) { try { await hit.conn.close(); } catch (_) {} }
  const conn = await mongoose.createConnection(uri, {
    serverSelectionTimeoutMS: TEST_TIMEOUT,
    maxPoolSize: 5
  }).asPromise();
  localCache.set(String(userId), { conn, expiresAt: Date.now() + TTL_MINUTES * 60 * 1000 });
  return getModels(conn);
}

async function dropUserConnection(userId) {
  localCache.delete(String(userId));
  if (shared) {
    for (const fnName of ['dropConnection', 'closeUserConnection', 'evict']) {
      if (typeof shared[fnName] === 'function') {
        try { await shared[fnName](userId); } catch (_) {}
      }
    }
  }
}

module.exports = { connectForUser, dropUserConnection };
CONN_EOF

note "Criando src/services/robot/credentials.js"
write_new src/services/robot/credentials.js <<'CRED_EOF'
'use strict';

// Lê a config BYOK/BYOD do usuário no banco PRINCIPAL e decifra com
// cryptoService (AES-256-GCM). Nunca retorna segredo sem decifrar.

let UserRobotConfig;
try { UserRobotConfig = require('../../models/UserRobotConfig'); }
catch (_) { throw new Error('models/UserRobotConfig não encontrado — rode a instalação BYOK/BYOD antes do add-robot.sh'); }

let cryptoService;
try { cryptoService = require('../cryptoService'); }
catch (_) { cryptoService = null; }

function decryptField(value) {
  if (!value) return null;
  if (!cryptoService) return null;
  for (const fnName of ['decrypt', 'decryptField', 'decryptText', 'decryptString']) {
    if (typeof cryptoService[fnName] === 'function') {
      return cryptoService[fnName](value);
    }
  }
  return null;
}

async function getRobotCredentials(userId) {
  const cfg = await UserRobotConfig.findOne({ userId }).lean();
  if (!cfg) return null;
  const provider = cfg.provider || cfg.aiProvider || null;
  const apiKey = decryptField(cfg.apiKeyEncrypted || cfg.apiKey);
  const userMongoUri = decryptField(cfg.userMongoUriEncrypted || cfg.userMongoUri || cfg.mongoUri);
  const model = cfg.model || cfg.aiModel || null;
  if (!provider || !apiKey || !userMongoUri) return null;
  return { provider, apiKey, userMongoUri, model };
}

module.exports = { getRobotCredentials };
CRED_EOF

note "Criando src/services/robot/aiGateway.js"
write_new src/services/robot/aiGateway.js <<'AI_EOF'
'use strict';

// Adaptador unificado: chama o provedor de IA escolhido pelo usuário
// (grok | gemini | openai | anthropic) passando apiKey + mensagens.

const path = require('path');

const PROVIDERS = {
  grok: { mod: 'grok', fns: ['chat', 'generate', 'sendMessage', 'complete', 'createCompletion', 'default'] },
  gemini: { mod: 'gemini', fns: ['chat', 'generate', 'sendMessage', 'complete', 'createCompletion', 'default'] },
  openai: { mod: 'openai', fns: ['chat', 'generate', 'sendMessage', 'complete', 'createCompletion', 'default'] },
  anthropic: { mod: 'anthropic', fns: ['chat', 'generate', 'sendMessage', 'complete', 'createCompletion', 'default'] }
};

const cache = new Map();

function loadProvider(name) {
  if (cache.has(name)) return cache.get(name);
  const entry = PROVIDERS[name];
  if (!entry) throw Object.assign(new Error(`Provedor de IA desconhecido: ${name}`), { status: 400 });
  const mod = require(path.join(__dirname, '..', 'aiProviders', entry.mod));
  for (const fnName of entry.fns) {
    if (typeof mod[fnName] === 'function') {
      cache.set(name, mod[fnName]);
      return mod[fnName];
    }
  }
  throw new Error(`Nenhuma função chamável encontrada em aiProviders/${entry.mod}`);
}

function normalizeResult(res) {
  if (res == null) return '';
  if (typeof res === 'string') return res;
  return String(res.text ?? res.content ?? res.reply ?? res.message ?? res.output ?? '');
}

async function chat({ provider, apiKey, model, systemPrompt, messages }) {
  const fn = loadProvider(provider);
  const payload = { apiKey, model, system: systemPrompt, messages };
  let out;
  try {
    out = await fn(payload);
  } catch (_) {
    // Assinaturas variam entre provedores: tenta posiçãoais
    out = await fn(apiKey, model, systemPrompt, messages);
  }
  return normalizeResult(out) || '...';
}

module.exports = { chat, PROVIDERS: Object.keys(PROVIDERS) };
AI_EOF
note "Criando src/services/robot/memory.js"
write_new src/services/robot/memory.js <<'MEM_EOF'
'use strict';

// Memória de longo prazo do pet (PetMemory — Mongo DO USUÁRIO).
// As últimas memórias entram no system prompt do chat; novas memórias
// podem ser salvas pela rota POST /robot/memories.

async function remember(models, data) {
  const summary = data && data.summary;
  if (!summary) return null;
  return models.PetMemory.create({
    userId: data.userId,
    summary: String(summary).slice(0, 500),
    tags: Array.isArray(data.tags) ? data.tags.map(String).slice(0, 10) : [],
    emotionalTone: data.emotionalTone || 'neutro',
    context: data.context ? String(data.context).slice(0, 500) : undefined
  });
}

async function recall(models, userId, limit) {
  const n = Math.min(Math.max(Number(limit) || 5, 1), 50);
  return models.PetMemory.find({ userId }).sort({ date: -1 }).limit(n).lean();
}

module.exports = { remember, recall };
MEM_EOF
note "Criando src/services/robot/credits.js"
write_new src/services/robot/credits.js <<'CREDITS_EOF'
ro projeto qualquer coisa  'use strict';

// Regra híbrida de créditos do chat do robô (padrão, ajustável por env):
//   +1 a cada ROBOT_MESSAGES_PER_CREDIT (5) mensagens válidas
//   +1 bônus por sessão de >= ROBOT_SESSION_BONUS_MINUTES (5) min
//   teto de ROBOT_CREDITS_DAILY_CAP (3) créditos por dia/usuário
//
// Contadores em PetCreditLog (Mongo DO USUÁRIO, BYOD). O crédito em si é
// registrado no banco PRINCIPAL via services/credits com adType
// 'robot_chat' e eventId idempotente — reexecuções não duplicam.

function envNum(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

const MESSAGES_PER_CREDIT = envNum('ROBOT_MESSAGES_PER_CREDIT', 5);
const SESSION_BONUS_MINUTES = envNum('ROBOT_SESSION_BONUS_MINUTES', 5);
const SESSION_IDLE_MINUTES = envNum('ROBOT_SESSION_IDLE_MINUTES', 15);
const DAILY_CAP = envNum('ROBOT_CREDITS_DAILY_CAP', 3);

let creditsService = null;
try { creditsService = require('../credits'); }
catch (_) { creditsService = null; }

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

async function awardInMainDb(userId, amount, eventId) {
  if (!creditsService || !(amount > 0)) return false;
  const payload = { userId, amount, credits: amount, adType: 'robot_chat', eventId };
  const fns = [];
  const names = ['addCredits', 'awardCredits', 'grantCredits', 'registerCredit', 'creditUser', 'credit'];
  for (const name of names) {
    if (typeof creditsService[name] === 'function') fns.push(creditsService[name]);
  }
  if (typeof creditsService === 'function') fns.push(creditsService);
  for (const fn of fns) {
    // Assinaturas variam entre backends: tenta objeto e depois posicional.
    try {
      const res = await fn(payload);
      if (res !== false) return true;
    } catch (_) {
      try {
        const res = await fn(userId, amount, { adType: 'robot_chat', eventId });
        if (res !== false) return true;
      } catch (__) { /* tenta a próxima assinatura */ }
    }
  }
  return false;
}

async function registerChatMessage(ref) {
  const userId = ref.userId;
  const models = ref.models;
  const PetCreditLog = models.PetCreditLog;
  const date = todayISO();
  const now = new Date();

  let log = await PetCreditLog.findOne({ userId });
  if (!log) log = new PetCreditLog({ userId, date, sessionStartedAt: now });
  if (log.date !== date) {
    log.date = date;
    log.messagesCount = 0;
    log.creditsEarnedToday = 0;
    log.sessionStartedAt = now;
    log.sessionBonusAwarded = false;
  }

  const idleMs = SESSION_IDLE_MINUTES * 60 * 1000;
  const lastAt = log.lastMessageAt ? new Date(log.lastMessageAt).getTime() : 0;
  if (!log.sessionStartedAt || (lastAt && now.getTime() - lastAt > idleMs)) {
    // intervalo sem mensagens encerra a sessão anterior (novo bônus possível)
    log.sessionStartedAt = now;
    log.sessionBonusAwarded = false;
  }

  log.messagesCount += 1;
  log.lastMessageAt = now;

  const reasons = [];
  if (log.messagesCount % MESSAGES_PER_CREDIT === 0) reasons.push('messages');
  const sessionStart = new Date(log.sessionStartedAt).getTime();
  if (!log.sessionBonusAwarded && now.getTime() - sessionStart >= SESSION_BONUS_MINUTES * 60 * 1000) {
    reasons.push('session');
    log.sessionBonusAwarded = true;
  }

  const remaining = Math.max(0, DAILY_CAP - log.creditsEarnedToday);
  const amount = Math.min(reasons.length, remaining);
  let awarded = 0;
  if (amount > 0) {
    const eventId = 'robot_chat:' + userId + ':' + date + ':m' + log.messagesCount;
    const ok = await awardInMainDb(userId, amount, eventId);
    if (ok) {
      awarded = amount;
      log.creditsEarnedToday += amount;
    }
  }

  await log.save();
  return {
    awarded,
    messagesCount: log.messagesCount,
    creditsEarnedToday: log.creditsEarnedToday,
    dailyCap: DAILY_CAP
  };
}

module.exports = { registerChatMessage, MESSAGES_PER_CREDIT, SESSION_BONUS_MINUTES, DAILY_CAP };
CREDITS_EOF
note "Criando src/services/robot/chat.js"
write_new src/services/robot/chat.js <<'CHAT_EOF'
'use strict';

// Orquestrador do chat: BYOK (key do agente por usuário) → Mongo do
// usuário (BYOD: connection string do Atlas por usuário) → histórico /
// memórias / persona → IA → persistência → evolução → créditos.

const { connectForUser } = require('./connectionManager');
const { getRobotCredentials } = require('./credentials');
const { chat } = require('./aiGateway');
const { recall, remember } = require('./memory');
const { registerChatMessage } = require('./credits');

function envNum(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

const HISTORY_LIMIT = envNum('ROBOT_HISTORY_MESSAGES', 20);
const MAX_MESSAGE_CHARS = envNum('ROBOT_MAX_MESSAGE_CHARS', 2000);
const XP_PER_LEVEL = envNum('ROBOT_XP_PER_LEVEL', 10);

function httpError(status, message) {
  return Object.assign(new Error(message), { status });
}

async function getModelsFor(userId) {
  if (process.env.ROBOT_ENABLED === 'false') {
    throw httpError(503, 'Robô desativado (ROBOT_ENABLED=false).');
  }
  const creds = await getRobotCredentials(userId);
  if (!creds) {
    throw httpError(400, 'Robô não configurado para este usuário (BYOK/BYOD ausente).');
  }
  const models = await connectForUser(userId, creds.userMongoUri);
  return { creds, models };
}

async function getPet(userId) {
  const ref = await getModelsFor(userId);
  let pet = await ref.models.Pet.findOne({ userId });
  if (!pet) pet = await ref.models.Pet.create({ userId });
  return pet;
}

async function listMemories(userId, limit) {
  const ref = await getModelsFor(userId);
  return recall(ref.models, userId, limit);
}

async function saveMemory(userId, data) {
  const ref = await getModelsFor(userId);
  data = data || {};
  data.userId = userId;
  return remember(ref.models, data);
}

const STAGE_ORDER = ['ovo', 'filhote', 'jovem', 'adulto', 'sabio'];
const SKILL_BY_STAGE = { jovem: 'memorias', adulto: 'conselhos', sabio: 'sabedoria' };
function stageForLevel(level) {
  if (level >= 12) return 'sabio';
  if (level >= 8) return 'adulto';
  if (level >= 5) return 'jovem';
  if (level >= 2) return 'filhote';
  return 'ovo';
}

function numOr(obj, key, fallback) {
  const v = obj && obj[key];
  return v != null ? v : fallback;
}

function buildSystemPrompt(pet, memories, personaExtra) {
  const p = pet.personality || {};
  const evo = pet.evolution || {};
  const lines = [
    'Você é ' + pet.name + ', o robô-pet leal e divertido do app "Internet Grátis".',
    'Estágio: ' + (evo.stage || 'filhote') + ' | nível: ' + pet.level + ' | humor: ' + pet.mood + '.',
    'Personalidade — humor ' + numOr(p, 'humor', 0.7) +
      ', curiosidade ' + numOr(p, 'curiosidade', 0.9) +
      ', energia ' + numOr(p, 'energia', 0.5) +
      ', carinho ' + numOr(p, 'carinho', 0.6) + '.',
    'Responda em português do Brasil, em no máximo 3 frases, como um pet falante.',
    'Não invente comandos nem recursos do app; se não souber algo, diga que vai perguntar ao seu dono.'
  ];
  if (memories && memories.length) {
    lines.push('Memórias recentes sobre o dono:');
    for (const m of memories) lines.push('- ' + m.summary);
  }
  if (personaExtra) lines.push(String(personaExtra));
  return lines.join('\n');
}

function applyProgression(pet) {
  if (!pet.evolution) pet.evolution = {};
  if (!Array.isArray(pet.evolution.unlockedSkills)) pet.evolution.unlockedSkills = ['falar'];
  if (!pet.evolution.stage) pet.evolution.stage = 'filhote';
  pet.xp = (pet.xp || 0) + 1;
  const level = Math.max(1, 1 + Math.floor(pet.xp / XP_PER_LEVEL));
  const leveledUp = level > pet.level;
  pet.level = level;
  const desired = stageForLevel(level);
  if (STAGE_ORDER.indexOf(desired) > STAGE_ORDER.indexOf(pet.evolution.stage)) {
    pet.evolution.stage = desired;
    const skill = SKILL_BY_STAGE[desired];
    if (skill && pet.evolution.unlockedSkills.indexOf(skill) === -1) {
      pet.evolution.unlockedSkills.push(skill);
    }
  }
  if (leveledUp) pet.mood = 'animado';
  pet.lastInteractionAt = new Date();
  return leveledUp;
}

async function sendMessage(req) {
  const userId = req.userId;
  const raw = req.message == null ? '' : req.message;
  const text = String(raw).trim();
  if (!text) throw httpError(400, 'Mensagem vazia (esperado JSON { "message": "..." }).');
  if (text.length > MAX_MESSAGE_CHARS) {
    throw httpError(400, 'Mensagem muito longa (máx. ' + MAX_MESSAGE_CHARS + ' caracteres).');
  }
  const ref = await getModelsFor(userId);
  const creds = ref.creds;
  const models = ref.models;
  let pet = await models.Pet.findOne({ userId });
  if (!pet) pet = new models.Pet({ userId });
  const history = await models.PetConversation
    .find({ userId }).sort({ createdAt: -1 }).limit(HISTORY_LIMIT).lean();
  history.reverse();
  const memories = await recall(models, userId, 5);
  const systemPrompt = buildSystemPrompt(pet, memories, process.env.ROBOT_PERSONA_PROMPT);
  const messages = history.map((c) => ({ role: c.role, content: c.content }));
  messages.push({ role: 'user', content: text });
  const reply = await chat({
    provider: creds.provider,
    apiKey: creds.apiKey,
    model: creds.model,
    systemPrompt,
    messages
  });
  await models.PetConversation.insertMany([
    { userId, role: 'user', content: text },
    { userId, role: 'pet', content: reply }
  ]);
  const leveledUp = applyProgression(pet);
  await pet.save();
  const credits = await registerChatMessage({ userId, models });
  return {
    reply,
    pet: {
      name: pet.name,
      level: pet.level,
      xp: pet.xp,
      mood: pet.mood,
      stage: pet.evolution.stage,
      unlockedSkills: pet.evolution.unlockedSkills,
      leveledUp
    },
    credits
  };
}

module.exports = { sendMessage, getPet, listMemories, saveMemory };
CHAT_EOF
mkdir -p src/routes
note "Criando src/routes/robot.js"
write_new src/routes/robot.js <<'ROUTES_EOF'
'use strict';

// Rota do Robô Pet — montada pelo add-robot.sh como app.use('/robot', router).
// Reaproveita o auth do backend quando existe (middleware em middleware/);
// senão decodifica Bearer JWT (JWT_SECRET) e, em último caso (dev),
// aceita o header x-user-id. Requer express.json() aplicado no server.

const express = require('express');
const robot = require('../services/robot/chat');

const router = express.Router();

let authMiddleware = null;
const candidates = ['../middleware/auth', '../middleware/authMiddleware', '../middleware/requireAuth', '../middleware/protect'];
for (const candidate of candidates) {
  try {
    const mod = require(candidate);
    authMiddleware = mod.protect || mod.requireAuth || mod.auth || mod.verifyToken ||
      (typeof mod === 'function' ? mod : null);
    if (authMiddleware) break;
  } catch (_) { /* tenta o próximo nome comum de middleware */ }
}
if (authMiddleware) router.use(authMiddleware);

function fromJwt(req) {
  const header = req.headers.authorization || '';
  if (header.slice(0, 7).toLowerCase() !== 'bearer ') return null;
  try {
    const jwt = require('jsonwebtoken');
    const secret = process.env.JWT_SECRET || process.env.TOKEN_SECRET;
    if (!secret) return null;
    const decoded = jwt.verify(header.slice(7), secret);
    const id = decoded.id || decoded._id || decoded.userId || decoded.sub || '';
    return String(id) || null;
  } catch (_) {
    return null;
  }
}

function resolveUserId(req) {
  const u = req.user || {};
  const fromUser = String(u.id || u._id || u.userId || '') || null;
  if (fromUser) return fromUser;
  if (req.robotUserId) return String(req.robotUserId);
  if (req.headers['x-user-id']) return String(req.headers['x-user-id']);
  return fromJwt(req);
}

router.use((req, res, next) => {
  if (process.env.ROBOT_ENABLED === 'false') {
    return res.status(503).json({ error: 'Robô desativado (ROBOT_ENABLED=false).' });
  }
  const userId = resolveUserId(req);
  if (!userId) return res.status(401).json({ error: 'Não autenticado.' });
  req.robotUserId = userId;
  next();
});

function fail(res, err) {
  const status = (err && err.status) || 500;
  if (status >= 500) console.error('[robot] erro:', err);
  res.status(status).json({ error: (err && err.message) || 'Erro interno.' });
}

router.get('/pet', async (req, res) => {
  try {
    res.json({ pet: await robot.getPet(req.robotUserId) });
  } catch (err) { fail(res, err); }
});

router.get('/memories', async (req, res) => {
  try {
    const asked = Number(req.query.limit) || 10;
    const limit = Math.min(Math.max(asked, 1), 50);
    res.json({ memories: await robot.listMemories(req.robotUserId, limit) });
  } catch (err) { fail(res, err); }
});

router.post('/memories', async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.summary) return res.status(400).json({ error: 'Informe um resumo (summary).' });
    const tones = ['positivo', 'neutro', 'negativo'];
    res.status(201).json({ memory: await robot.saveMemory(req.robotUserId, {
      summary: String(body.summary).slice(0, 500),
      tags: Array.isArray(body.tags) ? body.tags : [],
      emotionalTone: tones.indexOf(body.emotionalTone) >= 0 ? body.emotionalTone : 'neutro',
      context: body.context ? String(body.context).slice(0, 500) : ''
    }) });
  } catch (err) { fail(res, err); }
});

router.post('/chat', async (req, res) => {
  try {
    res.json(await robot.sendMessage({
      userId: req.robotUserId,
      message: (req.body && req.body.message) || ''
    }));
  } catch (err) { fail(res, err); }
});

module.exports = router;
ROUTES_EOF
# -----------------------------------------------------------------------------
# Integração: mount no src/server.js + variáveis no .env.example
# -----------------------------------------------------------------------------

inject_mount() {
  local file="src/server.js"
  local tmp line_no
  if grep -q "routes/robot" "$file"; then
    note "src/server.js já referencia routes/robot — mount ignorado"
    return 0
  fi
  tmp="$(mktemp)"
  line_no="$(grep -nE 'app\.listen\(' "$file" | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$line_no" ]; then
    line_no="$(grep -nE 'server\.listen\(' "$file" | head -n 1 | cut -d: -f1 || true)"
  fi
  if [ -n "$line_no" ] && [ "$line_no" -gt 1 ]; then
    head -n "$((line_no - 1))" "$file" > "$tmp"
    printf "const robotRoutes = require('./routes/robot');\n" >> "$tmp"
    printf "app.use('/robot', robotRoutes);\n\n" >> "$tmp"
    tail -n "+$line_no" "$file" >> "$tmp"
    cp "$tmp" "$file" && rm -f "$tmp"
    note "mount /robot injetado em src/server.js"
    return 0
  fi
  line_no="$(grep -n 'app\.use(' "$file" | tail -n 1 | cut -d: -f1 || true)"
  if [ -n "$line_no" ]; then
    head -n "$line_no" "$file" > "$tmp"
    printf "const robotRoutes = require('./routes/robot');\n" >> "$tmp"
    printf "app.use('/robot', robotRoutes);\n" >> "$tmp"
    tail -n "+$((line_no + 1))" "$file" >> "$tmp"
    cp "$tmp" "$file" && rm -f "$tmp"
    note "mount /robot injetado em src/server.js"
    return 0
  fi
  rm -f "$tmp"
  warn "não encontrei app.listen/app.use em src/server.js — adicione manualmente:"
  printf "  const robotRoutes = require('./routes/robot');\n"
  printf "  app.use('/robot', robotRoutes);\n"
}

append_env() {
  local file=".env.example"
  local kv key
  if [ ! -f "$file" ]; then
    warn ".env.example não encontrado — criando apenas com as variáveis do robô"
    : > "$file"
  fi
  if ! grep -q '# --- Robô Pet' "$file"; then
    printf '\n# --- Robô Pet (add-robot.sh) ---\n' >> "$file"
  fi
  for kv in "$@"; do
    key="${kv%%=*}"
    if grep -qE "^[[:space:]]*${key}=" "$file"; then
      note ".env.example já possui ${key}"
    else
      printf '%s\n' "$kv" >> "$file"
    fi
  done
}

note "Configurando mount da rota /robot em src/server.js"
inject_mount

note "Acrescentando variáveis do robô em .env.example"
append_env \
  "ROBOT_ENABLED=true" \
  "ROBOT_MESSAGES_PER_CREDIT=5" \
  "ROBOT_SESSION_BONUS_MINUTES=5" \
  "ROBOT_SESSION_IDLE_MINUTES=15" \
  "ROBOT_CREDITS_DAILY_CAP=3" \
  "ROBOT_HISTORY_MESSAGES=20" \
  "ROBOT_MAX_MESSAGE_CHARS=2000" \
  "ROBOT_XP_PER_LEVEL=10" \
  "ROBOT_PERSONA_PROMPT=" \
  "USER_DB_CACHE_TTL_MINUTES=30" \
  "USER_DB_TEST_TIMEOUT=5000"

note "Instalação concluída."
printf '\n'
printf 'Arquivos do robô (criados apenas se não existiam):\n'
printf '  src/services/robot/petSchemas.js\n'
printf '  src/services/robot/connectionManager.js\n'
printf '  src/services/robot/credentials.js\n'
printf '  src/services/robot/aiGateway.js\n'
printf '  src/services/robot/memory.js\n'
printf '  src/services/robot/credits.js\n'
printf '  src/services/robot/chat.js\n'
printf '  src/routes/robot.js\n'
printf '\nPróximos passos:\n'
printf '  1) Confira o mount /robot em src/server.js (ou use o manual, se avisado acima).\n'
printf '  2) Tenha BYOK/BYOD (models/UserRobotConfig + cryptoService) e services/credits.\n'
printf '  3) Configure provider/apiKey/userMongoUri por usuário e reinicie o backend.\n'
printf '\nCréditos do chat (padrão): +1 a cada 5 msgs | +1 por sessão >= 5 min | teto 3/dia.\n'
printf 'Ajuste via ROBOT_MESSAGES_PER_CREDIT, ROBOT_SESSION_BONUS_MINUTES e ROBOT_CREDITS_DAILY_CAP.\n'

