'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const files = ['source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs',
    'source/utils/rokuDemuxCommon.brs', 'source/utils/rokuDemuxCore.brs', 'source/utils/rokuDemuxProtocol.brs', 'source/utils/twitchAdProtocol.brs',
    'components/Tasks/TwitchAdMetadata/TwitchAdMetadata.brs'];
const fixture = path.join(__dirname, 'fixtures/ad-clock-adapter/main.brs');
const prefix = 'stitch-ad-clock-adapter-';

function child(args, cwd, timeoutMs = 30000, outputLimit = 65536) {
    const start = performance.now();
    return new Promise(resolve => {
        const processChild = spawn(process.execPath, args, {cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => {timedOut = true; processChild.kill();}, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) {exceeded = true; processChild.kill(); return;}
            output += data.toString();
        };
        processChild.stdout.on('data', collect);
        processChild.stderr.on('data', collect);
        processChild.once('error', error => {startupError = error.name;});
        processChild.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({code, signal, output, bytes, timedOut, exceeded, startupError, elapsedMs: Math.round(performance.now() - start)});
        });
    });
}

function normal(result) {
    const detail = result.output.slice(-10000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception|failed to set up component/i, detail);
}

function positive(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /STITCH_AD_CLOCK_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const begin = `STITCH_AD_CLOCK_BEGIN: ${marker}`;
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_AD_CLOCK_BEGIN: ')), [begin]);
    const ends = lines.filter(line => line.startsWith('STITCH_AD_CLOCK_END: '));
    assert.equal(ends.length, 1, result.output);
    const tag = `STITCH_AD_CLOCK_END: ${marker} `;
    assert.ok(ends[0].startsWith(tag));
    assert.ok(lines.indexOf(begin) < lines.indexOf(ends[0]));
    const counts = JSON.parse(ends[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions', 'failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    return {assertions: counts.assertions, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const originals = new Map();
    try {
        for (const file of files) {
            const bytes = await fs.readFile(path.join(root, file));
            originals.set(file, bytes);
            assert.deepEqual(bsc.Parser.parse(bytes.toString(), {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await fs.writeFile(path.join(dir, path.basename(file)), bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, path.basename(file))), bytes);
        }
        const main = await fs.readFile(fixture, 'utf8');
        assert.deepEqual(bsc.Parser.parse(main, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        const execute = async (replacement, replacementFile = 'source/utils/twitchAdClock.brs') => {
            const marker = randomUUID();
            for (const file of ['source/utils/twitchAdClock.brs', 'source/utils/twitchAdProtocol.brs']) {
                await fs.writeFile(path.join(dir, path.basename(file)), originals.get(file));
            }
            if (replacement) await fs.writeFile(path.join(dir, path.basename(replacementFile)), replacement);
            await fs.writeFile(path.join(dir, 'main.brs'), main.replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
                ...files.map(file => path.basename(file)), 'main.brs'], dir);
            return {...result, marker};
        };
        await action({execute, sources: originals});
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive: true, force: true});
    }
}

test('actual presented UTC adapter and immutable source-bound manifest projection', {timeout: 40000}, async t => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
    });
});

