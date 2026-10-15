'use strict';

// Adaptador Anthropic (Messages API).
const MODEL = process.env.ANTHROPIC_MODEL || 'claude-3-haiku-20240307';

async function chat(payload) {
  const msgs = (payload.messages || []).filter((m) => m.content).map((m) => ({
    role: m.role === 'pet' ? 'assistant' : m.role,
    content: m.content
  }));
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': payload.apiKey,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: payload.model || MODEL,
      max_tokens: 300,
      system: payload.system || '',
      messages: msgs
    })
  });
  if (!res.ok) throw new Error('Anthropic respondeu ' + res.status);
  const data = await res.json();
  const block = data && data.content && data.content[0];
  return (block && block.text) || '...';
}

module.exports = { chat };
