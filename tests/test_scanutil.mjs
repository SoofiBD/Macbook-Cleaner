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