test('actual native/source/local epoch and UTC guards fail despite normal engine exit', {timeout: 160000}, async t => {
    await withFixture(async ({execute, sources}) => {
        for (const [file, before, after] of [
            ['source/utils/twitchAdClock.brs', 'if info.epoch <> 1 then return invalid', 'if info.epoch <> 0 and info.epoch <> 1 then return invalid'],
            ['source/utils/twitchAdClock.brs', 'if match.epoch <> epoch or match.durationUs <> target.durationUs then return invalid', 'if match.durationUs <> target.durationUs then return invalid'],
            ['source/utils/twitchAdProtocol.brs', 'if match.epoch <> saved.sourceEpoch or selected.epoch <> saved.sourceEpoch then return invalid', 'if selected.epoch <> saved.sourceEpoch then return invalid'],
            ['source/utils/twitchAdProtocol.brs', 'if anchor.epoch <> target.epoch then return false', "' Deliberately removed local boundary binding"],
            ['source/utils/twitchAdClock.brs', 'if segment.epoch <> previous.epoch and difference < 0& then return false', "' Deliberately removed cross-epoch UTC nonoverlap"]
        ]) {
            const source = sources.get(file).toString();
            assert.equal(source.split(before).length, 2, 'unique actual guard mutation');
            const result = await execute(source.replace(before, after), file);
            normal(result);
            assert.throws(() => positive(result, result.marker));
            assert.match(result.output, /STITCH_AD_CLOCK_FAIL:/);
            t.diagnostic(JSON.stringify({mutant: before, normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
        }
    });
});

test('finite output validator admits LF/CRLF and rejects stale, reordered, empty and crashed runs', () => {
    const marker = 'fresh-control';
    const output = `STITCH_AD_CLOCK_BEGIN: ${marker}\nSTITCH_AD_CLOCK_END: ${marker} {"assertions":1,"failures":0}\n`;
    const result = {code: 0, signal: null, output, bytes: output.length, timedOut: false, exceeded: false};
    positive(result, marker);
    positive({...result, output: output.replaceAll('\n', '\r\n')}, marker);
    for (const bad of [
        {...result, code: 1}, {...result, signal: 'SIGTERM'}, {...result, timedOut: true}, {...result, exceeded: true},
        {...result, startupError: 'Error'}, {...result, output: output.replace('"assertions":1', '"assertions":0')},
        {...result, output: output.replace('"failures":0', '"failures":1')},
        {...result, output: output.replaceAll(marker, 'stale')}, {...result, output: output + output},
        {...result, output: output.trim().split('\n').reverse().join('\n')},
        {...result, output: output + 'BRIGHTSCRIPT: ERROR: fake crash\n'}
    ]) assert.throws(() => positive(bad, marker));
});

// Exact production Task logic. Only unavailable native transfer/filesystem/port
// construction, wait/event type, file read and response assignment are shims;
// deadlines, configuration calls, identity, order and cleanup remain actual.
async function executeMetadataIo(mutate = false, fixtureName = 'io-main.brs') {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = randomUUID();
    const originals = new Map();
    try {
        for (const file of files) {
            const bytes = await fs.readFile(path.join(root, file));
            originals.set(file, bytes);
            let source = bytes.toString();
            if (file.endsWith('/TwitchAdMetadata.brs')) {
                source = source.replace(/CreateObject\("(roMessagePort|roTimespan|roFileSystem|roUrlTransfer)"\)/g, 'adFixtureCreateObject("$1")')
                    .replace('event = wait(50, m.port)', 'event = adFixtureWait(50, m.port)')
                    .replace('type(event) = "roUrlEvent"', 'adFixtureType(event) = "roUrlEvent"')
                    .replace('text = ReadAsciiFile(m.path)', 'text = adFixtureRead(m.path)')
                    .replace(/m\.top\.response = ([^\r\n]+)/g, 'adFixtureEmit($1)');
                if (mutate === true) {
                    assert.equal(source.split('now >= m.deadline').length, 3);
                    source = source.replaceAll('now >= m.deadline', 'now > m.deadline');
                } else if (mutate === 'inflight-exists') {
                    const actualGuard = /if fs\.Exists\(m\.path\)\r?\n\s+stat = fs\.Stat\(m\.path\)/g;
                    const matches = source.match(actualGuard);
                    assert.equal(matches?.length, 1, 'one exact in-flight existence guard');
                    source = source.replace(actualGuard, match => match.replace('if fs.Exists(m.path)', 'if true'));
                } else if (mutate === 'gap-terminal' || mutate === 'gap-empty') {
                    const gapBranch = /if not twitchAdClockTimelineValid\(timeline\)\r?\n(?:\s*'[^\r\n]*\r?\n)*\s+adMetadataEmpty\(owner\)/g;
                    assert.equal(source.match(gapBranch)?.length, 1, 'one actual optional timing branch');
                    source = source.replace(gapBranch, match => mutate === 'gap-terminal'
                        ? `${match}\n                        exit while`
                        : match.replace('adMetadataEmpty(owner)', 'm.stopped = false'));
                } else if (mutate === 'gap-cleanup' || mutate === 'gap-identity') {
                    const guard = mutate === 'gap-cleanup'
                        ? 'if not fs.Delete(m.path) then exit while'
                        : 'if event.GetSourceIdentity() = m.identity';
                    assert.equal(source.split(guard).length, 2, 'one actual cleanup/identity guard');
                    source = source.replace(guard, mutate === 'gap-cleanup' ? 'if false then exit while' : 'if true');
                }
            }
            assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await fs.writeFile(path.join(dir, path.basename(file)), source);
        }
        assert.ok(['io-main.brs', 'inflight-main.brs', 'gap-main.brs'].includes(fixtureName));
        const main = (await fs.readFile(path.join(__dirname, 'fixtures/ad-clock-adapter', fixtureName), 'utf8')).replaceAll('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(main, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), main);
        const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, ...files.map(file => path.basename(file)), 'main.brs'], dir);
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes);
        return {...result, marker};
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive: true, force: true});
    }
}
test('actual metadata Task deadline, identity, typed stop and staging-file cleanup with native IO unavailable', {timeout: 40000}, async t => {
    const result = await executeMetadataIo();
    t.diagnostic(JSON.stringify(positive(result, result.marker)));
});
test('original five-second Task deadline equality guard removal is rejected', {timeout: 40000}, async t => {
    const result = await executeMetadataIo(true);
    normal(result); assert.throws(() => positive(result, result.marker));
    assert.match(result.output, /STITCH_AD_CLOCK_FAIL:/);
    t.diagnostic(JSON.stringify({guard: 'now >= m.deadline', normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
});

test('actual second metadata poll waits for an absent async file and preserves present-file/deadline/cleanup refusals', {timeout: 40000}, async t => {
    const result = await executeMetadataIo(false, 'inflight-main.brs');
    const proof = positive(result, result.marker);
    positive({...result, output: result.output.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')}, result.marker);
    t.diagnostic(JSON.stringify(proof));
});

test('restoring the old unguarded in-flight Stat fails actual two-poll progression despite normal exit', {timeout: 40000}, async t => {
    const result = await executeMetadataIo('inflight-exists', 'inflight-main.brs');
    normal(result);
    assert.throws(() => positive(result, result.marker));
    assert.match(result.output, /STITCH_AD_CLOCK_FAIL:.*actual independent two-poll publication count second-delayed/);
    assert.match(result.output, /STITCH_AD_CLOCK_FAIL:.*absent in-flight destination never receives Stat second-delayed/);
    t.diagnostic(JSON.stringify({guard: 'actual pending-path existence', normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
});

test('actual same metadata worker hides optional timing gaps and recovers without changing hard IO refusals', {timeout: 40000}, async t => {
    const result = await executeMetadataIo(false, 'gap-main.brs');
    const proof = positive(result, result.marker);
    positive({...result, output: result.output.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')}, result.marker);
    t.diagnostic(JSON.stringify(proof));
});

test('actual old gap termination and removed empty, deletion or identity guards fail with normal exit', {timeout: 135000}, async t => {
    for (const mutation of ['gap-terminal', 'gap-empty', 'gap-cleanup', 'gap-identity']) {
        const result = await executeMetadataIo(mutation, 'gap-main.brs');
        normal(result);
        assert.throws(() => positive(result, result.marker));
        assert.match(result.output, /STITCH_AD_CLOCK_FAIL:/);
        if (mutation === 'gap-terminal') assert.match(result.output, /same worker resumes valid metadata after optional gap/);
        if (mutation === 'gap-empty') assert.match(result.output, /actual gap explicitly publishes empty cues and bounds/);
        if (mutation === 'gap-cleanup') assert.match(result.output, /fresh poll must not overwrite an undeleted staging file/);
        if (mutation === 'gap-identity') assert.match(result.output, /hard response cannot supply later cues gap-stale/);
        t.diagnostic(JSON.stringify({guard: mutation, normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
    }
});

// Full actual Fetch/Core feed bodies run. Only native URL event/filesystem
// construction and reads are unavailable; flag guard and capture are unchanged.
async function executeFetchFlags(mutate = false) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = randomUUID(), originals = new Map();
    const runtimeFiles = [...files, 'source/utils/rokuDemuxFetch.brs'];
    try {
        for (const file of runtimeFiles) {
            const bytes = await fs.readFile(path.join(root, file));
            originals.set(file, bytes);
            let source = bytes.toString();
            if (file.endsWith('/rokuDemuxFetch.brs')) {
                for (const [before, after] of [
                    ['Type(event) <> "roUrlEvent"', 'fetchFlagType(event) <> "roUrlEvent"'],
                    ['payload = ReadAsciiFile(nlInputPath())', 'payload = fetchFlagRead(nlInputPath())']
                ]) {
                    assert.equal(source.split(before).length, 2, 'one exact unavailable native boundary');
                    source = source.replace(before, after);
                }
                source = source.replaceAll('CreateObject("roFileSystem")', 'fetchFlagCreateObject("roFileSystem")');
                if (mutate) {
                    const guard = 'if twitchAdClockBoolean(state.adClockEnabled) and state.adClockEnabled = true';
                    assert.equal(source.split(guard).length, 2, 'one actual typed-flag comparison');
                    source = source.replace(guard, 'if true');
                }
            }
            assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await fs.writeFile(path.join(dir, path.basename(file)), source);
        }
        const main = (await fs.readFile(path.join(__dirname, 'fixtures/ad-clock-adapter/fetch-flag-main.brs'), 'utf8')).replaceAll('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(main, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), main);
        const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
            ...runtimeFiles.map(file => path.basename(file)), 'main.brs'], dir);
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes);
        return {...result, marker};
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive: true, force: true});
    }
}

test('actual Fetch/Core completion keeps absent, malformed and false ad flags disabled', {timeout: 40000}, async t => {
    const result = await executeFetchFlags();
    t.diagnostic(JSON.stringify(positive(result, result.marker)));
});

test('actual opt-in guard removal captures disabled metadata and is rejected', {timeout: 40000}, async t => {
    const result = await executeFetchFlags(true);
    normal(result);
    assert.throws(() => positive(result, result.marker));
    assert.match(result.output, /STITCH_AD_CLOCK_FAIL:/);
    t.diagnostic(JSON.stringify({guard: 'typed Boolean true opt-in', normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
});
