'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { evaluateAudit } = require('../audit-dependencies');

function fixture() {
    return {
        audit: {
            metadata: { vulnerabilities: { high: 1, critical: 0, moderate: 0 } },
            vulnerabilities: {
                braces: { severity: 'high', fixAvailable: false, nodes: ['node_modules/braces'], via: [{ url: 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm' }] },
            },
        },
        lock: { packages: { 'node_modules/braces': { version: '3.0.3', dev: true } } },
        policy: { minimumSeverity: 'high', exceptions: { 'GHSA-vfj7-8cjw-p6xm': { package: 'braces', versions: ['3.0.3'], publishedLatest: '3.0.3', developmentOnly: true, expires: '2026-11-06T00:00:00Z' } } },
    };
}
const beforeExpiry = Date.parse('2026-10-07T00:00:00Z');
const registry = { braces: '3.0.3' };
test('exception is limited to the exact development package/version', () => {
    const f = fixture();
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, []);
    f.lock.packages['node_modules/braces'].dev = false;
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['braces']);
    f.lock.packages['node_modules/braces'].dev = true;
    f.lock.packages['node_modules/braces'].version = '2.3.2';
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['braces']);
});
test('expired exception and new upstream release block CI', () => {
    const f = fixture();
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, Date.parse(f.policy.exceptions['GHSA-vfj7-8cjw-p6xm'].expires), registry).blocked, ['braces']);
    const newerRegistry = { braces: '3.0.4' };
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, newerRegistry).blocked, ['braces']);
});
test('additional advisory is never hidden by a package exception', () => {
    const f = fixture();
    f.audit.vulnerabilities.braces.via.push({ url: 'https://github.com/advisories/GHSA-new-vulnerability' });
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['braces']);
});
test('transitive caller must also be development-only', () => {
    const f = fixture();
    f.audit.vulnerabilities.compiler = { severity: 'high', nodes: ['node_modules/compiler'], via: ['braces'] };
    f.lock.packages['node_modules/compiler'] = { dev: true };
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, []);
    f.lock.packages['node_modules/compiler'].dev = false;
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['compiler']);
});
test('invalid reports and unresolved findings fail closed', () => {
    const f = fixture();
    assert.throws(() => evaluateAudit({ error: {} }, f.lock, f.policy, beforeExpiry, registry));
    f.audit.vulnerabilities.braces.via = ['missing-package'];
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['braces']);
});

test('cycles in advisory references cannot approve an exception', () => {
    const f = fixture();
    f.audit.vulnerabilities.braces.via = ['compiler'];
    f.audit.vulnerabilities.compiler = { severity: 'high', nodes: ['node_modules/compiler'], via: ['braces'] };
    f.lock.packages['node_modules/compiler'] = { version: '1.0.0', dev: true };
    assert.deepEqual(evaluateAudit(f.audit, f.lock, f.policy, beforeExpiry, registry).blocked, ['braces', 'compiler']);
});
