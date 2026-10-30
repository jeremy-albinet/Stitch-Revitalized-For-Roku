'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const bsc = require('brighterscript');
const corpus = require('./fixtures/roku-vod-index/corpus');
const root = path.resolve(__dirname, '../..');
const sourcePath = path.join(root, 'source/utils/rokuVodIndex.brs');
const fixturePath = path.join(__dirname, 'fixtures/roku-vod-index/main.brs');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

function runChild(args, cwd, timeoutMs = 60000, outputLimit = 1024 * 1024) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, args, { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', bytes = 0, exceeded = false, timedOut = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = chunk => {
            if (exceeded) return;
            bytes += chunk.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += chunk.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error.name; });
        child.once('close', code => { clearTimeout(timer); resolve({ code, output, timedOut, exceeded, startupError }); });
    });
}

function normalExit(result) {
    const detail = result.output.slice(-14000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}

function accept(result, marker) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_VOD_INDEX_FAIL:/, result.output);
    const summaries = result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_VOD_INDEX_RESULT: '));
    assert.equal(summaries.length, 1, result.output);
    assert.ok(summaries[0].startsWith(`STITCH_VOD_INDEX_RESULT: ${marker} `), 'fresh result required');
    const summary = JSON.parse(summaries[0].slice(`STITCH_VOD_INDEX_RESULT: ${marker} `.length));
    assert.ok(Number.isInteger(summary.assertions) && summary.assertions > 0);
    assert.equal(summary.failures, 0);
    return summary.assertions;
}

