// Minimal Chrome DevTools Protocol client for Steam's CEF.
// Steam must be started with -cef-enable-debugging (listens on localhost:8080).
// Restart Steam WITHOUT that flag when done.
//   node tools/cdp.js                 list debuggable pages
//   node tools/cdp.js "<title part>" "<js expression>"
const PORT = process.env.CDP_PORT || 8080;

async function pages() {
  const r = await fetch(`http://127.0.0.1:${PORT}/json`);
  return r.json();
}

async function connect(match) {
  const list = await pages();
  const page = list.find((p) => p.webSocketDebuggerUrl && (p.title || '').includes(match));
  if (!page) throw new Error(`no page matching "${match}". Pages: ${list.map((p) => p.title).join(' | ')}`);
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });
  let id = 0;
  const waiting = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
  };
  const send = (method, params = {}) => new Promise((ok) => {
    const n = ++id; waiting.set(n, ok); ws.send(JSON.stringify({ id: n, method, params }));
  });
  const evaluate = async (expression) => {
    const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails));
    return r.result?.result?.value;
  };
  return { page, send, evaluate, close: () => ws.close() };
}

module.exports = { pages, connect };

if (require.main === module) {
  (async () => {
    const [match, expr] = process.argv.slice(2);
    if (!match) { for (const p of await pages()) console.log(`${p.type}\t${p.title}\t${p.url}`); return; }
    const c = await connect(match);
    console.log(JSON.stringify(await c.evaluate(expr || 'document.title'), null, 2));
    c.close();
  })().catch((e) => { console.error(e.message); process.exit(1); });
}
