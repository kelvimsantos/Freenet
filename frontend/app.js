'use strict';
/* Frontend Internet Grátis — login, anúncios, chat do robô, carteira. */

const API = (window.API_BASE || 'http://localhost:3000').replace(/\/$/, '');
const LS_TOKEN = 'ig_token';
const LS_USER = 'ig_user';

const $ = (id) => document.getElementById(id);

function headers(json) {
  const h = {};
  if (json) h['Content-Type'] = 'application/json';
  const t = localStorage.getItem(LS_TOKEN);
  if (t) h.Authorization = 'Bearer ' + t;
  return h;
}

async function api(path, opts) {
  const res = await fetch(API + path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || ('Erro ' + res.status));
  return data;
}

function show(view) {
  ['authView', 'appView'].forEach((v) => $(v).classList.add('hidden'));
  $(view).classList.remove('hidden');
}

function switchTab(name) {
  const tabs = document.querySelectorAll('.app-tabs .tab');
  tabs.forEach((b) => b.classList.toggle('active', b.dataset.view === name));
  ['adsView', 'robotView', 'walletView', 'configView'].forEach((v) => $(v).classList.add('hidden'));
  $(name).classList.remove('hidden');
  if (name === 'walletView') loadWallet();
  if (name === 'robotView') loadPet();
  if (name === 'configView') loadConfig();
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

let mode = 'login';
$('tabLogin').onclick = () => {
  mode = 'login';
  $('tabLogin').classList.add('active');
  $('tabRegister').classList.remove('active');
  $('authName').classList.add('hidden');
};
$('tabRegister').onclick = () => {
  mode = 'register';
  $('tabRegister').classList.add('active');
  $('tabLogin').classList.remove('active');
  $('authName').classList.remove('hidden');
};

$('authForm').onsubmit = async (e) => {
  e.preventDefault();
  $('authError').classList.add('hidden');
  try {
    const body = { email: $('authEmail').value.trim(), password: $('authPass').value };
    if (mode === 'register') body.name = $('authName').value.trim();
    const target = mode === 'register' ? '/api/auth/register' : '/api/auth/login';
    const out = await api(target, { method: 'POST', headers: headers(true), body: JSON.stringify(body) });
    localStorage.setItem(LS_TOKEN, out.token);
    localStorage.setItem(LS_USER, JSON.stringify(out.user));
    enterApp();
  } catch (err) {
    $('authError').textContent = err.message;
    $('authError').classList.remove('hidden');
  }
};

$('logoutBtn').onclick = () => {
  localStorage.removeItem(LS_TOKEN);
  localStorage.removeItem(LS_USER);
  show('authView');
  $('logoutBtn').classList.add('hidden');
  $('balance').classList.add('hidden');
};

function enterApp() {
  show('appView');
  $('logoutBtn').classList.remove('hidden');
  $('balance').classList.remove('hidden');
  refreshBalance();
  loadAds();
}

async function refreshBalance() {
  try {
    const out = await api('/api/credits/balance', { headers: headers() });
    $('balanceValue').textContent = out.balance;
    if ($('walletBalance')) $('walletBalance').textContent = out.balance;
  } catch (_) { /* sessão expirada etc. */ }
}

/* ---------- ANÚNCIOS ---------- */
async function loadAds() {
  const box = $('adsList');
  box.innerHTML = '<p class="muted">Carregando…</p>';
  try {
    const out = await api('/api/ads', { headers: headers() });
    if (!out.ads.length) { box.innerHTML = '<p class="muted">Nenhum anúncio ativo.</p>'; return; }
    box.innerHTML = '';
    out.ads.forEach((ad) => {
      const div = document.createElement('div');
      div.className = 'ad-item';
      const info = document.createElement('div');
      info.innerHTML = '<b>' + escapeHtml(ad.title) + '</b><br><span class="muted">+' +
        ad.reward + ' créditos • ' + ad.durationSec + 's</span>';
      const btn = document.createElement('button');
      btn.className = 'btn btn-primary';
      btn.textContent = 'Assistir';
      btn.onclick = () => playAd(ad);
      div.append(info, btn);
      box.appendChild(div);
    });
  } catch (err) {
    box.innerHTML = '<p class="error">' + escapeHtml(err.message) + '</p>';
  }
}

let adTimer = null;
function playAd(ad) {
  clearInterval(adTimer);
  $('adPlayer').classList.remove('hidden');
  $('adTitle').textContent = ad.title;
  $('adDesc').textContent = ad.description || '';
  $('adCloseBtn').classList.add('hidden');
  const video = $('adVideo');
  if (ad.videoUrl) {
    video.src = ad.videoUrl;
    video.classList.remove('hidden');
    video.play().catch(() => null);
  } else {
    video.classList.add('hidden');
    video.removeAttribute('src');
  }
  const rnd = Math.random().toString(36).slice(2, 10);
  const watchToken = 'w_' + Date.now() + '_' + rnd;
  const total = Math.max(Number(ad.durationSec) || 15, 3);
  const started = Date.now();
  adTimer = setInterval(async () => {
    const elapsed = (Date.now() - started) / 1000;
    $('adProgress').style.width = Math.min(100, (elapsed / total) * 100) + '%';
    const left = Math.max(0, Math.ceil(total - elapsed));
    if (left > 0) {
      $('adTimer').textContent = 'Aguarde ' + left + 's…';
      return;
    }
    clearInterval(adTimer);
    $('adTimer').textContent = 'Concluído! Creditando…';
    try {
      const out = await api('/api/ads/' + ad._id + '/complete', {
        method: 'POST', headers: headers(true), body: JSON.stringify({ watchToken })
      });
      $('adTimer').textContent = out.duplicate ? 'Já creditado antes. ✅' : '+' + ad.reward + ' créditos! ✅';
      $('adCloseBtn').classList.remove('hidden');
      refreshBalance();
    } catch (err) {
      $('adTimer').textContent = err.message;
      $('adCloseBtn').classList.remove('hidden');
    }
  }, 300);
}

$('adCloseBtn').onclick = () => {
  clearInterval(adTimer);
  $('adPlayer').classList.add('hidden');
  const v = $('adVideo');
  v.pause();
  v.removeAttribute('src');
};

$('dailyBtn').onclick = async () => {
  try {
    const out = await api('/api/credits/daily-bonus', { method: 'POST', headers: headers() });
    alert(out.duplicate ? 'Bônus de hoje já resgatado 🙂' : 'Bônus diário creditado! 🎁');
    refreshBalance();
  } catch (err) { alert(err.message); }
};

/* ---------- ROBÔ ---------- */
async function loadPet() {
  try {
    const out = await api('/robot/pet', { headers: headers() });
    const p = out.pet;
    const stage = (p.evolution && p.evolution.stage) || p.stage || 'filhote';
    $('petInfo').textContent = '🐾 ' + p.name + ' • nível ' + p.level + ' • ' + stage;
  } catch (err) {
    $('petInfo').textContent = 'Configure suas chaves na aba ⚙️ para ativar o pet. (' + err.message + ')';
  }
}

async function loadConfig() {
  try {
    const out = await api('/api/robot-config', { headers: headers() });
    if (out.configured) {
      $('configMsg').textContent = '✅ Configurado com ' + (out.provider || '') + '. Preencha só para trocar.';
    } else {
      $('configMsg').textContent = '⚠️ Ainda não configurado.';
    }
    if (out.provider) $('cfgProvider').value = out.provider;
    if (out.model) $('cfgModel').value = out.model;
  } catch (err) { $('configMsg').textContent = err.message; }
}

$('configForm').onsubmit = async (e) => {
  e.preventDefault();
  const body = { provider: $('cfgProvider').value, model: $('cfgModel').value.trim() };
  if ($('cfgApiKey').value.trim()) body.apiKey = $('cfgApiKey').value.trim();
  if ($('cfgMongoUri').value.trim()) body.userMongoUri = $('cfgMongoUri').value.trim();
  try {
    await api('/api/robot-config', { method: 'PUT', headers: headers(true), body: JSON.stringify(body) });
    $('configMsg').textContent = '✅ Salvo! Segredos cifrados no servidor.';
    $('cfgApiKey').value = '';
    $('cfgMongoUri').value = '';
  } catch (err) { $('configMsg').textContent = err.message; }
};

function addMsg(role, text) {
  const div = document.createElement('div');
  div.className = 'msg ' + role;
  div.textContent = text;
  $('chatBox').appendChild(div);
  $('chatBox').scrollTop = $('chatBox').scrollHeight;
}

$('chatForm').onsubmit = async (e) => {
  e.preventDefault();
  const text = $('chatInput').value.trim();
  if (!text) return;
  $('chatInput').value = '';
  addMsg('user', text);
  addMsg('pet', '…');
  try {
    const out = await api('/robot/chat', {
      method: 'POST', headers: headers(true), body: JSON.stringify({ message: text })
    });
    $('chatBox').lastChild.textContent = out.reply;
    if (out.credits && out.credits.awarded > 0) {
      addMsg('pet', '🎉 +' + out.credits.awarded + ' crédito(s) por conversar comigo!');
    }
    refreshBalance();
  } catch (err) {
    $('chatBox').lastChild.textContent = 'Erro: ' + err.message;
  }
};

/* ---------- CARTEIRA ---------- */
async function loadWallet() {
  try {
    const plans = await api('/api/credits/plans', { headers: headers() });
    const box = $('plansList');
    box.innerHTML = '';
    plans.plans.forEach((p) => {
      const div = document.createElement('div');
      div.className = 'plan-item';
      const info = document.createElement('div');
      info.innerHTML = '<b>' + escapeHtml(p.label) + '</b><br><span class="muted">' + p.cost + ' créditos</span>';
      const btn = document.createElement('button');
      btn.className = 'btn btn-secondary';
      btn.textContent = 'Resgatar';
      btn.onclick = () => redeemPlan(p);
      div.append(info, btn);
      box.appendChild(div);
    });
    const hist = await api('/api/credits/history?limit=20', { headers: headers() });
    const hbox = $('historyList');
    hbox.innerHTML = hist.events.length ? '' : '<p class="muted">Sem movimentações ainda.</p>';
    hist.events.forEach((ev) => {
      const div = document.createElement('div');
      div.className = 'history-item';
      const sign = ev.amount >= 0 ? '+' : '';
      div.innerHTML = '<span>' + escapeHtml(ev.adType) + '</span><b>' + sign + ev.amount + '</b>';
      hbox.appendChild(div);
    });
    refreshBalance();
  } catch (err) {
    $('plansList').innerHTML = '<p class="error">' + escapeHtml(err.message) + '</p>';
  }
}

async function redeemPlan(p) {
  try {
    await api('/api/credits/redeem', {
      method: 'POST', headers: headers(true), body: JSON.stringify({ plan: p.id })
    });
    alert('Resgatado: ' + p.label + ' ✅');
    refreshBalance();
    loadWallet();
  } catch (err) { alert(err.message); }
}

document.querySelectorAll('.app-tabs .tab').forEach((b) => {
  b.onclick = () => switchTab(b.dataset.view);
});

/* ---------- INIT ---------- */
// Valida a sessão salva: token pode ter expirado ou sido invalidado por
// troca de JWT_SECRET / banco zerado no restart. Sem isso o app abria
// direto no appView quebrado (saldo/ads falhando em silêncio).
async function boot() {
  const saved = localStorage.getItem(LS_TOKEN);
  if (!saved) { show('authView'); return; }
  try {
    await api('/api/auth/me', { headers: headers() });
    enterApp();
  } catch (_) {
    localStorage.removeItem(LS_TOKEN);
    localStorage.removeItem(LS_USER);
    show('authView');
  }
}
boot();
