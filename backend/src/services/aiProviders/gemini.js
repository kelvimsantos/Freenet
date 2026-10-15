'use strict';

// Adaptador Google Gemini (generateContent).
const MODEL = process.env.GEMINI_MODEL || 'gemini-1.5-flash';

async function chat(payload) {
  const parts = [];
  if (payload.system) parts.push({ text: 'Instruções do sistema: ' + payload.system });
  for (const m of payload.messages || []) {
    if (m.content) parts.push({ text: (m.role === 'user' ? 'Usuário: ' : 'Pet: ') + m.content });
  }
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' +
    (payload.model || MODEL) + ':generateContent?key=' + encodeURIComponent(payload.apiKey);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contents: [{ parts }] })
  });
  if (!res.ok) throw new Error('Gemini respondeu ' + res.status);
  const data = await res.json();
  const cand = data && data.candidates && data.candidates[0];
  const part = cand && cand.content && cand.content.parts && cand.content.parts[0];
  return (part && part.text) || '...';
}

module.exports = { chat };
