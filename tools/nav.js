// Measure Big Picture frame rate while pressing a key repeatedly (simulated navigation).
const [,, key = "ArrowRight", presses = "15"] = process.argv;
const targets = await (await fetch("http://localhost:8080/json")).json();
const t = targets.find(x => x.title === "Steam Big Picture Mode");
const ws = new WebSocket(t.webSocketDebuggerUrl);
let id = 0; const pending = {};
const send = (method, params = {}) => new Promise(r => { pending[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
ws.onmessage = m => { const d = JSON.parse(m.data); pending[d.id]?.(d.result); };
await new Promise(r => ws.onopen = r);
const codes = { ArrowRight: 39, ArrowLeft: 37, ArrowDown: 40, ArrowUp: 38 };
const meas = send("Runtime.evaluate", { awaitPromise: true, returnByValue: true, expression: `new Promise(r => { const ft = []; let last = performance.now(); const t0 = last; function f(t) { ft.push(t - last); last = t; if (t - t0 < ${presses * 200 + 500}) requestAnimationFrame(f); else { ft.sort((a,b)=>a-b); r({ fps: +(ft.length / ((t - t0)/1000)).toFixed(1), p95ms: +ft[Math.floor(ft.length*0.95)].toFixed(1), worstMs: +ft[ft.length-1].toFixed(1), over50ms: ft.filter(x => x > 50).length }); } } requestAnimationFrame(f); })` });
for (let i = 0; i < +presses; i++) {
  for (const type of ["rawKeyDown", "keyUp"]) await send("Input.dispatchKeyEvent", { type, key, code: key, windowsVirtualKeyCode: codes[key] });
  await new Promise(r => setTimeout(r, 200));
}
console.log(key, JSON.stringify((await meas).result.value));
ws.close();
