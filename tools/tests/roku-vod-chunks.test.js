'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID, createHash} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');
const {corpus, inspect} = require('./fixtures/roku-vod-chunks/corpus');
const {workerProof} = require('./fixtures/roku-vod-large/runner');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/roku-vod-chunks');
const prefix = 'stitch-vod-chunks-';
const sourceNames = ['rokuDemuxBulk', 'rokuDemuxInitMetadata', 'rokuVodChunks'];
const cases = ['init-timing-defaults-and-refusals', 'actual-bulk-full-byte-and-absolute-timing-goldens',
    'trailing-metadata-preserved-video-only', 'entire-tail-addressing-layout-and-work-refusals',
    'stale-plan-cancel-and-close-release', 'actual-output-bound-and-helper-failure-release'];
const sha = data => createHash('sha256').update(data).digest('hex');

function child(args, cwd, timeoutMs = 40000, outputLimit = 1048576) {
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
        processChild.once('error', error => {startupError = error;});
        processChild.once('close', code => {clearTimeout(timer); resolve({code, output, bytes, timedOut, exceeded, startupError});});
    });
}

function execution(result) {
    const detail = result.output.slice(-8000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, `finite child deadline\n${detail}`);
    assert.equal(result.exceeded, false, `bounded child output\n${detail}`);
    assert.equal(result.code, 0, `child exit\n${detail}`);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    workerProof(result, true);
    return detail;
}

function positive(result, marker, expected, mode = 'goldens') {
    const detail = execution(result);
    assert.doesNotMatch(result.output, /STITCH_VOD_CHUNKS_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/);
    const selected = mode === 'goldens' ? cases.slice(0, 3) : mode === 'states' ? [cases[0], ...cases.slice(4)] : [cases[0], cases[3]];
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_VOD_CHUNKS_CASE: ')), selected.map(name => `STITCH_VOD_CHUNKS_CASE: ${name}`));
    const passes = lines.filter(line => line.startsWith('STITCH_VOD_CHUNKS_PASS: '));
    assert.equal(passes.length, 1, detail);
    assert.ok(passes[0].startsWith(`STITCH_VOD_CHUNKS_PASS: ${marker} `), 'new package marker required');
    const counts = passes[0].match(/ cases=\s*(\d+) assertions=\s*(\d+)$/);
    assert.ok(counts, detail);
    assert.equal(Number(counts[1]), selected.length);
    assert.ok(Number(counts[2]) > 0, 'actual positive native assertions required');
    const actualBytes = lines.filter(line => line.startsWith('STITCH_VOD_CHUNKS_BYTES: '));
    assert.equal(actualBytes.length, mode === 'goldens' ? 1 : 0, 'only golden mode returns the actual full output pair');
    if (mode === 'goldens') {
    const decoded = JSON.parse(actualBytes[0].slice('STITCH_VOD_CHUNKS_BYTES: '.length));
    for (const kind of ['video', 'audio']) {
        assert.match(decoded[kind], /^(?:[0-9a-f]{2})+$/);
        const bytes = Buffer.from(decoded[kind], 'hex');
        assert.equal(bytes.length, expected.media[kind].count);
        assert.equal(sha(bytes), expected.media[kind].sha256);
        assert.equal(decoded[kind], expected.media[kind].hex, 'full native output equals independent builder');
        const read = inspect(bytes, {1: kind});
        assert.deepEqual(read[kind], expected.original[kind], `every native ${kind} sample payload/DTS/PTS/duration/flags`);
        assert.deepEqual(read.events, kind === 'video' ? expected.original.events : [], 'exact video-only metadata');
    }
    }
    return {cases: Number(counts[1]), assertions: Number(counts[2]), outputBytes: result.bytes};
}

async function withFixture(run) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const source = new Map();
    try {
        for (const name of sourceNames) {
            const file = `source/utils/${name}.brs`;
            const bytes = await fs.readFile(path.join(root, file));
            assert.deepEqual(bsc.Parser.parse(bytes.toString(), {mode: bsc.ParseMode.BrightScript}).diagnostics, [], `actual ${name} syntax`);
            source.set(name, bytes);
            await fs.writeFile(path.join(dir, `${name}.brs`), bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, `${name}.brs`)), bytes, 'unchanged native implementation copied exactly');
        }
        const seed = JSON.parse(await fs.readFile(path.join(fixture, 'init-seed.json'), 'utf8'));
        assert.equal(seed.synthetic, true);
        const initial = Buffer.from(seed.hex, 'hex');
        assert.equal(sha(initial), seed.sha256, 'checked self-contained synthetic AVC/AAC seed');
        const expected = corpus(initial);
        const marker = randomUUID();
        const harness = await fs.readFile(path.join(fixture, 'main.brs'), 'utf8');
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, [], 'native fixture syntax');
        await fs.writeFile(path.join(dir, 'corpus.json'), JSON.stringify(expected));
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Bounded Recorded Chunk Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const execute = async (mode = 'goldens') => {
            const runMarker = randomUUID();
            await fs.writeFile(path.join(dir, 'main.brs'), harness.replace('__MODE__', mode).replaceAll('__MARKER__', runMarker));
            // The engine handles byte reads directly; this entry only records worker/read proof.
            // Keep the same actual helpers, full-byte assertions, worker proof and finite deadline.
            const entry = path.join(fixture, '../roku-vod-large/engine.js');
            const result = await child([entry, '--no-sg', '--root', dir, '--worker-marker', runMarker,
                ...sourceNames.map(name => `${name}.brs`), 'main.brs'], dir);
            return {...result, marker: runMarker, workerAdapter: true};
        };
        await run({dir, source, expected, marker, execute});
        for (const [name, bytes] of source) assert.deepEqual(await fs.readFile(path.join(root, `source/utils/${name}.brs`)), bytes, `owned/frozen ${name} unchanged during execution`);
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('actual recorded chunk caller preserves every byte/time across 95 pairs and rejects unsafe whole inputs', {timeout: 180000}, async t => {
    await withFixture(async ({expected, marker, execute}) => {
        const start = performance.now();
        for (const mode of ['goldens', 'refusals', 'work', 'states']) {
            const attemptStart = performance.now();
            const result = await execute(mode);
            t.diagnostic(JSON.stringify({mode, ...positive(result, result.marker, expected, mode), elapsedMs: Math.round(performance.now() - attemptStart)}));
        }
        t.diagnostic(`total elapsedMs=${Math.round(performance.now() - start)}`);
        t.diagnostic('synthetic offline helper evidence only; no network, native throughput, heap, decoder or recorded playback claim');
    });
});