async function fixture(mode, mutation) {
    const prefix = 'stitch-vod-index-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const original = await fs.readFile(sourcePath);
    try {
        const marker = randomUUID();
        let source = original.toString();
        assert.deepEqual(bsc.Parser.parse(source, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        if (mutation) {
            assert.equal(source.split(mutation[0]).length, 2, 'one actual mutation anchor required');
            source = source.replace(mutation[0], mutation[1]);
        }
        await fs.writeFile(path.join(dir, 'rokuVodIndex.brs'), source);
        if (!mutation) assert.deepEqual(await fs.readFile(path.join(dir, 'rokuVodIndex.brs')), original);
        const large = corpus.packed(7376, 10000000n);
        assert.ok(Buffer.byteLength(large.text) <= 262144);
        const harness = (await fs.readFile(fixturePath, 'utf8'))
            .replace('__MARKER__', marker).replace('__MODE__', mode).replace('__LARGE_DIGEST__', sha(large.records));
        assert.deepEqual(bsc.Parser.parse(harness, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), harness);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Pure Recorded Index Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const data = { small: corpus.small, crlf: corpus.small.replaceAll('\n', '\r\n'), single: corpus.single,
            defaultSequence: corpus.single.replace('#EXT-X-MEDIA-SEQUENCE:17\n', ''),
            absolute: corpus.single.replace('0.m4s', `${corpus.origin}/absolute.m4s?x=fixture%2B%25`), comments: corpus.comments, bad: corpus.bad };
        await fs.writeFile(path.join(dir, 'corpus.json'), JSON.stringify(data));
        await fs.writeFile(path.join(dir, 'large.bin'), large.text);
        const existingLines = corpus.single.split('\n').length - 1;
        for (const [name, limit] of [['comment-lines-max.bin', 16448], ['comment-lines-over.bin', 16449]]) {
            const body = corpus.single.replace('#EXT-X-ENDLIST\n', '#c\n'.repeat(limit - existingLines) + '#EXT-X-ENDLIST\n');
            assert.ok(Buffer.byteLength(body) <= 262144, `${name} isolates ignored-comment line count`);
            await fs.writeFile(path.join(dir, name), body);
        }
        const result = await runChild([cli, '--no-sg', '--root', dir, 'rokuVodIndex.brs', 'main.brs'], dir);
        assert.deepEqual(await fs.readFile(sourcePath), original, 'actual source must remain unchanged during execution');
        return { result, marker };
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual recorded index retains all7376 entries, packed offsets, microseconds and exact pinned queries', { timeout: 90000 }, async t => {
    const { result, marker } = await fixture('normal');
    t.diagnostic(`${accept(result, marker)} actual pure-index assertions; no network/backend/device claim`);
});

test('actual recorded index enforces ignored-comment line-count boundaries', { timeout: 210000 }, async t => {
    // Shared entry, duration and blank-line limits run through both APIs in
    // roku-vod-preflight. Keep this distinct ignored-comment input here.
    const boundaries = [['comment-lines-max', 1], ['comment-lines-over', 1]];
    for (const [mode, expectedAssertions] of boundaries) {
        const started = performance.now();
        t.diagnostic(`running boundary input ${mode}`);
        const { result, marker } = await fixture(mode);
        const count = accept(result, marker);
        assert.equal(count, expectedAssertions, `complete ${mode} assertions`);
        t.diagnostic(`${mode}: ${count} actual boundary assertions in ${Math.round(performance.now() - started)} ms`);
    }
});

test('tail-only lookup, inaccurate duration and wrong half-open boundary mutations fail normally', { timeout: 210000 }, async t => {
    for (const [before, after, label] of [
        ['recordOffset = entryNo * 24', 'recordOffset = (index.count - 1) * 24', 'first entry exists'],
        ['totalUs += pendingUs', 'totalUs += pendingUs + 1&', 'exact microsecond durations and nonzero sequence'],
        ['positionUs >= item.startUs + item.durationUs', 'positionUs > item.startUs + item.durationUs', 'last entry starts at exact cumulative duration']
    ]) {
        const { result, marker } = await fixture('small', [before, after]);
        normalExit(result);
        assert.ok(result.output.includes(`STITCH_VOD_INDEX_FAIL: ${label}`), result.output);
        assert.throws(() => accept(result, marker));
        t.diagnostic(`${label}: actual mutated handler rejected despite normal exit`);
    }
});

test('comment acceptance and unknown EXT refusal controls reject actual policy mutations', { timeout: 90000 }, async t => {
    for (const [before, after, label] of [
        ['else if line.Left(4) = "#EXT"\n                    if pendingUs <> invalid', 'else\n                    if pendingUs <> invalid', 'comments accept observed comment LF'],
        ['ended = true\n                    else\n                        return invalid', 'ended = true\n                    else\n                        \'Deliberately ignore unknown EXT tag', 'refuse unknown required tag']
    ]) {
        const { result, marker } = await fixture('comments', [before, after]);
        normalExit(result);
        assert.ok(result.output.includes(`STITCH_VOD_INDEX_FAIL: ${label}`), result.output.slice(-14000));
        assert.throws(() => accept(result, marker));
        t.diagnostic(`${label}: actual policy mutation rejected despite normal exit`);
    }
});

test('fresh positive-output validator rejects stale,failed,zero,crash and bounded transport failures', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const valid = `STITCH_VOD_INDEX_RESULT: ${marker} {"assertions":1,"failures":0}\n`;
    const result = output => ({ code: 0, output, timedOut: false, exceeded: false });
    accept(result(valid), marker);
    for (const output of [valid.replace(marker, randomUUID()), valid.replace('"assertions":1', '"assertions":0'),
        valid.replace('"failures":0', '"failures":1'), valid + valid,
        valid + 'STITCH_VOD_INDEX_FAIL: deliberate\n', valid + 'BRIGHTSCRIPT: ERROR: deliberate\n']) {
        assert.throws(() => accept(result(output), marker));
    }
    const timed = await runChild(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timed.timedOut, true);
    assert.throws(() => accept(timed, marker));
    const overflow = await runChild(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(overflow.exceeded, true);
    assert.throws(() => accept(overflow, marker));
    const nonzero = await runChild(['-e', `process.stdout.write(${JSON.stringify(valid)}); process.exitCode=7;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 7);
    assert.throws(() => accept(nonzero, marker));
});
