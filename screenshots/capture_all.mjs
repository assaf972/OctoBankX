import puppeteer from 'puppeteer';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE = 'http://127.0.0.1:4567';

const DESKTOP_PAGES = [
    { name: 'home', url: '/' },
    { name: 'banks', url: '/banks' },
    { name: 'jobs', url: '/jobs' },
    { name: 'log', url: '/log' },
    { name: 'email_senders', url: '/email_senders' },
    { name: 'settings', url: '/settings' },
];

const MOBILE_PAGES = [
    { name: 'mobile_home', url: '/mobile/' },
    { name: 'mobile_banks', url: '/mobile/banks' },
    { name: 'mobile_jobs', url: '/mobile/jobs' },
    { name: 'mobile_log', url: '/mobile/log' },
    { name: 'mobile_email_senders', url: '/mobile/email_senders' },
    { name: 'mobile_settings', url: '/mobile/settings' },
];

async function screenshot(page, dir, name, url, viewport) {
    await page.setViewport(viewport);
    await page.goto(BASE + url, { waitUntil: 'networkidle0', timeout: 15000 });
    await new Promise(r => setTimeout(r, 800));
    const file = path.join(dir, `${name}.png`);
    await page.screenshot({
        path: file,
        fullPage: false,
    });
    console.log(`  ✓ ${name}.png  (${viewport.width})`);
}

const browser = await puppeteer.launch({
    headless: 'new',
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
});
const page = await browser.newPage();

// ── English screenshots ──
const enDir = path.join(__dirname, 'en');
fs.mkdirSync(enDir, { recursive: true });

// Set locale to English
await page.goto(BASE + '/locale?lang=en', { waitUntil: 'networkidle0', timeout: 15000 });

console.log('\n── English Desktop pages ──');
for (const p of DESKTOP_PAGES) {
    await screenshot(page, enDir, p.name, p.url, { width: 1280, height: 600 });
}

console.log('\n── English Mobile pages ──');
for (const p of MOBILE_PAGES) {
    await screenshot(page, enDir, p.name, p.url, { width: 390, height: 700 });
}

// ── Hebrew screenshots ──
const heDir = path.join(__dirname, 'he');
fs.mkdirSync(heDir, { recursive: true });

// Set locale to Hebrew
await page.goto(BASE + '/locale?lang=he', { waitUntil: 'networkidle0', timeout: 15000 });

console.log('\n── Hebrew Desktop pages ──');
for (const p of DESKTOP_PAGES) {
    await screenshot(page, heDir, p.name, p.url, { width: 1280, height: 600 });
}

console.log('\n── Hebrew Mobile pages ──');
for (const p of MOBILE_PAGES) {
    await screenshot(page, heDir, p.name, p.url, { width: 390, height: 700 });
}

await browser.close();
console.log('\nDone. Screenshots saved to screenshots/en/ and screenshots/he/');
