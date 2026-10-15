#!/usr/bin/env node
// Browser smoke test for the exported Godot web build.
//
//   node tools/web_smoke_test.js [build-dir] [out-dir]
//
// Serves the build over HTTP, loads it in headless Chromium twice (a touch phone
// and a keyboard desktop), drives the player through the on-screen buttons and
// keyboard, and checks the state the game publishes on window.__game.
// Screenshots land in out-dir. Exit code 1 if any check fails.
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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const failures = [];
function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? '  ' + detail : ''}`);
  if (!ok) failures.push(name);
}

async function waitForState(page, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let state = null;
  while (Date.now() < deadline) {
    state = await page.evaluate(() => window.__game || null);
    if (state && predicate(state)) return state;
    await sleep(50);
  }
  throw new Error(`timed out waiting for ${label}; last state: ${JSON.stringify(state)}`);
}

async function openGame(browser, outDir, label, contextOptions) {
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  const consoleLines = [];
  page.on('console', (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => consoleLines.push(`[pageerror] ${e.message}`));
  page.on('crash', () => consoleLines.push('[crash] page crashed'));
  return { context, page, consoleLines };
}

async function phoneScenario(browser, base, outDir) {
  console.log('\n== Phone (touch) scenario ==');
  const phone = devices['Pixel 7'];
  const { context, page, consoleLines } = await openGame(browser, outDir, 'phone', {
    userAgent: phone.userAgent, viewport: { width: 915, height: 412 },
    deviceScaleFactor: 1, isMobile: true, hasTouch: true,
  });
  const cdp = await context.newCDPSession(page);
  const touchHold = async (pt, ms) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: pt.x, y: pt.y, id: 1 }] });
    await sleep(ms);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  };
  try {
    await page.goto(`${base}/index.html`, { waitUntil: 'load' });
    const s0 = await waitForState(page, (s) => s.booted, 120000, 'boot');
    check('phone: game booted', true, `version ${s0.version}`);
    check('phone: touchscreen detected', s0.touch === true, JSON.stringify({ touch: s0.touch }));
    check('phone: four touch buttons laid out', s0.buttons && Object.keys(s0.buttons).length === 4, JSON.stringify(s0.buttons));
    check('phone: viewport expanded sideways', s0.viewport && s0.viewport.w > s0.viewport.h, JSON.stringify(s0.viewport));
    await sleep(600);
    await page.screenshot({ path: path.join(outDir, 'phone-boot.png') });

    const start = await waitForState(page, (s) => s.on_floor, 5000, 'standing on floor');
    await touchHold(s0.buttons.right, 1000);
    const afterRight = await waitForState(page, (s) => Math.abs(s.vx) < 1, 3000, 'stop after moving right');
    check('phone: right button moves right', afterRight.x > start.x + 60 && afterRight.facing === 1,
      `x ${start.x} -> ${afterRight.x}`);

    await touchHold(s0.buttons.jump, 80);
    const airborne = await waitForState(page, (s) => s.jumps >= 1, 2000, 'jump registered');
    check('phone: jump button jumps', airborne.jumps >= 1, `jumps=${airborne.jumps} vy=${airborne.vy} on_floor=${airborne.on_floor}`);
    await sleep(250);
    await page.screenshot({ path: path.join(outDir, 'phone-jump.png') });
    const landed = await waitForState(page, (s) => s.on_floor, 3000, 'landing');
    check('phone: lands back on a surface', landed.on_floor, `y=${landed.y}`);

    await touchHold(s0.buttons.attack, 60);
    const attacked = await waitForState(page, (s) => s.attacks >= 1, 2000, 'attack registered');
    check('phone: attack button attacks', attacked.attacks >= 1, `attacks=${attacked.attacks}`);

    const beforeLeft = await page.evaluate(() => window.__game);
    await touchHold(s0.buttons.left, 800);
    const afterLeft = await waitForState(page, (s) => Math.abs(s.vx) < 1, 3000, 'stop after moving left');
    check('phone: left button moves left', afterLeft.x < beforeLeft.x - 40 && afterLeft.facing === -1,
      `x ${beforeLeft.x} -> ${afterLeft.x}`);
    await sleep(300);
    await page.screenshot({ path: path.join(outDir, 'phone-final.png') });
  } catch (err) {
    check('phone: scenario completed', false, err.message);
    await page.screenshot({ path: path.join(outDir, 'phone-error.png') }).catch(() => {});
  } finally {
    const bad = consoleLines.filter((l) => /pageerror|crash|\[error\]|USER ERROR|SCRIPT ERROR/i.test(l));
    check('phone: no page errors', bad.length === 0, bad.slice(0, 5).join(' | '));
    fs.writeFileSync(path.join(outDir, 'phone-console.log'), consoleLines.join('\n'));
    await context.close();
  }
}

async function desktopScenario(browser, base, outDir) {
  console.log('\n== Desktop (keyboard) scenario ==');
  const { context, page, consoleLines } = await openGame(browser, outDir, 'desktop', {
    viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1,
  });
  try {
    await page.goto(`${base}/index.html`, { waitUntil: 'load' });
    const s0 = await waitForState(page, (s) => s.booted, 120000, 'boot');
    check('desktop: game booted', true, `version ${s0.version}`);
    check('desktop: no touchscreen detected', s0.touch === false, JSON.stringify({ touch: s0.touch }));
    await sleep(600);
    await page.mouse.click(640, 360); // make sure the canvas has keyboard focus
    await page.screenshot({ path: path.join(outDir, 'desktop-boot.png') });

    const start = await waitForState(page, (s) => s.on_floor, 5000, 'standing on floor');
    await page.keyboard.down('ArrowRight'); await sleep(1000); await page.keyboard.up('ArrowRight');
    const afterRight = await waitForState(page, (s) => Math.abs(s.vx) < 1, 3000, 'stop after moving right');
    check('desktop: arrow key moves right', afterRight.x > start.x + 60, `x ${start.x} -> ${afterRight.x}`);

    await page.keyboard.press('Space');
    const jumped = await waitForState(page, (s) => s.jumps >= 1, 2000, 'jump registered');
    check('desktop: space jumps', jumped.jumps >= 1, `jumps=${jumped.jumps}`);
    await waitForState(page, (s) => s.on_floor, 3000, 'landing');

    await page.keyboard.press('x');
    const attacked = await waitForState(page, (s) => s.attacks >= 1, 2000, 'attack registered');
    check('desktop: x attacks', attacked.attacks >= 1, `attacks=${attacked.attacks}`);
    await sleep(300);
    await page.screenshot({ path: path.join(outDir, 'desktop-final.png') });
  } catch (err) {
    check('desktop: scenario completed', false, err.message);
    await page.screenshot({ path: path.join(outDir, 'desktop-error.png') }).catch(() => {});
  } finally {
    const bad = consoleLines.filter((l) => /pageerror|crash|\[error\]|USER ERROR|SCRIPT ERROR/i.test(l));
    check('desktop: no page errors', bad.length === 0, bad.slice(0, 5).join(' | '));
    fs.writeFileSync(path.join(outDir, 'desktop-console.log'), consoleLines.join('\n'));
    await context.close();
  }
}

(async () => {
  const buildDir = path.resolve(process.argv[2] || 'build/web');
  const outDir = path.resolve(process.argv[3] || 'build/smoke');
  fs.mkdirSync(outDir, { recursive: true });
  if (!fs.existsSync(path.join(buildDir, 'index.html'))) {
    console.error(`No index.html in ${buildDir}. Export the web build first.`);
    process.exit(2);
  }
  const server = await serve(buildDir);
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      '--autoplay-policy=no-user-gesture-required'],
  });
  try {
    await phoneScenario(browser, base, outDir);
    await desktopScenario(browser, base, outDir);
  } finally {
    await browser.close();
    server.close();
  }
  console.log(`\n${failures.length === 0 ? 'ALL CHECKS PASSED' : failures.length + ' CHECK(S) FAILED'}; screenshots in ${outDir}`);
  process.exit(failures.length === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
