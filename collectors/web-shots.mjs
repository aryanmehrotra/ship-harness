// Visual evidence for web apps: routes × widths × themes, pixel-diffed against a
// committed baseline, plus console errors and failed requests.
//
// Invoked by scripts/collect.sh, never directly by a model. Reads its config from
// SHIP_COLLECTOR_CONFIG and obeys collectors/CONTRACT.md.
//
// Requires, in the *target* repo:  npm i -D @playwright/test pixelmatch pngjs
//                                  npx playwright install chromium

import fs from 'node:fs';
import path from 'node:path';

const NAME = process.env.SHIP_NAME || 'web';
const MODE = process.env.SHIP_MODE || 'compare';
const OUT = process.env.SHIP_OUT || `.evidence/${NAME}.json`;
const EVID = process.env.SHIP_EVIDENCE_DIR || '.evidence';
const BASE = process.env.SHIP_BASELINE_DIR || `.evidence/baseline/${NAME}`;
const SHOTS = path.join(EVID, 'artifacts', NAME);
const DIFFS = path.join(EVID, 'artifacts', `${NAME}-diffs`);

const cfg = {
  baseUrl: 'http://localhost:3000',
  routes: ['/'],
  widths: [1440],
  themes: ['light'],
  height: 900,
  fullPage: true,
  settleMs: 300,
  waitUntil: 'load',
  waitFor: null,
  threshold: 0.1,
  maxRatio: 0.001,
  ignoreConsole: [],
  ignoreRequests: [],
  mask: [],
  reachableTimeoutMs: 15000,
  ...JSON.parse(process.env.SHIP_COLLECTOR_CONFIG || '{}'),
};

/** Write the report and leave with the right code. 2 means "I am broken", which
 *  is deliberately not the same as "the app regressed". */
function report(status, failed, artifacts, notes) {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(
    { collector: NAME, status, failed, artifacts, notes }, null, 2));
  process.exit(status === 'PASS' ? 0 : status === 'FAIL' ? 1 : 2);
}

const ignored = (text, patterns) =>
  patterns.some(p => { try { return new RegExp(p).test(text); } catch { return text.includes(p); } });

let chromium, pixelmatch, PNG;
try {
  ({ chromium } = await import('@playwright/test'));
  pixelmatch = (await import('pixelmatch')).default;
  ({ PNG } = await import('pngjs'));
} catch (e) {
  report('BROKEN', [], [], `missing dependency: ${e.message}. In your repo run: ` +
    `npm i -D @playwright/test pixelmatch pngjs && npx playwright install chromium`);
}

// Preflight. Without this, a dev server that simply is not running produces a
// wall of "regressions" that all look real, and someone spends twenty minutes
// on it before noticing. A dead origin is a broken collector, not a red diff.
try {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), cfg.reachableTimeoutMs);
  await fetch(cfg.baseUrl, { signal: ac.signal });
  clearTimeout(t);
} catch (e) {
  report('BROKEN', [], [],
    `${cfg.baseUrl} is not reachable (${e.message}). Start the app before collecting ` +
    `evidence — an unreachable origin would otherwise be reported as a regression on every route.`);
}

fs.mkdirSync(MODE === 'baseline' ? BASE : SHOTS, { recursive: true });

const failed = [];
const artifacts = [];
let browser;

