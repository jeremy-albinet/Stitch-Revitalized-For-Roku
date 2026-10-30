'use strict';

const {test} = require('node:test');
// Reuse the bounded, fresh-marker BrightScript runner; no additional engine harness.
const {root, fs, path, assert, execution, positive, packageFixture} = require('./fixtures/roku-vod-fetch/runner');
const names = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch', 'rokuDemuxCommon', 'rokuDemuxProtocol'];

async function fixture(mutation) {
    const main = await fs.readFile(path.join(__dirname, 'fixtures/roku-demux-fetch-timeout/main.brs'), 'utf8');
    return packageFixture(names, main, (name, source) => {
        if (name !== 'rokuDemuxFetch') return source;
        // Only native transfer creation and the native event type are boundaries.
        // Filesystem, framing, cancellation, timeout and Core input bodies execute.
        for (const [before, after] of [
            ['CreateObject("roUrlTransfer")', 'tfTransfer()'],
            ['Type(event) <> "roUrlEvent"', 'tfEventType(event) <> "roUrlEvent"']
        ]) {
            assert.equal(source.split(before).length, 2, `one native boundary: ${before}`);
            source = source.replace(before, after);
        }
        if (mutation) {
            assert.equal(source.split(mutation.before).length, 2, `one actual ${mutation.label} anchor`);
            source = source.replace(mutation.before, mutation.after);
        }
        return source;
    });
}

test('actual live Fetch timeout policy is independent of event/Tick order with real staging cleanup', {timeout: 60000}, async t => {
    const result = await fixture();
    t.diagnostic(`actual production assertions=${positive(result, 'STITCH_FETCH_TIMEOUT', result.marker)}`);
    t.diagnostic('HEAD/GET, at/after deadline, both dispatch orders, successful retry, second timeout, stale identities, cancellation failure; real staging files; native URL/events mocked, no network/decoder/device evidence');
});

test('actual timeout, identity, single-retry and cleanup mutations fail at normal engine exit', {timeout: 180000}, async t => {
    const mutations = [
        {label: 'event-order', before: 'if nowMs >= op.deadline\n            nlTimeout(state)',
            after: 'if false\n            nlTimeout(state)', expected: 'first overdue dispatch keeps retry intent'},
        {label: 'deadline-equality', before: 'if nowMs >= op.deadline\n            nlTimeout(state)',
            after: 'if nowMs > op.deadline\n            nlTimeout(state)', expected: 'first overdue dispatch keeps retry intent'},
        {label: 'identity', before: 'if event.GetSourceIdentity() <> op.identity then return false',
            after: 'if false then return false', expected: 'late old identity cannot expire retry'},
        {label: 'retry-cap', before: 'nlCheck(not retried and nlString(op.url), "upstream operation deadline")',
            after: 'nlCheck(nlString(op.url), "upstream operation deadline")', expected: 'second timeout fails closed'},
        {label: 'input-cleanup', before: 'clean = nativeLiveInputCleanup()',
            after: 'clean = true', expected: 'timeout deletes owned staging file'},
        {label: 'cancel', before: 'cancelled = transfer.AsyncCancel()',
            after: 'cancelled = true', expected: 'timeout cancels exactly one retained transfer'}
    ];
    // Match either source newline convention without altering production bodies.
    const source = await fs.readFile(path.join(root, 'source/utils/rokuDemuxFetch.brs'), 'utf8');
    for (const mutation of mutations) {
        if (source.includes('\r\n')) {
            mutation.before = mutation.before.replaceAll('\n', '\r\n');
            mutation.after = mutation.after.replaceAll('\n', '\r\n');
        }
        const result = await fixture(mutation);
        execution(result);
        assert.ok(result.output.includes(`STITCH_FETCH_TIMEOUT_FAIL: fetch-timeout-fixture: ${mutation.expected}`), `${mutation.label}\n${result.output}`);
        assert.throws(() => positive(result, 'STITCH_FETCH_TIMEOUT', result.marker));
        t.diagnostic(`rejected ${mutation.label}`);
    }
});
