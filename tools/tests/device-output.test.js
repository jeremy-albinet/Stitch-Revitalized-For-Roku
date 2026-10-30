'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseRooibosResult } = require('../deploy-test');
const marker = 'STITCH_TEST_START: fresh-package\n';

test('ignores stale simulator success', () => {
    assert.equal(parseRooibosResult('STITCH_TEST_START: old-package\n93 passed (120ms)\n', 'fresh-package').status, 'pending');
});
test('recognizes fresh summary with colors and Windows newlines', () => {
    assert.deepEqual(parseRooibosResult(marker + '\t\u001b[32m17 passed\u001b[0m (123ms)\r\n', 'fresh-package'), { status: 'passed', count: 17 });
});
test('failure after passed line cannot be reported as success', () => {
    assert.equal(parseRooibosResult(marker + '17 passed (123ms)\n1 failing\n', 'fresh-package').status, 'failed');
});
test('crash and debugger output fail the run', () => {
    assert.equal(parseRooibosResult(marker + '1 crashed\n', 'fresh-package').status, 'failed');
    assert.equal(parseRooibosResult(marker + 'BrightScript Debugger>\n', 'fresh-package').status, 'failed');
});
test('zero tests and incomplete output cannot pass', () => {
    assert.equal(parseRooibosResult(marker + '0 passed (0ms)\n', 'fresh-package').status, 'pending');
    assert.equal(parseRooibosResult(marker + 'test is running\n', 'fresh-package').status, 'pending');
});
