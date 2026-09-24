// Measures Big Picture frame rate over the DevTools protocol while you
// navigate with the controller.
//   node tools/prof.js [seconds] [page title part]
const { connect } = require('./cdp');
(async () => {
  const secs = Number(process.argv[2] || 10);
  const c = await connect(process.argv[3] || 'Big Picture');
  const result = await c.evaluate(`new Promise((done) => {
    const frames = []; const end = performance.now() + ${secs} * 1000;
    const tick = (t) => { frames.push(t); if (t < end) requestAnimationFrame(tick); else {
      const d = frames.slice(1).map((x, i) => x - frames[i]).sort((a, b) => a - b);
      const avg = 1000 / (d.reduce((a, b) => a + b, 0) / d.length);
      const p1 = 1000 / d[Math.floor(d.length * 0.99)];
      done({ frames: frames.length, avgFps: +avg.toFixed(1), low1pctFps: +p1.toFixed(1) });
    } };
    requestAnimationFrame(tick);
  })`);
  console.log(`${c.page.title}: ${JSON.stringify(result)}`);
  c.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
