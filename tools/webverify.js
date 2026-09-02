#!/usr/bin/env node
// §48 Phase 11 — in-browser verification driver (playwright-core + system
// chromium). Usage:
//   node tools/webverify.js "http://localhost:8901/index.html?CC_SMOKE_TEST=1&cc_portal=mock" CC_SMOKE_OK
//   node tools/webverify.js ".../index.html?CC_UI_VERIFY=1&cc_portal=mock" CC_UI_VERIFY_PASS
// Serve web-export/ first:  (cd web-export && python3 -m http.server 8901)
// npm i playwright-core once; chromium flags target SwiftShader WebGL2.
const { chromium } = require('playwright-core');
(async () => {
  const url = process.argv[2];
  const want = process.argv[3] || 'CC_SMOKE_OK';
  const browser = await chromium.launch({
    executablePath: '/usr/bin/chromium',
    args: ['--no-sandbox', '--disable-gpu', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const lines = [];
  page.on('console', (msg) => {
    const t = msg.text();
    lines.push(t);
    if (t.includes('CC_') || t.includes('WP_BREAK') || t.includes('ad_') || t.includes('Provider:') || t.includes('PASS') || t.includes('FAIL')) {
      console.log('[console]', t.slice(0, 200));
    }
  });
  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  const deadline = Date.now() + 240000;
  let found = false;
  while (Date.now() < deadline) {
    if (lines.some((l) => l.includes(want))) { found = true; break; }
    await page.waitForTimeout(1000);
  }
  await page.screenshot({ path: '/tmp/web_final.png' });
  // Report mock portal ad call counts if present.
  try {
    const counts = await page.evaluate(() => window.CCPortal ? JSON.stringify(window.CCPortal.mockCounts) : 'no-bridge');
    console.log('[portal]', counts);
  } catch (e) { console.log('[portal] n/a'); }
  console.log(found ? 'WEBVERIFY_PASS' : 'WEBVERIFY_FAIL (no ' + want + ')');
  await browser.close();
  process.exit(found ? 0 : 1);
})().catch((e) => { console.error('WEBVERIFY_ERROR', e.message); process.exit(2); });
