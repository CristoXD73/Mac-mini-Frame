// Evaluate an expression in a Steam CEF target via the DevTools protocol.
const [,, title, expr] = process.argv;
const targets = await (await fetch("http://localhost:8080/json")).json();
const t = targets.find(x => x.title === title) || targets.find(x => x.title.includes(title));
if (!t) { console.log("no target", title); process.exit(1); }
const ws = new WebSocket(t.webSocketDebuggerUrl);
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression: expr, awaitPromise: true, returnByValue: true } }));
ws.onmessage = m => { const r = JSON.parse(m.data); if (r.id === 1) { console.log(JSON.stringify(r.result?.result?.value ?? r.result, null, 1)); ws.close(); } };
