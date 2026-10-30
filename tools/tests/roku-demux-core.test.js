'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/roku-demux-core');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const sourceNames = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch',
    'rokuDemuxCommon', 'rokuDemuxProtocol'];
const caseNames = ['binary-goldens-and-strict-malformed',
    'rounded-publication-duration-and-stable-manifests',
    'bounded-fresh-startup-window-wait',
    'rolling-past-finite-limits-with-held-lease', 'poll-gaps-contiguous-and-fail-closed',
    'actual-cache-leases-and-atomic-admission', 'active-publication-generation-cap',
    'monotonic-long-clock-quotas-and-exhaustion',
    'shorter-tail-discard-before-cached-history',
    'finite-default-and-real-progress-deadlines'];
const sha256 = data => createHash('sha256').update(data).digest('hex');

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one unchanged production ${name} body required`);
    return matches[0] + '\n';
}

function validateCorpus(corpus) {
    assert.equal(corpus.version, 1);
    const identities = [corpus.init.input, corpus.init.video, corpus.init.audio,
        ...corpus.media.flatMap(item => [item.input, item.video, item.audio]),
        ...corpus.negative.map(item => item.input)];
    for (const item of identities) {
        assert.match(item.hex, /^(?:[0-9a-f]{2})+$/);
        const bytes = Buffer.from(item.hex, 'hex');
        assert.equal(bytes.length, item.count, 'checked binary logical count');
        assert.equal(sha256(bytes), item.sha256, 'checked complete binary SHA identity');
    }
    assert.equal(corpus.init.metadata.videoCodec, 'avc1.4D402A');
    assert.equal(corpus.init.metadata.audioCodec, 'mp4a.40.2');
    assert.ok(corpus.media.length > 258 && corpus.media.length <= 270, 'small corpus crosses actual old generation bound');
    assert.equal(new Set(corpus.media.map(item => item.input.sha256)).size, corpus.media.length);
    for (let index = 0; index < corpus.media.length; index++) {
        assert.equal(corpus.media[index].sequence, index + 10);
        assert.ok(corpus.media[index].input.count <= 256, 'no large emulator payloads');
    }
    for (const name of ['duration-empty-video-requested', 'duration-empty-video-discarded',
        'duration-empty-audio-requested', 'duration-empty-audio-discarded',
        'truncated-init', 'encrypted-init', 'duplicate-track-id', 'negative-sample-offset', 'sample-grouping']) {
        assert.ok(corpus.negative.some(item => item.name === name), `actual malformed binary ${name}`);
    }
}

function runChild(args, cwd, timeoutMs = 45000, outputLimit = 65536) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, args,
            { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        let startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => {
            clearTimeout(timer);
            resolve({ code, output, exceeded, timedOut, startupError });
        });
    });
}

function requireExecution(result) {
    const detail = result.output.slice(-14000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, `child timeout\n${detail}`);
    assert.equal(result.exceeded, false, `output limit\n${detail}`);
    assert.equal(result.code, 0, `child exited ${result.code}\n${detail}`);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    return detail;
}

function requirePositive(result, marker) {
    const detail = requireExecution(result);
    assert.doesNotMatch(result.output, /STITCH_ROKU_CORE_FAIL:/, detail);
    const summaries = result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_ROKU_CORE_PASS:'));
    assert.equal(summaries.length, 1, `exactly one non-stale success required\n${detail}`);
    assert.ok(summaries[0].startsWith(`STITCH_ROKU_CORE_PASS: ${marker} `), `fresh marker missing\n${detail}`);
    const numbers = summaries[0].match(/cases=\s*(\d+) assertions=\s*(\d+) pairs=\s*(\d+) goldens=\s*(\d+) ids=\s*(\d+) generations=\s*(\d+) elapsedMs=\s*(\d+)$/);
    assert.ok(numbers, detail);
    const [cases, assertions, pairs, goldens, ids, generations, elapsedMs] = numbers.slice(1).map(Number);
    const actualCases = result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_ROKU_CORE_CASE: '));
    assert.deepEqual(actualCases, caseNames.map(name => `STITCH_ROKU_CORE_CASE: ${name}`));
    assert.equal(cases, actualCases.length);
    assert.ok(assertions > 0 && pairs > 258 && goldens > 516 && ids > 256 && generations > 256 && elapsedMs > 45000,
        'actual binary pipeline must cross the historical limits');
    return { cases, assertions, pairs, goldens, ids, generations, elapsedMs };
}

async function withFixture(run) {
    const prefix = 'stitch-roku-core-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const sources = new Map();
    try {
        for (const name of sourceNames) {
            const file = `source/utils/${name}.brs`;
            const bytes = await fs.readFile(path.join(root, file));
            sources.set(file, bytes);
            const parsed = bsc.Parser.parse(bytes.toString(), { mode: bsc.ParseMode.BrightScript });
            assert.deepEqual(parsed.diagnostics, [], `actual ${name} source parses cleanly`);
            if (name === 'rokuDemuxFetch') {
                // Only its unchanged real cleanup bodies are needed. URL/Task
                // adapter entrypoints are not called or faked by this port.
                const source = ['nlInputPath', 'nativeLiveInputCleanup', 'nlCancelInput', 'nativeLiveClose']
                    .map(func => exactFunction(bytes.toString(), func)).join('\n');
                await fs.writeFile(path.join(dir, `${name}.brs`), source);
            } else {
                await fs.writeFile(path.join(dir, `${name}.brs`), bytes);
                assert.deepEqual(await fs.readFile(path.join(dir, `${name}.brs`)), bytes);
            }
        }
        const corpusBytes = await fs.readFile(path.join(fixtures, 'corpus.json'));
        const corpus = JSON.parse(corpusBytes);
        validateCorpus(corpus);
        const provenance = JSON.parse(await fs.readFile(path.join(fixtures, 'provenance.json')));
        assert.equal(sha256(corpusBytes), provenance.corpusSha256, 'corpus provenance identity');
        await fs.writeFile(path.join(dir, 'corpus.json'), corpusBytes);
        const marker = randomUUID();
        const harness = (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replace('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(harness, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), harness);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Actual Core Binary Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const execute = () => runChild([cli, '--no-sg', '--root', dir,
            ...sourceNames.map(name => `${name}.brs`), 'main.brs'], dir);
        await run({ dir, corpus, sources, marker, harness, execute });
        for (const [file, bytes] of sources) {
            assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, `frozen actual ${file} changed during run`);
        }
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('demux regex reuse preserves alternating asset and session validation', async () => {
    await withFixture(async ({ dir, sources, marker, execute }) => {
        const common = sources.get('source/utils/rokuDemuxCommon.brs').toString();
        const constructors = /\bCreateObject\(\s*"roRegex",\s*/gi;
        assert.equal([...common.matchAll(constructors)].length, 2);
        await fs.writeFile(path.join(dir, 'rokuDemuxCommon.brs'), common.replace(constructors, 'fixtureRegex('));
        await fs.writeFile(path.join(dir, 'main.brs'), `sub main()
    m.failures = 0
    getGlobalAA().regexBuilds = 0
    session = string(32, "a")
    for index = 1 to 25
        valid = "live-" + session + "-" + index.toStr()
        check(loopbackAssetId(valid), "valid scoped asset")
        check(not loopbackAssetId("live-" + session + "-0"), "zero asset rejected after warmup")
        check(not loopbackAssetId("live-" + session + "-4294967296"), "numeric overflow rejected after warmup")
        check(not loopbackAssetId("live-" + string(32, "A") + "-1"), "uppercase asset rejected after warmup")
        check(loopbackAssetSession(valid) = session, "session extraction remains validated")
        check(loopbackSteadySessionIdValid(session), "valid session")
        check(not loopbackSteadySessionIdValid(string(32, "A")), "uppercase session rejected after warmup")
        check(not loopbackSteadySessionIdValid(session + "a"), "overlong session rejected after warmup")
    end for
    check(loopbackAssetId("live-256") and not loopbackAssetId("live-257"), "finite asset bounds retained")
    check(loopbackAssetId("live-" + session + "-4294967295"), "maximum identity retained")
    check(getGlobalAA().regexBuilds = 2, "one real regex constructor per pattern in the execution context")
    if m.failures = 0 then print "STITCH_REGEX_CACHE_PASS:${marker}"
