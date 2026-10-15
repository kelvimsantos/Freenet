'use strict';

// Adaptador Grok (xAI) — endpoint OpenAI-compatível.
// Payload: { apiKey, model, system, messages:[{role, content}] }
const MODEL = process.env.GROK_MODEL || 'grok-beta';

async function chat(payload) {
  const apiKey = payload.apiKey;
  const model = payload.model || MODEL;
  const msgs = [{ role: 'system', content: payload.system || '' }]
    .concat(payload.messages || []).filter((m) => m.content);
  const res = await fetch('https://api.x.ai/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
    body: JSON.stringify({ model, messages: msgs, max_tokens: 300 })
  });
  if (!res.ok) throw new Error('Grok respondeu ' + res.status);
  const data = await res.json();
  const text = data && data.choices && data.choices[0] && data.choices[0].message;
  return (text && text.content) || '...';
}

module.exports = { chat };
