import puppeteer from 'puppeteer';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE = 'http://127.0.0.1:4567';

const DESKTOP_PAGES = [
  { name: '01_home',       url: '/' },
  { name: '02_banks',      url: '/banks' },
  { name: '03_jobs',       url: '/jobs' },
  { name: '04_log',        url: '/log' },
  { name: '05_api_calls',  url: '/api-calls' },
  { name: '06_settings',   url: '/settings' },
];

const MOBILE_PAGES = [
  { name: '07_mobile_home',      url: '/mobile/' },
  { name: '08_mobile_banks',     url: '/mobile/banks' },
  { name: '09_mobile_jobs',      url: '/mobile/jobs' },
  { name: '10_mobile_log',       url: '/mobile/log' },
  { name: '11_mobile_api_calls', url: '/mobile/api-calls' },
  { name: '12_mobile_settings',  url: '/mobile/settings' },
];

async function screenshot(page, name, url, viewport) {
  await page.setViewport(viewport);
  await page.goto(BASE + url, { waitUntil: 'networkidle0', timeout: 15000 });
  await new Promise(r => setTimeout(r, 600));
  const file = path.join(__dirname, `${name}.png`);
  // clip to exactly the viewport — no full-page scroll
  await page.screenshot({
    path: file,
    clip: { x: 0, y: 0, width: viewport.width, height: viewport.height },
  });
  console.log(`  ✓ ${name}.png  (${viewport.width}×${viewport.height})`);
}

const browser = await puppeteer.launch({
  headless: 'new',
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
});
const page = await browser.newPage();

// Desktop: 1280 wide × 480 tall  → renders ≈ 4 cm tall in a standard document column
console.log('\n── Desktop pages (1280×480) ──');
for (const p of DESKTOP_PAGES) {
  await screenshot(page, p.name, p.url, { width: 1280, height: 480 });
}

// Mobile: 390 wide × 560 tall  → shows nav bar + first content cards
console.log('\n── Mobile pages (390×560) ──');
for (const p of MOBILE_PAGES) {
  await screenshot(page, p.name, p.url, { width: 390, height: 560 });
}

await browser.close();
console.log('\nDone. All screenshots saved to screenshots/');
