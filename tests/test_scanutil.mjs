import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ScanUtil = require('../web/scanutil.js');

test('computeTotalBytes prefers numeric total_bytes', () => {
  const data = { total_bytes: 1000, scan: { a: { size_bytes: 999, in_total: true } } };
  assert.equal(ScanUtil.computeTotalBytes(data), 1000);
});

test('computeTotalBytes sums only in_total categories when total_bytes missing', () => {
  const data = { scan: {
    app_leftovers:  { size_bytes: 100, in_total: true },
    app_uninstaller:{ size_bytes: 100, in_total: false },
    developer:      { size_bytes: 50,  in_total: true },
  }};
  assert.equal(ScanUtil.computeTotalBytes(data), 150);
});

test('computeTotalBytes treats missing in_total as included', () => {
  const data = { scan: { a: { size_bytes: 30 }, b: { size_bytes: 20, in_total: true } } };
  assert.equal(ScanUtil.computeTotalBytes(data), 50);
});

const SAMPLE = {
  total_bytes: 500,
  scan: {
    app_leftovers: { size_bytes: 300, in_total: true, risk: 'caution', subitems: [
      { id: 'Claude', name: 'Claude', size_bytes: 200, size_human: '200 B', path: '/u/Claude', is_orphaned: false },
      { id: 'OldApp', name: 'OldApp', size_bytes: 100, size_human: '100 B', path: '/u/OldApp', is_orphaned: true },
    ]},
    browser_full: { size_bytes: 50, in_total: true, risk: 'danger', subitems: [
      { id: 'chrome', name: 'Google Chrome', size_bytes: 50, size_human: '50 B', age_days: 5, is_orphaned: false },
    ]},
    user_cache: { size_bytes: 150, in_total: true },           // no subitems -> ignored
    app_uninstaller: { size_bytes: 300, in_total: false, subitems: [
      { id: 'Claude', name: 'Claude', size_bytes: 200, size_human: '200 B' },
    ]},
  },
};

test('flattenScan only includes categories with subitems', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  const cats = new Set(rows.map(r => r.catKey));
  assert.ok(!cats.has('user_cache'));
  assert.ok(cats.has('app_leftovers'));
  assert.equal(rows.length, 4); // 2 + 1 + 1
});

test('flattenScan rowId is unique and stable', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(new Set(rows.map(r => r.rowId)).size, rows.length);
  assert.ok(rows.some(r => r.rowId === 'app_leftovers::Claude'));
});

test('flattenScan maps safety from risk', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(rows.find(r => r.rowId === 'browser_full::chrome').safety, 'danger');
  assert.equal(rows.find(r => r.rowId === 'app_leftovers::Claude').safety, 'caution');
});

test('flattenScan: explicit safe risk -> safe, unknown/missing risk -> caution', () => {
  const data = { scan: {
    developer:    { risk: 'safe', subitems: [{ id: 'a', name: 'A' }] },
    ios_backups:  { risk: 'weird', subitems: [{ id: 'b', name: 'B' }] }, // unknown
    app_leftovers:{ subitems: [{ id: 'c', name: 'C' }] },                // missing risk
  }};
  const rows = ScanUtil.flattenScan(data);
  assert.equal(rows.find(r => r.rowId === 'developer::a').safety, 'safe');
  assert.equal(rows.find(r => r.rowId === 'ios_backups::b').safety, 'caution');
  assert.equal(rows.find(r => r.rowId === 'app_leftovers::c').safety, 'caution');
});

test('flattenScan tolerates missing/malformed data', () => {
  assert.deepEqual(ScanUtil.flattenScan(undefined), []);
  assert.deepEqual(ScanUtil.flattenScan({}), []);
  assert.deepEqual(ScanUtil.flattenScan({ scan: { developer: {} } }), []); // no subitems array
});

test('sortRows by size desc', () => {
  const rows = ScanUtil.sortRows(ScanUtil.flattenScan(SAMPLE), 'size', 'desc');
  assert.equal(rows[0].sizeBytes, 200);
  assert.equal(rows[rows.length - 1].sizeBytes, 50);
});

test('filterRows matches name and path case-insensitively', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(ScanUtil.filterRows(rows, 'claude').length, 2); // app_leftovers + app_uninstaller
  assert.equal(ScanUtil.filterRows(rows, '/u/OldApp').length, 1);
  assert.equal(ScanUtil.filterRows(rows, '').length, rows.length);
});

test('selectedTotalBytes sums only selected rowIds', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  const sel = new Set(['app_leftovers::Claude', 'browser_full::chrome']);
  assert.equal(ScanUtil.selectedTotalBytes(rows, sel), 250);
});

test('buildCleanPayload groups ids by category with indices', () => {
  const rows = ScanUtil.flattenScan(SAMPLE).filter(
    r => r.rowId === 'app_leftovers::OldApp' || r.rowId === 'browser_full::chrome'
  );
  const indexByKey = { app_leftovers: 3, browser_full: 9 };
  const p = ScanUtil.buildCleanPayload(rows, indexByKey);
  assert.deepEqual(p.categories.sort(), [3, 9]);
  assert.deepEqual(p.app_leftovers_selected, ['OldApp']);
  assert.deepEqual(p.browser_full_selected, ['chrome']);
  assert.deepEqual(p.developer_selected, []);
});