test('metadata, absolute timing, pair cap and aggregate-output mutations cannot pass actual assertions', {timeout: 180000}, async () => {
    await withFixture(async ({dir, source, expected, marker, execute}) => {
        const mutations = [
            ['rokuDemuxBulk', 'if keep = "video" then nbRaw(plan, atom.offset, atom.size)', 'if false then nbRaw(plan, atom.offset, atom.size)', 'video golden', 'goldens'],
            ['rokuVodChunks', 'target.Append(converted)', 'rewriteVodChunksTime(converted)\n        target.Append(converted)', 'video golden', 'goldens'],
            ['rokuVodChunks', 'rvdcCheck(rootPairs <= 128)', 'rvdcCheck(rootPairs <= 129)', 'whole-input refusal too-many-pairs', 'refusals'],
            ['rokuVodChunks', 'if target.Count() + converted.Count() > 16777216', 'if false', 'aggregate track output bound', 'states']
        ];
        for (const [name, needle, replacement, expectedFailure, mode] of mutations) {
            for (const [resetName, bytes] of source) await fs.writeFile(path.join(dir, `${resetName}.brs`), bytes);
            const original = source.get(name).toString();
            assert.equal(original.split(needle).length, 2, 'exactly one actual mutation seam');
            await fs.writeFile(path.join(dir, `${name}.brs`), original.replace(needle, replacement));
            const result = await execute(mode);
            execution(result);
            assert.match(result.output, new RegExp(`STITCH_VOD_CHUNKS_FAIL: ${result.marker}`), 'normal failed actual assertion');
            assert.ok(result.output.includes(expectedFailure), `exact mutation failure\n${result.output.slice(-4000)}`);
            assert.throws(() => positive(result, result.marker, expected, mode));
        }
    });
});

test('recorded chunk runner rejects stale/zero/duplicate/runtime/nonzero/timeout/oversize results', () => {
    const marker = 'fresh-native-fixture';
    const base = {code: 0, output: '', bytes: 0, exceeded: false, timedOut: false, startupError: undefined};
    for (const change of [{code: 1}, {timedOut: true}, {exceeded: true}, {startupError: new Error('start')},
        {output: 'BRIGHTSCRIPT: ERROR: boom'}, {output: 'runtime error'}, {output: 'Syntax Error'},
        {output: 'STITCH_VOD_CHUNKS_PASS: stale cases=6 assertions=150'},
        {output: `STITCH_VOD_CHUNKS_PASS: ${marker} cases=0 assertions=0`},
        {output: `STITCH_VOD_CHUNKS_PASS: ${marker} cases=6 assertions=150\nSTITCH_VOD_CHUNKS_PASS: ${marker} cases=6 assertions=150`}]) {
        assert.throws(() => positive({...base, ...change}, marker, {}));
    }
});


test('same large work-mode actual indivisible byte and sample guard mutants fail normally', {timeout:180000}, async t => {
    await withFixture(async ({dir,source,expected,execute}) => {
        const sourceBody=source.get('rokuVodChunks').toString();
        for(const [label,seams] of [
            ['one-pair-sample-work',[
                ['rvdcCheck(samples + count <= 8192&)','rvdcCheck(samples + count <= 8193&)'],
                ['rvdcCheck(atom.finish - chunkStart <= 4194304 and pairSamples <= 8192)','rvdcCheck(atom.finish - chunkStart <= 4194304 and pairSamples <= 8194)']]],
            ['one-pair-byte-work',[
                ['rvdcCheck(atom.finish - chunkStart <= 4194304 and pairSamples <= 8192)','rvdcCheck(atom.finish - chunkStart <= 12582912 and pairSamples <= 8192)'],
                ['rvdcCheck(data.Count() - chunkStart <= 4194304 and spans.Count() < 128)','rvdcCheck(data.Count() - chunkStart <= 12582912 and spans.Count() < 128)']]]
        ]) {
            let mutated=sourceBody;
            for(const [before,after] of seams) {assert.equal(mutated.split(before).length,2);mutated=mutated.replace(before,after);}
            await fs.writeFile(path.join(dir,'rokuVodChunks.brs'),mutated);
            const result=await execute('work');
            execution(result);
            assert.ok(result.output.includes(`whole-input refusal ${label}`),result.output.slice(-6000));
            assert.throws(()=>positive(result,result.marker,expected,'work'));
            t.diagnostic(`${label}: actual normal-exit same-work-mode mutation rejected`);
        }
    });
});