end sub
sub check(value as boolean, label as string)
    if not value
        m.failures++
        print "STITCH_REGEX_CACHE_FAIL:"; label
    end if
end sub
function fixtureRegex(pattern as string, flags as string) as object
    getGlobalAA().regexBuilds++
    return CreateObject("roRegex", pattern, flags)
end function
`);
        const result = await execute();
        requireExecution(result);
        assert.doesNotMatch(result.output, /STITCH_REGEX_CACHE_FAIL:/, result.output.slice(-4000));
        assert.equal(result.output.split(`STITCH_REGEX_CACHE_PASS:${marker}`).length - 1, 1);
    });
});

test('actual Bulk/Core bytes, rolling generations, cache leases, continuity and monotonic quotas', { timeout: 90000 }, async t => {
    await withFixture(async ({ marker, execute }) => {
        const result = await execute();
        const counts = requirePositive(result, marker);
        t.diagnostic(JSON.stringify(counts));
        t.diagnostic('actual small binary conversion and logical clock; no network/decoder/hardware/large-memory proof');
    });
});

test('actual duration guard mutations and a corrupt full-byte golden cannot pass', { timeout: 90000 }, async () => {
    await withFixture(async ({ dir, sources, marker, harness, execute, corpus }) => {
        const protocolPath = path.join(dir, 'rokuDemuxProtocol.brs');
        const protocol = sources.get('source/utils/rokuDemuxProtocol.brs').toString();
        const localGuard = 'if segment.durationUs >= 2500000 then return false';
        const sourceGuard = 'if segment.durationUs > pub.targetDuration * 1000000 + 499999 then return false';
        assert.equal(protocol.split(localGuard).length, 2, 'one actual local rounded duration guard');
        assert.equal(protocol.split(sourceGuard).length, 2, 'one actual source rounded duration guard');
        // Reuse the actual Core/publication/manifest case without repeatedly
        // running its unrelated historical 260-pair rolling matrix.
        const durationHarness = harness.replace(/^        (?:bulkCore|startupWindowCore|rollingCore|continuityCore|admissionCore|generationPinsCore|clockQuotaCore|staleTailCore|finiteLivenessCore)\(\)\r?\n/gm, '');
        await fs.writeFile(path.join(dir, 'main.brs'), durationHarness);
        for (const control of [
            { before: localGuard, after: 'if segment.durationUs > 2000000 then return false', expected: 'actual fractional Core publication accepted 2.002' },
            { before: localGuard, after: 'if segment.durationUs > 2500000 then return false', expected: 'publication rejects local half-second boundary' },
            { before: sourceGuard, after: 'if segment.durationUs > pub.targetDuration * 1000000 then return false', expected: 'actual fractional Core publication accepted 2.499999' },
            { before: sourceGuard, after: "' Deliberately removed source-target boundary", expected: 'publication rejects source half-second boundary' }
        ]) {
            await fs.writeFile(protocolPath, protocol.replace(control.before, control.after));
            const result = await execute();
            requireExecution(result);
            assert.ok(result.output.includes(`STITCH_ROKU_CORE_FAIL: core-fixture: ${control.expected}`), result.output.slice(-14000));
            assert.throws(() => requirePositive(result, marker));
        }
        await fs.writeFile(protocolPath, protocol);
        await fs.writeFile(path.join(dir, 'main.brs'), harness);
        const bulkPath = path.join(dir, 'rokuDemuxBulk.brs');
        const bulk = sources.get('source/utils/rokuDemuxBulk.brs').toString();
        assert.equal(bulk.split('&hfdffc4').length, 2, 'one actual duration-is-empty mask');
        await fs.writeFile(bulkPath, bulk.replace('&hfdffc4', '&hfcffc4'));
        const permissive = await execute();
        requireExecution(permissive);
        assert.match(permissive.output, /STITCH_ROKU_CORE_FAIL: core-fixture: strict malformed duration-empty-video-requested/);
        assert.throws(() => requirePositive(permissive, marker));
        await fs.writeFile(bulkPath, bulk);
        const wrong = structuredClone(corpus);
        wrong.init.video.hex = 'ff' + wrong.init.video.hex.slice(2);
        await fs.writeFile(path.join(dir, 'corpus.json'), JSON.stringify(wrong));
        const corrupt = await execute();
        requireExecution(corrupt);
        assert.match(corrupt.output, /STITCH_ROKU_CORE_FAIL: core-fixture: standalone video init full Python byte golden/);
        assert.throws(() => requirePositive(corrupt, marker));
    });
});

test('actual startup wait guards and finite polling mutations cannot pass', { timeout: 90000 }, async () => {
    await withFixture(async ({ dir, sources, marker, harness, execute }) => {
        const corePath = path.join(dir, 'rokuDemuxCore.brs');
        const core = sources.get('source/utils/rokuDemuxCore.brs').toString();
        const startupHarness = harness.replace(/^        (?:bulkCore|publicationDurationCore|rollingCore|continuityCore|admissionCore|generationPinsCore|clockQuotaCore|staleTailCore|finiteLivenessCore)\(\)\r?\n/gm, '');
        await fs.writeFile(path.join(dir, 'main.brs'), startupHarness);
        const windowCall = 'window = nlWindow(parsed, state.delayUs, waitForStartup, false, windowUs)';
        const pollGate = '        if nowMs < state.nextPoll then return invalid';
        const waitPoll = '            state.nextPoll = nowMs + parsed.targetDuration * 500&';
        const windowEquality = /        if waitForStartup and not playlist\.ended\r?\n            if segment\.mapUrl <> selectedMap or segment\.epoch <> selectedEpoch then return invalid\r?\n        end if\r?\n        nlCheck\(segment\.mapUrl = selectedMap and segment\.epoch = selectedEpoch, "selected window crosses map or discontinuity"\)/;
        assert.equal(core.split(windowCall).length, 2);
        assert.equal(core.split(pollGate).length, 2);
        assert.equal(core.split(waitPoll).length, 2);
        assert.ok(core.match(windowEquality));
        for (const control of [
            { source: core.replace(windowCall, 'window = nlWindow(parsed, state.delayUs, false, false, windowUs)'), expected: 'validated mixed startup waits for coherent tail' },
            { source: core.replace(windowEquality, "        ' Deliberately accept incompatible startup media"), expected: 'mixed startup waits without assigning a window or publication' },
            { source: core.replace(pollGate, ''), expected: 'startup wait suppresses early playlist intent' },
            { source: core.replace(waitPoll, waitPoll + '\n            state.deadline = nowMs + 45000&'), expected: 'startup wait keeps absolute deadline' }
        ]) {
            await fs.writeFile(corePath, control.source);
            const result = await execute();
            requireExecution(result);
            assert.ok(result.output.includes(`STITCH_ROKU_CORE_FAIL: core-fixture: ${control.expected}`), result.output.slice(-14000));
            assert.throws(() => requirePositive(result, marker));
        }
    });
});

test('bounded runner rejects stale/failure/timeout/overflow/nonzero child output', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const cases = caseNames.map(name => `STITCH_ROKU_CORE_CASE: ${name}\n`).join('');
    const summary = `STITCH_ROKU_CORE_PASS: ${marker} cases=${caseNames.length} assertions=1 pairs=260 goldens=522 ids=522 generations=258 elapsedMs=514000\n`;
    const valid = cases + summary;
    const script = text => `process.stdout.write(${JSON.stringify(text)});`;
    const stale = await runChild(['-e', script(valid.replace(marker, randomUUID()))], os.tmpdir(), 2000);
    assert.throws(() => requirePositive(stale, marker), /fresh marker missing/);
    const failed = await runChild(['-e', script(valid + 'STITCH_ROKU_CORE_FAIL: deliberate\n')], os.tmpdir(), 2000);
    assert.throws(() => requirePositive(failed, marker));
    const timeout = await runChild(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150);
    assert.equal(timeout.timedOut, true);
    assert.throws(() => requirePositive(timeout, marker), /child timeout/);
    const overflow = await runChild(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(overflow.exceeded, true);
    assert.throws(() => requirePositive(overflow, marker), /output limit/);
    const nonzero = await runChild(['-e', script(valid) + 'process.exitCode = 9;'], os.tmpdir(), 2000);
    assert.equal(nonzero.code, 9);
    assert.throws(() => requirePositive(nonzero, marker), /exited 9/);
});