try {
  browser = await chromium.launch();

  for (const route of cfg.routes) {
    for (const width of cfg.widths) {
      for (const theme of cfg.themes) {
        const id = `${route.replace(/[^a-z0-9]/gi, '_')}__${width}__${theme}`;
        const ctx = await browser.newContext({
          viewport: { width, height: cfg.height },
          colorScheme: theme,
          deviceScaleFactor: 1,
          reducedMotion: 'reduce',
        });
        const page = await ctx.newPage();

        // Deterministic signals a visual judge cannot fake or overlook.
        const consoleErrors = [];
        const failedRequests = [];
        page.on('console', m => {
          if (m.type() === 'error' && !ignored(m.text(), cfg.ignoreConsole))
            consoleErrors.push(m.text());
        });
        page.on('requestfailed', r => {
          const line = `${r.method()} ${r.url()}`;
          if (!ignored(line, cfg.ignoreRequests)) failedRequests.push(line);
        });
        page.on('response', r => {
          const line = `${r.status()} ${r.url()}`;
          if (r.status() >= 400 && !ignored(line, cfg.ignoreRequests)) failedRequests.push(line);
        });

        await page.goto(cfg.baseUrl + route, { waitUntil: cfg.waitUntil, timeout: 30000 });
        // Animation is the single largest source of false positives here.
        await page.addStyleTag({ content:
          `*,*::before,*::after{animation:none!important;transition:none!important;
           caret-color:transparent!important;scroll-behavior:auto!important}` });
        // Anything genuinely non-deterministic — clocks, ids, avatars — gets painted
        // over rather than tolerated with a loose threshold, because a loose threshold
        // hides real regressions everywhere else on the page too.
        for (const sel of cfg.mask) {
          await page.addStyleTag({ content:
            `${sel}{visibility:hidden!important;background:#888!important}` });
        }
        if (cfg.waitFor) await page.waitForSelector(cfg.waitFor, { timeout: 10000 });
        await page.waitForTimeout(cfg.settleMs);

        const dest = MODE === 'baseline' ? BASE : SHOTS;
        const file = path.join(dest, `${id}.png`);
        await page.screenshot({ path: file, fullPage: cfg.fullPage });
        await ctx.close();
        artifacts.push(file);

        const reasons = [];
        if (consoleErrors.length)
          reasons.push(`${consoleErrors.length} console error(s): ${consoleErrors[0]}`);
        if (failedRequests.length)
          reasons.push(`${failedRequests.length} failed request(s): ${failedRequests[0]}`);

        if (MODE === 'compare') {
          const basePath = path.join(BASE, `${id}.png`);
          if (!fs.existsSync(basePath)) {
            reasons.push('no baseline for this combination — it was added after the ' +
              'baseline was recorded, so nothing is proven about it either way');
          } else {
            const a = PNG.sync.read(fs.readFileSync(basePath));
            const b = PNG.sync.read(fs.readFileSync(file));
            if (a.width !== b.width || a.height !== b.height) {
              reasons.push(`size changed ${a.width}x${a.height} → ${b.width}x${b.height}`);
            } else {
              const diff = new PNG({ width: a.width, height: a.height });
              const px = pixelmatch(a.data, b.data, diff.data, a.width, a.height,
                { threshold: cfg.threshold });
              const ratio = px / (a.width * a.height);
              if (ratio > cfg.maxRatio) {
                fs.mkdirSync(DIFFS, { recursive: true });
                const dpath = path.join(DIFFS, `${id}.png`);
                fs.writeFileSync(dpath, PNG.sync.write(diff));
                artifacts.push(dpath);
                reasons.push(`${px} pixels differ (${(ratio * 100).toFixed(3)}% > ` +
                  `${(cfg.maxRatio * 100).toFixed(3)}% allowed)`);
              }
            }
          }
        }

        if (reasons.length) {
          const arts = [file];
          const dpath = path.join(DIFFS, `${id}.png`);
          if (fs.existsSync(dpath)) arts.push(dpath);
          if (MODE === 'compare' && fs.existsSync(path.join(BASE, `${id}.png`)))
            arts.unshift(path.join(BASE, `${id}.png`));
          failed.push({ id, why: reasons.join(' · '), artifacts: arts,
                        consoleErrors, failedRequests });
        }
      }
    }
  }
} catch (e) {
  await browser?.close();
  report('BROKEN', failed, artifacts, `collector threw: ${e.message}`);
}
await browser.close();

if (MODE === 'baseline') {
  report(failed.length ? 'FAIL' : 'PASS', failed, artifacts,
    failed.length
      ? `Baselines recorded, but ${failed.length} page(s) had console or network errors ` +
        `while recording. You are about to enshrine a broken page as the oracle.`
      : `Recorded ${artifacts.length} baseline shots. Commit .evidence/baseline/.`);
}

report(failed.length ? 'FAIL' : 'PASS', failed, artifacts,
  `${artifacts.length} shots · ${failed.length} failed`);
