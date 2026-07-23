// trigger pull-request capture workflow
const { chromium } = require('playwright');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const BASE = 'https://studios.warext.com';
const outDir = path.join(process.cwd(), 'studios-live-screenshots');
fs.mkdirSync(outDir, { recursive: true });

const initial = [
  '/',
  '/magaza',
  '/haberler',
  '/iletisim',
  '/yardim-merkezi',
  '/hesap/giris-yap',
  '/hesap/olustur',
  '/sifremi-unuttum',
  '/mail-dogrula',
  '/sepet',
  '/404'
];

function safeName(urlPath, index) {
  let name = decodeURIComponent(urlPath.split('?')[0])
    .replace(/^\/+|\/+$/g, '')
    .replace(/[^a-zA-Z0-9ğüşöçıİĞÜŞÖÇ_-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  if (!name) name = 'ana-sayfa';
  return String(index + 1).padStart(2, '0') + '_' + name;
}

function allowedPath(p) {
  if (!p || !p.startsWith('/')) return false;
  if (/\.(xml|txt|json|js|css|png|jpg|jpeg|gif|webp|svg|ico|woff2?|ttf|map)(\?|$)/i.test(p)) return false;
  if (/^\/(yonetim-paneli|panel|api|callback|cikis-yap|changeLanguage|kurulum)(\/|$)/i.test(p)) return false;
  if (/^\/(musteri|bakiye|odeme)(\/|$)/i.test(p)) return false;
  return /^\/(?:$|magaza(?:\/[^?#]+)?|urun\/[^?#]+|haberler|haber\/[^?#]+|iletisim|yardim-merkezi(?:\/[^?#]+)?|sayfa\/[^?#]+|hesap\/(?:giris-yap|olustur)|sifremi-unuttum|mail-dogrula|sepet|404)$/i.test(p);
}

async function collectLinks(page, urlPath, set) {
  try {
    await page.goto(BASE + urlPath, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(2500);
    const hrefs = await page.locator('a[href]').evaluateAll(els => els.map(a => a.href));
    for (const href of hrefs) {
      try {
        const u = new URL(href);
        if (u.origin !== BASE) continue;
        if (allowedPath(u.pathname)) set.add(u.pathname + (u.search || ''));
      } catch {}
    }
  } catch (e) {
    console.log('collect failed', urlPath, e.message);
  }
}

async function compressUnder1MB(inputPng, outputJpg) {
  let quality = 82;
  let width = null;
  const max = 1024 * 1024;
  while (quality >= 35) {
    let pipeline = sharp(inputPng).flatten({ background: '#ffffff' }).jpeg({ quality, mozjpeg: true });
    if (width) pipeline = pipeline.resize({ width, withoutEnlargement: true });
    await pipeline.toFile(outputJpg);
    const size = fs.statSync(outputJpg).size;
    if (size <= max) return size;
    quality -= 8;
    if (quality < 50 && !width) width = 1200;
    else if (quality < 42 && width === 1200) width = 1000;
  }
  await sharp(inputPng).flatten({ background: '#ffffff' }).resize({ width: 900, withoutEnlargement: true }).jpeg({ quality: 35, mozjpeg: true }).toFile(outputJpg);
  return fs.statSync(outputJpg).size;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1,
    locale: 'tr-TR',
    timezoneId: 'Europe/Istanbul',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36'
  });
  const page = await context.newPage();
  const routes = new Set(initial);

  for (const p of ['/', '/magaza', '/haberler', '/yardim-merkezi']) {
    await collectLinks(page, p, routes);
  }

  for (const p of [...routes].filter(x => x.startsWith('/magaza') || x === '/haberler' || x.startsWith('/yardim-merkezi'))) {
    await collectLinks(page, p, routes);
  }

  const ordered = [...routes].filter(allowedPath).sort((a, b) => {
    const ai = initial.indexOf(a), bi = initial.indexOf(b);
    if (ai !== -1 || bi !== -1) return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
    return a.localeCompare(b, 'tr');
  });

  const manifest = [];
  let i = 0;
  for (const p of ordered) {
    const name = safeName(p, i++);
    const png = path.join(outDir, name + '.png');
    const jpg = path.join(outDir, name + '.jpg');
    let status = null;
    let finalUrl = null;
    let title = null;
    let error = null;
    try {
      const response = await page.goto(BASE + p, { waitUntil: 'networkidle', timeout: 70000 });
      status = response ? response.status() : null;
      await page.waitForTimeout(3000);
      finalUrl = page.url();
      title = await page.title();
      await page.evaluate(() => {
        document.querySelectorAll('[style*="animation"], .loading, .loader, .preloader').forEach(el => {
          if (el.classList.contains('loading') || el.classList.contains('loader') || el.classList.contains('preloader')) el.style.display = 'none';
        });
      });
      await page.screenshot({ path: png, fullPage: true, animations: 'disabled' });
      const size = await compressUnder1MB(png, jpg);
      fs.unlinkSync(png);
      manifest.push({ path: p, finalUrl, title, status, file: path.basename(jpg), bytes: size });
      console.log('captured', p, path.basename(jpg), size);
    } catch (e) {
      error = e.message;
      manifest.push({ path: p, finalUrl, title, status, error });
      console.log('capture failed', p, error);
    }
  }

  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  fs.writeFileSync(path.join(outDir, 'README.txt'), 'Warext Studios canlı siteden alınan gerçek ekran görüntüleri.\nKaynak: ' + BASE + '\nTarih: ' + new Date().toISOString() + '\nHer JPG 1 MB altındadır.\n');
  await browser.close();
})();
