'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/roku-demux-epochs');
const sourceFiles = ['source/utils/rokuDemuxCommon.brs', 'source/utils/rokuDemuxProtocol.brs'];
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const prefix = 'stitch-roku-epochs-';
const caseNames = ['legacy-finite', 'legacy-session', 'content-ad-content', 'short-boundaries',
    'rolled-ad', 'rolled-return', 'same-pair-discontinuity', 'maximum-identities',
    'ended-single', 'rounded-fraction', 'strict-malformed'];

function runChild(dir, timeoutMs = 20000, outputLimit = 65536) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [cli, '--no-sg', '--root', dir,
            ...sourceFiles, 'main.brs'], { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
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
        child.once('close', code => {
            clearTimeout(timer);
            resolve({ code, output, exceeded, timedOut, startupError });
        });
    });
}

function requireExecution(result) {
    const detail = result.output.slice(-10000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, `child deadline exceeded\n${detail}`);
    assert.equal(result.exceeded, false, `child output exceeded\n${detail}`);
    assert.equal(result.code, 0, `child exit ${result.code}\n${detail}`);
    assert.doesNotMatch(result.output,
        /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    return detail;
}

function requirePositive(result, marker) {
    const detail = requireExecution(result);
    assert.doesNotMatch(result.output, /STITCH_ROKU_EPOCH_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/);
    const summaries = lines.filter(line => line.startsWith('STITCH_ROKU_EPOCH_PASS:'));
    assert.equal(summaries.length, 1, `exactly one fresh summary\n${detail}`);
    assert.ok(summaries[0].startsWith(`STITCH_ROKU_EPOCH_PASS: ${marker} `), `fresh marker missing\n${detail}`);
    const counts = summaries[0].match(/cases=\s*(\d+) assertions=\s*(\d+) goldens=\s*(\d+) rejections=\s*(\d+)$/);
    assert.ok(counts, detail);
    const [cases, assertions, goldens, rejections] = counts.slice(1).map(Number);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_ROKU_EPOCH_CASE: ')),
        caseNames.map(name => `STITCH_ROKU_EPOCH_CASE: ${name}`));
    assert.equal(cases, caseNames.length);
    assert.ok(assertions > 0, 'actual native assertions must execute');
    assert.equal(goldens, 20, 'both complete manifests for every literal narrative snapshot');
    assert.ok(rejections >= 60, 'the complete strict malformed corpus must execute');
    return { cases, assertions, goldens, rejections };
}

async function withFixture(callback) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const sources = new Map();
    async function add(relative, bytes) {
        const target = path.join(dir, relative);
        await fs.mkdir(path.dirname(target), { recursive: true });
        await fs.writeFile(target, bytes);
    }
    try {
        for (const file of sourceFiles) {
            const bytes = await fs.readFile(path.join(root, file));
            sources.set(file, bytes);
            assert.deepEqual(bsc.Parser.parse(bytes.toString(), { mode: bsc.ParseMode.BrightScript }).diagnostics, [],
                `actual ${file} parses without diagnostics`);
            await add(file, bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, file)), bytes, 'production functions copied byte-for-byte');
        }
        const marker = randomUUID();
        const harness = (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replace('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(harness, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await add('main.brs', harness);
        await add('manifest', 'title=Pure Epoch Publication Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const goldens = (await fs.readdir(fixtures)).filter(name => name.endsWith('.m3u8')).sort();
        assert.equal(goldens.length, 20);
        for (const name of goldens) {
            const bytes = await fs.readFile(path.join(fixtures, name));
            assert.ok(bytes.length > 0 && bytes.length <= 16384 && bytes.every(byte => byte < 128));
            await add(`goldens/${name}`, bytes);
        }
        await callback({ dir, marker, sources, execute: () => runChild(dir) });
        for (const [file, bytes] of sources) {
            assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, `frozen ${file} unchanged by execution`);
        }
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual versioned publication emits strict legacy/epoch byte goldens and complete assets', { timeout: 60000 }, async t => {
    await withFixture(async ({ marker, execute }) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(requirePositive(result, marker)));
        for (const output of [result.output, result.output.replace(/\r?\n/g, '\r\n')]) {
            assert.doesNotThrow(() => requirePositive({ ...result, output }, marker));
        }
        for (const bad of [
            { ...result, code: 1 }, { ...result, timedOut: true }, { ...result, exceeded: true },
            { ...result, output: result.output + '\nEXIT_BRIGHTSCRIPT_CRASH\n' },
            { ...result, output: result.output.replace(/assertions=\s*\d+/, 'assertions=0') },
            { ...result, output: result.output + result.output },
            { ...result, output: result.output.replace('STITCH_ROKU_EPOCH_CASE: rolled-ad', 'STITCH_ROKU_EPOCH_CASE: foreign') },
            { ...result, output: result.output.replace(/goldens=\s*\d+/, 'goldens=0') }
        ]) assert.throws(() => requirePositive(bad, marker));
        assert.throws(() => requirePositive(result, 'STALE_MARKER'));
        t.diagnostic('metadata validation only; no init-byte, native decoder, Server advertising, or sustained-playback approval');
    });
});

