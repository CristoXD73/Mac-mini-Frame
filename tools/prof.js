// Alternate Left/Right in Big Picture and report frame rate plus where main-thread time went.
const targets = await (await fetch("http://localhost:8080/json")).json();
const t = targets.find(x => x.title === "Steam Big Picture Mode");
const ws = new WebSocket(t.webSocketDebuggerUrl);
let id = 0; const pending = {};
const send = (method, params = {}) => new Promise(r => { pending[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
ws.onmessage = m => { const d = JSON.parse(m.data); pending[d.id]?.(d.result); };
await new Promise(r => ws.onopen = r);
await send("Performance.enable");
const metrics = async () => Object.fromEntries((await send("Performance.getMetrics")).metrics.map(m => [m.name, m.value]));
const N = 24, gap = 180;
const before = await metrics();
const meas = send("Runtime.evaluate", { awaitPromise: true, returnByValue: true, expression: `new Promise(r => { const ft = []; let last = performance.now(); const t0 = last; function f(t) { ft.push(t - last); last = t; if (t - t0 < ${N * gap + 300}) requestAnimationFrame(f); else { ft.sort((a,b)=>a-b); r({ fps: +(ft.length / ((t - t0)/1000)).toFixed(1), median: +ft[ft.length>>1].toFixed(1), p95: +ft[Math.floor(ft.length*0.95)].toFixed(1) }); } } requestAnimationFrame(f); })` });
for (let i = 0; i < N; i++) {
  const key = i % 4 < 2 ? "ArrowRight" : "ArrowLeft", code = key === "ArrowRight" ? 39 : 37;
  for (const type of ["rawKeyDown", "keyUp"]) await send("Input.dispatchKeyEvent", { type, key, code: key, windowsVirtualKeyCode: code });
  await new Promise(r => setTimeout(r, gap));
}
const res = (await meas).result.value, after = await metrics();
const d = k => +((after[k] - before[k]) * 1000).toFixed(0);
const wall = N * gap + 300;
console.log(JSON.stringify({ ...res, mainThreadBusyPct: +(100 * d("TaskDuration") / wall).toFixed(0), scriptMs: d("ScriptDuration"), styleMs: d("RecalcStyleDuration"), layoutMs: d("LayoutDuration") }));
ws.close();
