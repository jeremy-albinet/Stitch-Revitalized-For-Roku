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
const fixtures = path.join(__dirname, 'fixtures/roku-demux-epoch-core');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const names = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxCommon', 'rokuDemuxProtocol', 'rokuDemuxInitMetadata', 'rokuDemuxFetch',
    'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol'];
const cases = ['content-ad-content-with-held-leases', 'several-short-mixed-boundaries-and-source-delay',
    'explicit-opt-in-and-legacy-startup-policy', 'byte-alias-distinct-from-genuine-stage-and-gate-refusal',
    'shared-source-identity-gap-epoch-and-track-refusals', 'atomic-pair-slot-pressure-and-old-lease-cleanup',
    'mixed-shorter-tail-discard-and-health-deadline',
    'unchanged-deadlines-quotas-local-overflow-and-stop'];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one unchanged production ${name}`);
    return matches[0] + '\n';
}

function runChild(args, dir, timeoutMs = 45000, outputLimit = 65536) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, args, { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', bytes = 0, exceeded = false, timedOut = false, startupError;
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
        child.once('close', code => { clearTimeout(timer); resolve({ code, output, exceeded, timedOut, startupError }); });
    });
}

function run(dir) {
    return runChild([cli, '--no-sg', '--root', dir, ...names.map(name => `${name}.brs`), 'main.brs'], dir);
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
    assert.doesNotMatch(result.output, /STITCH_EPOCH_CORE_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_EPOCH_CORE_CASE: ')), cases.map(name => `STITCH_EPOCH_CORE_CASE: ${name}`));
    const summaries = lines.filter(line => line.startsWith('STITCH_EPOCH_CORE_PASS:'));
    assert.equal(summaries.length, 1, detail);
    assert.ok(summaries[0].startsWith(`STITCH_EPOCH_CORE_PASS: ${marker} `), `fresh marker missing\n${detail}`);
    const numbers = summaries[0].match(/cases=\s*(\d+) assertions=\s*(\d+) goldens=\s*(\d+) manifests=\s*(\d+) pairs=\s*(\d+) gateCalls=\s*(\d+)$/);
    assert.ok(numbers, detail);
    const [count, assertions, goldens, manifests, pairs, gateCalls] = numbers.slice(1).map(Number);
    assert.equal(count, cases.length);
    assert.ok(assertions > 0 && goldens > 0 && pairs >= 9 && gateCalls >= 3 && manifests === 8, 'actual conversion/gate/manifest coverage required');
    return { cases: count, assertions, goldens, manifests, pairs, gateCalls };
}

async function withFixture(callback) {
    const prefix = 'stitch-epoch-core-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const sources = new Map();
    try {
        for (const name of names) {
            const file = `source/utils/${name}.brs`;
            const bytes = await fs.readFile(path.join(root, file));
            sources.set(file, bytes);
            assert.deepEqual(bsc.Parser.parse(bytes.toString(), { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            let copy = bytes;
            if (name === 'rokuDemuxFetch') {
                copy = ['nlInputPath', 'nativeLiveInputCleanup', 'nlCancelInput', 'nativeLiveClose', 'rokuDemuxFeedInput']
                    .map(func => exactFunction(bytes.toString(), func)).join('\n');
            }
            await fs.writeFile(path.join(dir, `${name}.brs`), copy);
            assert.deepEqual(await fs.readFile(path.join(dir, `${name}.brs`)), Buffer.from(copy));
        }
        const corpusBytes = await fs.readFile(path.join(fixtures, 'corpus.json'));
        const corpus = JSON.parse(corpusBytes);
        const provenance = JSON.parse(await fs.readFile(path.join(fixtures, 'provenance.json')));
        assert.equal(digest(corpusBytes), provenance.corpusSha256);
        assert.equal(provenance.actualDecoderApproval, false);
        assert.equal(provenance.runtimePythonRequired, false);
        assert.equal(provenance.synthetic, true);
        for (const record of [...Object.values(corpus.inits), ...corpus.media, corpus.ptsMedia]) {
            for (const key of ['input', 'video', 'audio']) {
                assert.match(record[key].hex, /^(?:[0-9a-f]{2})+$/);
                const body = Buffer.from(record[key].hex, 'hex');
                assert.equal(body.length, record[key].count);
                assert.equal(digest(body), record[key].sha256);
            }
        }
        assert.notEqual(corpus.inits.content.videoTrackId, corpus.inits.ad.videoTrackId);
        assert.notEqual(corpus.inits.content.videoTimescale, corpus.inits.ad.videoTimescale);
        assert.notEqual(corpus.inits.content.audioTimescale, corpus.inits.ad.audioTimescale);
        for (const record of corpus.media) {
            for (const track of ['video', 'audio']) {
                const body = Buffer.from(record[track].hex, 'hex');
                const offset = body.indexOf(Buffer.from('tfdt'));
                assert.ok(offset >= 4);
                assert.equal(body.readUInt32BE(offset + 4), 0x01000000, 'unchanged version1 TFDT');
                assert.equal(body.readBigUInt64BE(offset + 8), BigInt(record[`${track}DecodeTime`]), 'original exact decode time survives split golden');
            }
        }
        for (const record of Object.values(corpus.inits)) {
            for (const track of ['video', 'audio']) {
                const body = Buffer.from(record[track].hex, 'hex');
                const offset = body.indexOf(Buffer.from('mdhd'));
                assert.ok(offset >= 4);
                assert.equal(body.readUInt32BE(offset + 16), record[`${track}Timescale`], 'actual mdhd timebase preserved by init golden');
            }
        }
        await fs.writeFile(path.join(dir, 'corpus.json'), corpusBytes);
        const marker = randomUUID();
        const harness = (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replace('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(harness, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), harness);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Actual Staged Epoch Core Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await callback({ dir, marker, harness, corpus, sources, execute: () => run(dir) });
        for (const [file, bytes] of sources) {
            assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, `actual unmodified source ${file}`);
        }
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual staged Core bindings preserve init/media/manifest goldens and leases', { timeout: 90000 }, async t => {
    await withFixture(async ({ marker, execute }) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(requirePositive(result, marker)));
        t.diagnostic('actual binary/Core/caller order; device decoder decision mocked, no network/native stability claim');
    });
});

test('removed staging/binding/pinning/pair/source guards fail at normal child exit', { timeout: 180000 }, async t => {
    await withFixture(async ({ dir, marker, sources, harness, execute }) => {
        const source = sources.get('source/utils/rokuDemuxCore.brs').toString();
        const mutations = [
            { func: 'nlEpochPrepare', before: 'state.phase = "init-rotation"', after: "' Deliberately removed stage phase", cases: ['timelineEC'],
                expected: 'epoch-core-fixture: genuine boundary stages at first unpublished sequence' },
            { func: 'nativeLiveFeed', before: 'if state.sourceTransitions then nlCheck(state.pendingSegment.mapUrl = state.mapUrl and state.pendingSegment.epoch = state.epoch and state.pendingWindow = invalid, "segment initialization binding invalid")',
                after: "' Deliberately removed segment binding guard", cases: ['identityEC'], expected: 'epoch-core-fixture: unvalidated segment binding is refused before conversion' },
            { func: 'nlProtected', before: 'if state.sourceTransitions and (saved.initVideoId = id or saved.initAudioId = id) then return true',
                after: "' Deliberately removed selected epoch init protection", cases: ['mixedEC'], expected: 'native-live: segment initialization binding invalid' },
            { func: 'nlPublish', before: 'item.initVideoId = saved.initVideoId', after: 'item.initVideoId = state.initIds[0]', cases: ['timelineEC'],
                expected: 'native-live: epoch publication invalid' },
            { func: 'nativeLiveAdvance', before: 'state.temporaryVideo = nativeDemuxBulkInit(state.input, "video")',
                after: 'state.temporaryVideo = nativeDemuxBulkInit(state.input, "video")\n        if state.sourceTransitions and state.pendingWindow <> invalid then state.mapUrl = state.pendingWindow.mapUrl',
                cases: ['timelineEC'], expected: 'epoch-core-fixture: one split output cannot replace old scalar identity' },
            { func: 'nlInitDigest', before: 'if pending.epoch = state.epoch then nlCheck(payload.Count() = state.initByteCount and digest = state.initDigest, "selected map initialization changed")',
                after: "' Deliberately removed same-epoch byte identity guard", cases: ['aliasesEC'],
                expected: 'epoch-core-fixture: same-epoch changed bytes refused before device gate mutation' },
            { func: 'nlEpochAcceptWindow', before: 'nlCheck(old.url = segment.url and old.duration = segment.duration and old.durationUs = segment.durationUs and old.mapUrl = segment.mapUrl and old.sourceEpoch = segment.epoch, "cached epoch segment identity changed")',
                after: "' Deliberately removed cached source identity guard", cases: ['identityEC'], expected: 'epoch-core-fixture: exact source identity refusal uri' },
            { func: 'nativeLiveAdvance', before: 'nlCheck(pending.digest = nlBodyDigest(state.input) and pending.byteCount = state.input.Count() and FormatJson(pending.tracks) = FormatJson(nlInspectEpochInit(state.input)), "staged initialization identity changed")',
                after: "' Deliberately removed inspected stage identity guard", cases: ['aliasesEC'], expected: 'epoch-core-fixture: wrong staged track map refused before atomic admission' }
        ];
        for (const mutation of mutations) {
            const body = exactFunction(source, mutation.func);
            assert.equal(body.split(mutation.before).length, 2, `one actual ${mutation.func} mutation target`);
            const changed = source.replace(body, body.replace(mutation.before, mutation.after));
            assert.notEqual(changed, source);
            assert.deepEqual(bsc.Parser.parse(changed, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            await fs.writeFile(path.join(dir, 'rokuDemuxCore.brs'), changed);
            const subset = harness.replace(/^        (timelineEC|mixedEC|optionsEC|aliasesEC|identityEC|admissionEC|staleTailEC|budgetsEC)\(\)\r?\n/gm,
                (line, name) => mutation.cases.includes(name) ? line : '');
            await fs.writeFile(path.join(dir, 'main.brs'), subset);
            const result = await execute();
            requireExecution(result);
            assert.deepEqual(result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_EPOCH_CORE_FAIL:')),
                [`STITCH_EPOCH_CORE_FAIL: ${mutation.expected}`]);
            assert.doesNotMatch(result.output, /STITCH_EPOCH_CORE_PASS:/);
            assert.throws(() => requirePositive(result, marker));
        }
        t.diagnostic(`${mutations.length} real production source controls reject normally exiting child output`);
    });
});

test('stale-tail guard, strict comparison, polling and health mutations cannot pass', { timeout: 120000 }, async t => {
    await withFixture(async ({ dir, sources, harness, execute }) => {
        const source = sources.get('source/utils/rokuDemuxCore.brs').toString();
        const feed = exactFunction(source, 'nativeLiveFeed');
        const comparison = 'if window.segments[window.segments.Count() - 1].sequence < state.publishedLast';
        const guard = feed.match(/^        if window\.segments\[window\.segments\.Count\(\) - 1\]\.sequence < state\.publishedLast\r?\n[^]*?^        end if\r?\n/m)?.[0];
        assert.ok(guard, 'one real stale-tail discard before continuity and cached-history checks');
        assert.ok(feed.indexOf(guard) < feed.indexOf('window = nlContinuityWindow('));
        assert.ok(feed.indexOf(guard) < feed.indexOf('nlEpochAcceptWindow(state, parsed, window)'));
        const subset = harness.replace(/^        (?:timelineEC|mixedEC|optionsEC|aliasesEC|identityEC|admissionEC|budgetsEC)\(\)\r?\n/gm, '');
        const controls = [
            { guard: '', retained: true, polling: false, expected: 'epoch-core-fixture: stale tail preserves published window and bounds' },
            { guard: '', retained: false, polling: false, expected: 'native-live: published epoch history unavailable' },
            { guard: guard.replace(comparison, comparison.replace(' < ', ' <= ')), retained: true, polling: false,
                expected: 'epoch-core-fixture: unchanged tail still refreshes upstream health without publication' },
            { guard: guard.replace('            return', '            state.lastUpstreamProgress = nowMs\n            return'), retained: true, polling: false,
                expected: 'epoch-core-fixture: stale tail cannot refresh progress' },
            { guard: guard.replace('if not state.pollFromRequest then state.nextPoll = nowMs + parsed.targetDuration * 500&', 'if not state.pollFromRequest then state.nextPoll = nowMs'), retained: true, polling: false,
                expected: 'epoch-core-fixture: changed stale snapshot keeps source target polling floor' },
            { guard: guard.replace('nlAcceptPlaylistPoll(state, payload, parsed.targetDuration, nowMs, tail.sequence, tail.durationUs)', "' Deliberately removed request polling acceptance"), retained: true, polling: true,
                expected: 'epoch-core-fixture: changed stale snapshot keeps source target polling floor' }
        ];
        for (const control of controls) {
            const changed = source.replace(guard, control.guard);
            assert.notEqual(changed, source);
            assert.deepEqual(bsc.Parser.parse(changed, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            await fs.writeFile(path.join(dir, 'rokuDemuxCore.brs'), changed);
            await fs.writeFile(path.join(dir, 'main.brs'), subset
                .replace('for each retained in [true, false]', `for each retained in [${control.retained}]`)
                .replace('for each requestPolling in [false, true]', `for each requestPolling in [${control.polling}]`));
            const result = await execute();
            requireExecution(result);
            assert.deepEqual(result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_EPOCH_CORE_FAIL:')),
                [`STITCH_EPOCH_CORE_FAIL: ${control.expected}`]);
            assert.doesNotMatch(result.output, /STITCH_EPOCH_CORE_PASS:/);
        }
        t.diagnostic(`${controls.length} actual stale-tail mutations fail at normal child exit, including retained and retired history`);
    });
});

test('finite child runner rejects actual timeout/output/crash/nonzero/stale/zero results', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const positive = cases.map(name => `STITCH_EPOCH_CORE_CASE: ${name}\n`).join('') +
        `STITCH_EPOCH_CORE_PASS: ${marker} cases=${cases.length} assertions=1 goldens=1 manifests=8 pairs=9 gateCalls=3\n`;
    const script = output => `process.stdout.write(${JSON.stringify(output)});`;
    const args = ['-e', script(positive)];
    const valid = await runChild(args, os.tmpdir(), 2000);
    assert.doesNotThrow(() => requirePositive(valid, marker));
    assert.doesNotThrow(() => requirePositive({ ...valid, output: valid.output.replace(/\n/g, '\r\n') }, marker));
    const timeout = await runChild(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150);
    assert.equal(timeout.timedOut, true);
    const overflow = await runChild(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(overflow.exceeded, true);
    const nonzero = await runChild(['-e', script(positive) + 'process.exitCode=9;'], os.tmpdir(), 2000);
    assert.equal(nonzero.code, 9);
    for (const bad of [timeout, overflow, nonzero,
        { ...valid, output: valid.output.replace(marker, 'STALE_MARKER') },
        { ...valid, output: valid.output + 'EXIT_BRIGHTSCRIPT_CRASH\n' },
        { ...valid, output: valid.output.replace('assertions=1', 'assertions=0') },
        { ...valid, output: valid.output + valid.output },
        { ...valid, output: valid.output.replace('STITCH_EPOCH_CORE_CASE: ', 'FOREIGN_CASE: ') }
    ]) assert.throws(() => requirePositive(bad, marker));
});