test('removed epoch/pair/MAP/discontinuity/asset guards fail at normal child exit', { timeout: 180000 }, async t => {
    await withFixture(async ({ dir, marker, sources, execute }) => {
        const file = 'source/utils/rokuDemuxProtocol.brs';
        const source = sources.get(file).toString();
        const mutations = [
            { before: 'if segment.epoch <> previous.epoch and segment.epoch <> previous.epoch + 1& then return false',
                after: "' Deliberately removed epoch progression guard", expected: 'strict publication rejects epoch-backward' },
            { before: 'if segment.epoch = previous.epoch and (segment.initVideoId <> previous.initVideoId or segment.initAudioId <> previous.initAudioId) then return false',
                after: "' Deliberately removed same-epoch map guard", expected: 'strict publication rejects same-epoch-map-change' },
            { before: 'if videoPairs[segment.initVideoId] <> segment.initAudioId then return false',
                after: "' Deliberately removed complete video pair guard", expected: 'strict publication rejects partial-video-pair' },
            { before: 'if audioPairs[segment.initAudioId] <> segment.initVideoId then return false',
                after: "' Deliberately removed complete audio pair guard", expected: 'strict publication rejects partial-audio-pair' },
            { before: 'if previousEpoch >= 0 then text += "#EXT-X-DISCONTINUITY" + nl',
                after: "' Deliberately removed boundary emission", expected: 'literal complete byte golden content-ad-content video' },
            { before: 'text += "#EXT-X-MAP:URI=" + quote + "/asset/" + initId + quote + nl',
                after: 'if previousEpoch < 0 then text += "#EXT-X-MAP:URI=" + quote + "/asset/" + initId + quote + nl',
                last: true, expected: 'literal complete byte golden content-ad-content video' },
            { before: 'ids.Push(segment.initVideoId)', after: 'ids.Push(publication.initVideoId)',
                expected: 'every epoch init pair advertised content-ad-content' }
        ];
        for (const mutation of mutations) {
            const index = mutation.last ? source.lastIndexOf(mutation.before) : source.indexOf(mutation.before);
            assert.ok(index >= 0, 'real production mutation target exists');
            if (!mutation.last) assert.equal(source.indexOf(mutation.before, index + 1), -1, 'single production mutation target');
            const changed = source.slice(0, index) + mutation.after + source.slice(index + mutation.before.length);
            assert.deepEqual(bsc.Parser.parse(changed, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            await fs.writeFile(path.join(dir, file), changed);
            const result = await execute();
            requireExecution(result);
            assert.deepEqual(result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_ROKU_EPOCH_FAIL:')),
                [`STITCH_ROKU_EPOCH_FAIL: epoch-fixture: ${mutation.expected}`]);
            assert.doesNotMatch(result.output, /STITCH_ROKU_EPOCH_PASS:/);
            assert.throws(() => requirePositive(result, marker));
        }
        t.diagnostic(`${mutations.length} actual production mutations rejected with normal exit 0`);
    });
});
