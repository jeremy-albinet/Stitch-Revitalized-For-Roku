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
const prefix = 'stitch-vod-cache-';
const sourceNames = ['rokuVodIndex', 'rokuDemuxBulk', 'rokuDemuxCommon', 'rokuVodCache'];
const modes = ['small', 'lru', 'budget', 'integrity', 'large'];
const fixtureFile = path.join(__dirname, 'fixtures/roku-vod-cache/main.brs');

function child(args, cwd, timeoutMs = 30000, outputLimit = 65536) {
    const started = performance.now();
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
        processChild.once('close', code => {
            clearTimeout(timer);
            resolve({code, output, bytes, timedOut, exceeded, startupError, elapsedMs: Math.round(performance.now() - started)});
        });
    });
}

function normalExit(result) {
    const detail = result.output.slice(-8000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, `finite child deadline\n${detail}`);
    assert.equal(result.exceeded, false, `bounded child output\n${detail}`);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}

function positive(result, marker, mode) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_VOD_CACHE_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_VOD_CACHE_CASE: ')), [`STITCH_VOD_CACHE_CASE: ${mode}`]);
    const summaries = lines.filter(line => line.startsWith('STITCH_VOD_CACHE_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const prefix = `STITCH_VOD_CACHE_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(prefix), 'fresh actual package marker required');
    const counts = JSON.parse(summaries[0].slice(prefix.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions', 'failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0, 'positive actual assertions required');
    assert.equal(counts.failures, 0);
    const bodyLines = lines.filter(line => line.startsWith('STITCH_VOD_CACHE_BYTES: '));
    assert.equal(bodyLines.length, mode === 'small' ? 1 : 0, 'only actual small mode returns complete cache bodies');
    if (mode === 'small') {
        const body = JSON.parse(bodyLines[0].slice('STITCH_VOD_CACHE_BYTES: '.length));
        for (const [track, length, tag] of [['video', 12, 35], ['audio', 7, 99]]) {
            const expected = Buffer.alloc(length);
            expected[0] = expected[length - 1] = tag;
            assert.equal(body[track], expected.toString('hex'), `every cached ${track} byte equals independent JS golden`);
        }
    }
    return {assertions: counts.assertions, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const sources = new Map();
    try {
        for (const name of sourceNames) {
            const bytes = await fs.readFile(path.join(root, `source/utils/${name}.brs`));
            assert.deepEqual(bsc.Parser.parse(bytes.toString(), {mode: bsc.ParseMode.BrightScript}).diagnostics, [], `actual ${name} syntax`);
            sources.set(name, bytes);
            await fs.writeFile(path.join(dir, `${name}.brs`), bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, `${name}.brs`)), bytes, 'actual source copied byte-for-byte');
        }
        const harness = await fs.readFile(fixtureFile, 'utf8');
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, [], 'actual BRS fixture syntax');
        const playlist = '#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n' +
            '#EXT-X-MEDIA-SEQUENCE:95\n#EXT-X-MAP:URI="init.mp4?sig=synthetic"\n' +
            Array.from({length: 64}, (_, i) => `#EXTINF:10.000000,\n${i}.m4s?sig=synthetic-${i}\n`).join('') + '#EXT-X-ENDLIST\n';
        await fs.writeFile(path.join(dir, 'index.m3u8'), playlist);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Pure Recorded Cache Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const execute = async mode => {
            const marker = randomUUID();
            await fs.writeFile(path.join(dir, 'main.brs'), harness.replaceAll('__MODE__', mode).replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
                ...sourceNames.map(name => `${name}.brs`), 'main.brs'], dir);
            return {...result, marker};
        };
        await action({dir, sources, execute});
        for (const [name, bytes] of sources) {
            assert.deepEqual(await fs.readFile(path.join(root, `source/utils/${name}.brs`)), bytes, `frozen/owned ${name} unchanged during actual runs`);
        }
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('actual recorded cache enforces paired demand, sparse LRU, work budgets, leases and immutable identity', {timeout: 135000}, async t => {
    await withFixture(async ({execute}) => {
        for (const mode of modes) {
            const result = await execute(mode);
            t.diagnostic(JSON.stringify({mode, ...positive(result, result.marker, mode)}));
        }
        t.diagnostic('pure synthetic helper evidence; logical byte accounting does not measure native heap, throughput or playback');
    });
});

test('pin, reservation, atomic publication, eager allocation, idle purge and cleanup mutations fail normally', {timeout: 200000}, async t => {
    await withFixture(async ({dir, sources, execute}) => {
        const original = sources.get('rokuVodCache').toString();
        const mutations = [
            ['not excluded and not item.pinned and not nvcLeased(state, item.entryNo)', 'not excluded and not nvcLeased(state, item.entryNo)', 'budget', 'reserved 48MiB and 16MiB pair cannot overlap pinned and leased 10MiB cache'],
            ['maxPair = 16777216&', 'maxPair = 16777216&\n        if entryNo = 1 then maxPair = 8388608&', 'budget', 'reserved 48MiB and 16MiB pair cannot overlap pinned and leased 10MiB cache'],
            ['updated.Push(item)', 'item.audio = CreateObject("roByteArray")\n        updated.Push(item)', 'small', 'complete valid pair consumes reservation'],
            ['if state.leases.Count() > 0 or state.reservation <> invalid', 'if false', 'small', 'close retains active sends'],
            ['pairs: [], leases: [], reservation: invalid', 'pairs: [{entryNo: 0}], leases: [], reservation: invalid', 'small', 'no eager asset allocation'],
            ['if not rokuVodCacheAuthorize(state, sessionId, track, entryNo) then return invalid', 'if state.hits = 3& then state.pairs = []\n        if not rokuVodCacheAuthorize(state, sessionId, track, entryNo) then return invalid', 'lru', 'long pause resumes existing paired hit'],
            ['if item.videoBytes + item.audioBytes > 16777216 then return false', 'if false then return false', 'large', 'validator independently rejects combined pair above16MiB'],
            ['if total > state.cacheBudgetBytes - pending.maxPairBytes then return false', 'if false then return false', 'large', 'pending reservation independently rejects resident above8MiB']
        ];
        for (const [before, after, mode, expected] of mutations) {
            assert.equal(original.split(before).length, 2, 'one actual mutation anchor');
            await fs.writeFile(path.join(dir, 'rokuVodCache.brs'), original.replace(before, after));
            const result = await execute(mode);
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_VOD_CACHE_FAIL: ${result.marker} vod-cache-fixture: ${expected}`), result.output);
            assert.throws(() => positive(result, result.marker, mode));
            t.diagnostic(JSON.stringify({mutation: expected, elapsedMs: result.elapsedMs}));
        }
    });
});

test('cache output validator rejects stale, zero, duplicate, runtime and bounded child transport failures', {timeout: 15000}, async () => {
    const marker = randomUUID();
    const bodies = '{"video":"230000000000000000000023","audio":"63000000000063"}';
    const good = `STITCH_VOD_CACHE_BYTES: ${bodies}\nSTITCH_VOD_CACHE_CASE: small\nSTITCH_VOD_CACHE_PASS: ${marker} {"assertions":1,"failures":0}\n`;
    const base = {code: 0, output: good, bytes: good.length, timedOut: false, exceeded: false, startupError: undefined};
    positive(base, marker, 'small');
    for (const changed of [
        {output: good.replace(marker, randomUUID())}, {output: good.replace('"assertions":1', '"assertions":0')},
        {output: good.replace('"failures":0', '"failures":1')}, {output: good + good},
        {output: good.replace('CASE: small', 'CASE: lru')}, {output: good + 'STITCH_VOD_CACHE_FAIL: false pass\n'},
        {output: good.replace('230000000000000000000023', '230100000000000000000023')},
        {output: good + 'BRIGHTSCRIPT: ERROR: false pass\n'}, {output: good + 'BrightScript Debugger'},
        {code: 7}, {startupError: 'spawn failed'}
    ]) assert.throws(() => positive({...base, ...changed}, marker, 'small'));
    const timed = await child(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timed.timedOut, true);
    assert.throws(() => positive(timed, marker, 'small'));
    const over = await child(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(over.exceeded, true);
    assert.throws(() => positive(over, marker, 'small'));
    const nonzero = await child(['-e', `process.stdout.write(${JSON.stringify(good)}); process.exitCode=7;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 7);
    assert.throws(() => positive(nonzero, marker, 'small'));
});
