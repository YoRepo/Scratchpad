#!/usr/bin/env node
// Browser smoke test for the exported Godot web build.
//
//   node tools/web_smoke_test.js [build-dir] [out-dir]
//
// Serves the build over HTTP and loads it in headless Chromium twice: a touch
// phone driven through the on-screen buttons, and a keyboard desktop driven
// through the keys. The desktop run tours every engine feature. Both runs read
// the state the game publishes on window.__game. Screenshots land in out-dir.
// Exit code 1 if any check fails.
'use strict';

const { chromium, devices } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json',
  '.css': 'text/css', '.svg': 'image/svg+xml',
};
const KEYS = {
  left: 'ArrowLeft', right: 'ArrowRight', up: 'ArrowUp', down: 'ArrowDown',
  jump: 'Space', attack: 'x', interact: 'e',
};
const PHONE_VIEWPORT = { width: 915, height: 412 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const failures = [];
let outDir = '';

function serve(dir) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const urlPath = decodeURIComponent(req.url.split('?')[0]);
      const file = path.join(dir, urlPath === '/' ? 'index.html' : urlPath);
      if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end(); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? '  ' + detail : ''}`);
  if (!ok) failures.push(name);
}

const state = (page) => page.evaluate(() => window.__game || null);

async function waitFor(page, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let s = null;
  while (Date.now() < deadline) {
    s = await state(page);
    if (s && predicate(s)) return s;
    await sleep(25);
  }
  throw new Error(`timed out waiting for ${label}; last state: ${JSON.stringify(s)}`);
}

// ---- Drivers: the same verbs for keyboard and touch -------------------------

function keyboardDriver(page) {
  const held = new Set();
  return {
    async hold(action) { const k = KEYS[action]; if (!held.has(k)) { await page.keyboard.down(k); held.add(k); } },
    async release(action) { const k = KEYS[action]; if (held.has(k)) { await page.keyboard.up(k); held.delete(k); } },
    async releaseAll() { for (const k of [...held]) await page.keyboard.up(k); held.clear(); },
    async tap(action, ms = 60) { await this.hold(action); await sleep(ms); await this.release(action); },
  };
}

function touchDriver(page, cdp, buttons) {
  const active = new Map(); // action -> {x, y, id}
  let nextId = 1;
  const points = () => [...active.values()].map((p) => ({ x: p.x, y: p.y, id: p.id }));
  return {
    async hold(action) {
      if (active.has(action)) return;
      const b = buttons()[action];
      if (!b) throw new Error(`no touch button for ${action}`);
      active.set(action, { x: b.x, y: b.y, id: nextId++ });
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: points() });
    },
    async release(action) {
      if (!active.has(action)) return;
      active.delete(action);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: points() });
    },
    async releaseAll() { if (active.size === 0) return; active.clear(); await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); },
    async tap(action, ms = 60) { await this.hold(action); await sleep(ms); await this.release(action); },
  };
}

// Turn to face a world x without moving more than a step.
async function faceToward(page, drv, targetX) {
  const s = await state(page);
  const want = s.x < targetX ? 1 : -1;
  if (s.facing !== want) { await drv.tap(want === 1 ? 'right' : 'left', 15); await sleep(100); }
  return state(page);
}

// Walk until the knight's x is within tol of targetX. Holds a direction while
// far away and taps it in short bursts when close, so it never overshoots.
async function walkTo(page, drv, targetX, { tol = 6, timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let s = await state(page);
  while (Math.abs(s.x - targetX) > tol) {
    if (Date.now() > deadline) { await drv.releaseAll(); throw new Error(`walkTo(${targetX}) stuck at x=${s.x}`); }
    const dir = s.x < targetX ? 'right' : 'left';
    const other = dir === 'right' ? 'left' : 'right';
    await drv.release(other);
    if (Math.abs(s.x - targetX) > 40) {
      await drv.hold(dir);
      await sleep(30);
    } else {
      await drv.release(dir);
      await drv.tap(dir, 30);
      await sleep(120);
    }
    s = await state(page);
  }
  await drv.releaseAll();
  await sleep(120);
  return state(page);
}

async function openPage(browser, contextOptions) {
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  const consoleLines = [];
  page.on('console', (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => consoleLines.push(`[pageerror] ${e.message}`));
  page.on('crash', () => consoleLines.push('[crash] page crashed'));
  return { context, page, consoleLines };
}

async function finish(label, context, page, consoleLines) {
  const bad = consoleLines.filter((l) => /pageerror|crash|\[error\]|USER ERROR|SCRIPT ERROR/i.test(l));
  check(`${label}: no page errors`, bad.length === 0, bad.slice(0, 5).join(' | '));
  fs.writeFileSync(path.join(outDir, `${label}-console.log`), consoleLines.join('\n'));
  await context.close();
}

// ---- Desktop: the full feature tour on the keyboard --------------------------

async function desktopTour(browser, base) {
  console.log('\n== Desktop (keyboard) feature tour ==');
  const { context, page, consoleLines } = await openPage(browser, { viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  const drv = keyboardDriver(page);
  const shot = (name) => page.screenshot({ path: path.join(outDir, `desktop-${name}.png`) });
  try {
    await page.goto(`${base}/index.html?level=meadow`, { waitUntil: 'load' });
    let s = await waitFor(page, (g) => g.booted && g.level, 120000, 'boot');
    check('desktop: booted into the meadow', s.level === 'Marginalia Meadow', `level=${s.level} version=${s.version}`);
    check('desktop: no touchscreen detected', s.touch === false);
    await page.mouse.click(640, 360);
    s = await waitFor(page, (g) => g.on_floor && g.state === 'Idle', 5000, 'standing idle');
    const L = s.landmarks;
    await shot('boot');

    // 1. Talk to the monk.
    s = await walkTo(page, drv, L.npcs.Anselm.x - 12);
    check('desktop: NPC gets focused when close', s.interactable === 'Brother Anselm', `interactable=${s.interactable}`);
    await drv.tap('interact');
    s = await waitFor(page, (g) => g.dialogue_active, 3000, 'dialogue to start');
    check('desktop: interact starts dialogue, player talks', s.state === 'Talk', `state=${s.state} line=${s.dialogue_index + 1}/${s.dialogue_total}`);
    await shot('dialogue');
    for (let i = 0; i < 8 && (await state(page)).dialogue_active; i++) { await drv.tap('interact'); await sleep(150); }
    s = await waitFor(page, (g) => !g.dialogue_active && g.state === 'Idle', 3000, 'dialogue to end');
    check('desktop: dialogue ends and control returns', true);

    // 2. Ladder: climb up onto the platform, then climb back down from the top.
    const ladder = L.climbables.LadderA;
    await walkTo(page, drv, ladder.x, { tol: 4 });
    await drv.hold('up');
    s = await waitFor(page, (g) => g.state === 'Climb', 3000, 'grab ladder');
    check('desktop: Up grabs the ladder', s.state === 'Climb' && Math.abs(s.x - ladder.x) < 1, `x=${s.x}`);
    await shot('ladder');
    s = await waitFor(page, (g) => g.state !== 'Climb', 6000, 'climb to the top');
    await drv.release('up');
    s = await waitFor(page, (g) => g.on_floor, 3000, 'stand on the platform');
    check('desktop: climbing off the top lands on the platform', Math.abs(s.y - ladder.top) < 2 && s.state !== 'Climb', `y=${s.y} top=${ladder.top}`);
    await drv.hold('down');
    s = await waitFor(page, (g) => g.state === 'Climb', 3000, 'grab ladder from the top');
    check('desktop: Down at the top grabs the ladder downward', true, `y=${s.y}`);
    s = await waitFor(page, (g) => g.state !== 'Climb', 6000, 'climb to the bottom');
    await drv.release('down');
    s = await waitFor(page, (g) => g.on_floor && g.state === 'Idle', 3000, 'back on the ground');
    check('desktop: reaching the bottom steps off onto the ground', Math.abs(s.y - ladder.bottom) < 2, `y=${s.y} bottom=${ladder.bottom}`);

    // 3. Hill: run over the slope without leaving the floor.
    const hill = L.solids.Hill;
    await walkTo(page, drv, hill.x - 40);
    await drv.hold('right');
    let minY = 999, offFloor = 0, samples = 0;
    const until = Date.now() + 8000;
    while (Date.now() < until) {
      s = await state(page);
      if (s.x > hill.x + hill.w + 30) break;
      if (s.x > hill.x + 10 && s.x < hill.x + hill.w - 10) { samples++; minY = Math.min(minY, s.y); if (!s.on_floor) offFloor++; }
      await sleep(25);
    }
    await drv.releaseAll();
    check('desktop: slope is walkable and keeps the knight grounded', minY <= hill.y + 2 && offFloor <= 2 && samples > 10,
      `minY=${minY} plateau=${hill.y} offFloor=${offFloor}/${samples}`);
    await shot('hill');

    // 4. Crouch and stand.
    await drv.hold('down');
    s = await waitFor(page, (g) => g.state === 'Crouch', 2000, 'crouch');
    await shot('crouch');
    await drv.release('down');
    s = await waitFor(page, (g) => g.state === 'Idle', 2000, 'stand up');
    check('desktop: Down crouches, release stands', true);

    // 5. Attack the snail.
    const snail = L.dummies.Snail;
    await walkTo(page, drv, snail.x - 22, { tol: 4 });
    s = await faceToward(page, drv, snail.x);
    const hpBefore = s.landmarks.dummies.Snail.hp;
    await drv.tap('attack');
    s = await waitFor(page, (g) => g.landmarks.dummies.Snail.hp < hpBefore, 3000, 'snail to take damage');
    check('desktop: sword hits the snail', s.landmarks.dummies.Snail.hp === hpBefore - 10, `hp ${hpBefore} -> ${s.landmarks.dummies.Snail.hp}`);
    await shot('attack');

    // 6. Rope up to the high platform, then drop through it with Down+Jump.
    const rope = L.climbables.RopeB;
    await walkTo(page, drv, rope.x, { tol: 4 });
    await drv.hold('up');
    s = await waitFor(page, (g) => g.state === 'Climb', 3000, 'grab rope');
    s = await waitFor(page, (g) => g.state !== 'Climb', 8000, 'climb the rope');
    await drv.release('up');
    s = await waitFor(page, (g) => g.on_floor, 3000, 'stand on the high platform');
    check('desktop: rope leads onto the high platform', Math.abs(s.y - rope.top) < 2, `y=${s.y} top=${rope.top}`);
    // Step away from the rope first: Down right at its top grabs it instead of crouching.
    await walkTo(page, drv, rope.x - 40, { tol: 6 });
    await drv.hold('down');
    await sleep(80);
    await drv.tap('jump');
    s = await waitFor(page, (g) => g.state === 'Air' && g.y > rope.top + 10, 3000, 'drop through');
    await drv.release('down');
    s = await waitFor(page, (g) => g.on_floor && g.y > rope.top + 50, 4000, 'land below');
    check('desktop: Down+Jump drops through the one-way platform', s.y > rope.top + 50, `y=${s.y}`);

    // 7. Portal to the cloister.
    const portal = L.portals.ToCloister;
    s = await walkTo(page, drv, portal.x, { tol: 6 });
    check('desktop: portal gets focused', s.interactable === 'Cloister', `interactable=${s.interactable}`);
    await drv.tap('interact');
    s = await waitFor(page, (g) => g.level === 'Cloister', 5000, 'level change');
    await sleep(300);
    s = await state(page);
    check('desktop: portal travels to the cloister at its spawn', Math.abs(s.x - s.landmarks.spawns.entrance.x) < 2, `x=${s.x}`);
    await shot('cloister');
  } catch (err) {
    check('desktop: tour completed', false, err.message);
    await shot('error').catch(() => {});
  } finally {
    await drv.releaseAll().catch(() => {});
    await finish('desktop', context, page, consoleLines);
  }
}

// ---- Phone: touch buttons ------------------------------------------------------

async function phoneScenario(browser, base) {
  console.log('\n== Phone (touch) scenario ==');
  const phone = devices['Pixel 7'];
  const { context, page, consoleLines } = await openPage(browser, {
    userAgent: phone.userAgent, viewport: PHONE_VIEWPORT, deviceScaleFactor: 1, isMobile: true, hasTouch: true,
  });
  const cdp = await context.newCDPSession(page);
  let latest = null;
  const drv = touchDriver(page, cdp, () => latest.buttons);
  const shot = (name) => page.screenshot({ path: path.join(outDir, `phone-${name}.png`) });
  try {
    await page.goto(`${base}/index.html?level=meadow`, { waitUntil: 'load' });
    latest = await waitFor(page, (g) => g.booted && g.level, 120000, 'boot');
    check('phone: touchscreen detected', latest.touch === true);
    check('phone: seven touch buttons laid out', Object.keys(latest.buttons || {}).length === 7, Object.keys(latest.buttons || {}).join(','));
    check('phone: viewport expanded sideways', latest.viewport.w > latest.viewport.h, JSON.stringify(latest.viewport));
    await sleep(400);
    await shot('boot');
    const L = latest.landmarks;

    let s = await walkTo(page, drv, L.npcs.Anselm.x - 12);
    check('phone: d-pad walks to the monk', s.interactable === 'Brother Anselm', `x=${s.x} interactable=${s.interactable}`);
    await drv.tap('interact');
    s = await waitFor(page, (g) => g.dialogue_active, 3000, 'dialogue via TALK button');
    check('phone: TALK button starts dialogue', true);
    await shot('dialogue');
    for (let i = 0; i < 8 && (await state(page)).dialogue_active; i++) { await drv.tap('interact'); await sleep(150); }
    await waitFor(page, (g) => !g.dialogue_active, 3000, 'dialogue to end');

    const ladder = L.climbables.LadderA;
    await walkTo(page, drv, ladder.x, { tol: 4 });
    await drv.hold('up');
    s = await waitFor(page, (g) => g.state === 'Climb', 3000, 'grab ladder by touch');
    s = await waitFor(page, (g) => g.state !== 'Climb', 6000, 'climb up by touch');
    await drv.release('up');
    s = await waitFor(page, (g) => g.on_floor, 3000, 'stand on platform');
    check('phone: Up button climbs the ladder', Math.abs(s.y - ladder.top) < 2, `y=${s.y}`);
    await shot('ladder');

    const jumpsBefore = s.jumps;
    await drv.tap('jump', 80);
    s = await waitFor(page, (g) => g.jumps > jumpsBefore, 2000, 'jump by touch');
    check('phone: JUMP button jumps', true);
    const attacksBefore = s.attacks;
    await drv.tap('attack', 80);
    s = await waitFor(page, (g) => g.attacks > attacksBefore, 2000, 'attack by touch');
    check('phone: ATK button attacks', true);
    await waitFor(page, (g) => g.on_floor && g.state === 'Idle', 3000, 'settle');
    await drv.hold('down');
    s = await waitFor(page, (g) => g.state === 'Climb' || g.state === 'Crouch', 2000, 'down by touch');
    check('phone: Down button crouches or grabs down', true, `state=${s.state}`);
    await drv.releaseAll();
    await sleep(300);
    await shot('final');
  } catch (err) {
    check('phone: scenario completed', false, err.message);
    await shot('error').catch(() => {});
  } finally {
    await drv.releaseAll().catch(() => {});
    await finish('phone', context, page, consoleLines);
  }
}

(async () => {
  const buildDir = path.resolve(process.argv[2] || 'build/web');
  outDir = path.resolve(process.argv[3] || 'build/smoke');
  fs.mkdirSync(outDir, { recursive: true });
  if (!fs.existsSync(path.join(buildDir, 'index.html'))) {
    console.error(`No index.html in ${buildDir}. Export the web build first.`);
    process.exit(2);
  }
  const server = await serve(buildDir);
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  try {
    await desktopTour(browser, base);
    await phoneScenario(browser, base);
  } finally {
    await browser.close();
    server.close();
  }
  console.log(`\n${failures.length === 0 ? 'ALL CHECKS PASSED' : failures.length + ' CHECK(S) FAILED'}; screenshots in ${outDir}`);
  process.exit(failures.length === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
