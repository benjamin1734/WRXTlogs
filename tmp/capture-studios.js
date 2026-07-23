// fast live capture workflow
const { chromium } = require('playwright');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const BASE = 'https://studios.warext.com';
const outDir = path.join(process.cwd(), 'studios-live-screenshots');
fs.mkdirSync(outDir, { recursive: true });

const initial = ['/', '/magaza', '/haberler', '/iletisim', '/yardim-merkezi', '/hesap/giris-yap', '/hesap/olustur', '/sifremi-unuttum', '/mail-dogrula', '/sepet', '/404'];

function safeName(urlPath, index) {
  let name = decodeURIComponent(urlPath.split('?')[0]).replace(/^\/+|\/+$/g, '').replace(/[^a-zA-Z0-9ğüşöçıİĞÜŞÖÇ_-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
  if (!name) name = 'ana-sayfa';
  return String(index + 1).padStart(2, '0') + '_' + name;
}

function allowedPath(p) {
  if (!p || !p.startsWith('/')) return false;
  if (/\.(xml|txt|json|js|css|png|jpg|jpeg|gif|webp|svg|ico|woff2?|ttf|map)(\?|$)/i.test(p)) return false;
  if (/^\/(yonetim-paneli|panel|api|callback|cikis-yap|changeLanguage|kurulum|musteri|bakiye|odeme)(\/|$)/i.test(p)) return false;
  return /^\/(?:$|magaza(?:\/[^?#]+)?|urun\/[^?#]+|haberler|haber\/[^?#]+|iletisim|yardim-merkezi(?:\/[^?#]+)?|sayfa\/[^?#]+|hesap\/(?:giris-yap|olustur)|sifremi-unuttum|mail-dogrula|sepet|404)$/i.test(p);
}

async function openPage(page, route) {
  const response = await page.goto(BASE + route, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2200);
  return response;
}

async function collectLinks(page, route, set) {
  try {
    await openPage(page, route);
    const hrefs = await page.locator('a[href]').evaluateAll(els => els.map(a => a.href));
    for (const href of hrefs) {
      try {
        const u = new URL(href);
        if (u.origin === BASE && allowedPath(u.pathname)) set.add(u.pathname);
      } catch {}
    }
  } catch (e) { console.log('collect failed', route, e.message); }
}

async function compressUnder1MB(inputPng, outputJpg) {
  const max = 1024 * 1024;
  for (const width of [null, 1300, 1100, 950]) {
    for (const quality of [82, 72, 62, 52, 42, 34]) {
      let pipeline = sharp(inputPng).flatten({ background: '#ffffff' });
      if (width) pipeline = pipeline.resize({ width, withoutEnlargement: true });
      await pipeline.jpeg({ quality, mozjpeg: true }).toFile(outputJpg);
      if (fs.statSync(outputJpg).size <= max) return fs.statSync(outputJpg).size;
    }
  }
  await sharp(inputPng).flatten({ background: '#ffffff' }).resize({ width: 850, withoutEnlargement: true }).jpeg({ quality: 30, mozjpeg: true }).toFile(outputJpg);
  return fs.statSync(outputJpg).size;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1, locale: 'tr-TR', timezoneId: 'Europe/Istanbul',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
  });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  const routes = new Set(initial);

  for (const p of ['/', '/magaza', '/haberler', '/yardim-merkezi']) await collectLinks(page, p, routes);
  for (const p of [...routes].filter(x => x.startsWith('/magaza/') || x.startsWith('/yardim-merkezi/'))) await collectLinks(page, p, routes);

  const ordered = [...routes].filter(allowedPath).sort((a, b) => {
    const ai = initial.indexOf(a), bi = initial.indexOf(b);
    if (ai !== -1 || bi !== -1) return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
    return a.localeCompare(b, 'tr');
  });

  const manifest = [];
  for (let i = 0; i < ordered.length; i++) {
    const route = ordered[i];
    const name = safeName(route, i);
    const png = path.join(outDir, name + '.png');
    const jpg = path.join(outDir, name + '.jpg');
    try {
      const response = await openPage(page, route);
      await page.evaluate(() => {
        document.documentElement.style.scrollBehavior = 'auto';
        document.querySelectorAll('.loading,.loader,.preloader').forEach(el => el.style.display = 'none');
      });
      await page.screenshot({ path: png, fullPage: true, animations: 'disabled' });
      const bytes = await compressUnder1MB(png, jpg);
      fs.unlinkSync(png);
      manifest.push({ path: route, finalUrl: page.url(), title: await page.title(), status: response ? response.status() : null, file: path.basename(jpg), bytes });
      console.log('captured', route, bytes);
    } catch (e) {
      manifest.push({ path: route, error: e.message });
      console.log('capture failed', route, e.message);
    }
  }

  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  fs.writeFileSync(path.join(outDir, 'README.txt'), `Warext Studios canlı siteden alınan gerçek ekran görüntüleri.\nKaynak: ${BASE}\nTarih: ${new Date().toISOString()}\nHer JPG 1 MB altındadır.\n`);
  await browser.close();
})();
