import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const source = fs.readFileSync(new URL('../web/script.js', import.meta.url), 'utf8');
const ScanUtil = require('../web/scanutil.js');
const flush = () => new Promise(resolve => setImmediate(resolve));

// Minimal DOM boundary: run the actual controller and its registered handlers.
async function dashboard(responses = {}) {
  class Element {
    innerHTML = ''; style = {}; dataset = {}; attributes = {}; handlers = {};
    classList = { toggle() {}, add() {}, remove() {} };
    set textContent(value) {
      this.innerHTML = String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    }
    get textContent() { return this.innerHTML; }
    setAttribute(key, value) { this.attributes[key] = value; }
    getAttribute(key) { return this.attributes[key]; }
    querySelector() { return null; }
    appendChild() {}
    addEventListener(event, handler) { (this.handlers[event] ||= []).push(handler); }
    async fire(event, target = this) {
      for (const handler of this.handlers[event] || []) await handler.call(this, { target });
      await flush();
    }
  }
  const elements = new Map();
  const get = key => {
    if (!elements.has(key)) elements.set(key, new Element());
    return elements.get(key);
  };
  const document = new Element();
  document.querySelector = get;
  document.querySelectorAll = () => [];
  document.createElement = () => new Element();
  document.documentElement = new Element();
  const calls = [], alerts = [];
  const defaults = {
    '/api/health': { success: true }, '/api/status': {},
    '/api/scan': { success: true, scan: { logs: { size_bytes: 10 } } },
  };
  vm.runInNewContext(source, { document, ScanUtil,
    window: { scrollTo() {} }, localStorage: { getItem() {}, setItem() {} },
    alert: text => alerts.push(text),
    fetch: async (url, options) => {
      calls.push({ url, options });
      const data = responses[url] ?? defaults[url];
      if (data instanceof Error) throw data;
      return { ok: true, json: async () => data };
    },
  });
  await flush();
  const tab = async id => get('#sidebarMenu').fire('click', {
    closest: () => ({ dataset: { tab: id } }),
  });
  return { get, tab, calls, alerts };
}

test('file views render only API files, escape paths and support empty results', async () => {
  const app = await dashboard({
    '/api/large-files': { results: [{ name: '<actual>.bin', path: '/tmp/<actual>.bin', size_bytes: 200 }],
      scope: 'Personal files', scanned_files: 1, large_min_bytes: 100 },
    '/api/duplicates': { results: [], partial: false, scope: 'Personal files' },
  });
  await app.tab('large-files');
  assert.match(app.get('#largeFilesContainer').innerHTML, /&lt;actual&gt;/);
  assert.doesNotMatch(app.get('#largeFilesContainer').innerHTML, /macOS_Sonoma|ubuntu_vm/);
  assert.equal(app.get('#largeFilesContainer').attributes['aria-busy'], 'false');
  await app.tab('duplicates');
  assert.match(app.get('#duplicatesContainer').innerHTML, /No matching files found/);
});

test('failed inventory shows retry instead of fabricated files', async () => {
  const app = await dashboard({ '/api/large-files': new Error('offline') });
  await app.tab('large-files');
  assert.match(app.get('#largeFilesContainer').innerHTML, /Could not scan files/);
  assert.match(app.get('#largeFilesContainer').innerHTML, /Try again/);
});

test('cleanup routes the selected stable category and checked subitem', async () => {
  const app = await dashboard({
    '/api/scan': { success: true, scan: { developer: { size_bytes: 30, subitems: [
      { id: 'npm_cache', size_bytes: 10 }, { id: 'pip_cache', size_bytes: 20 },
    ] } } }, '/api/clean': { success: true, freed_human: '10 B' },
  });
  await app.tab('smart-clean');
  await app.get('#smartCleanCategoriesList').fire('click', {
    dataset: { subCat: 'developer', subId: 'pip_cache' }, checked: false,
  });
  await app.get('#btnExecuteClean').fire('click');
  const clean = app.calls.find(call => call.url === '/api/clean');
  assert.ok(clean);
  assert.deepEqual(JSON.parse(clean.options.body), {
    categories: ['developer'], developer_selected: ['npm_cache'], dry_run: false,
  });
});

test('offline maintenance fails visibly without success messages', async () => {
  const app = await dashboard({ '/api/health': new Error('offline') });
  await app.get('#btnToolFlushDns').fire('click');
  assert.ok(app.alerts.some(text => /No maintenance was performed/.test(text)));
  assert.ok(!app.alerts.some(text => /successfully/.test(text)));
});
