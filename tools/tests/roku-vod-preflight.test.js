'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { randomUUID, createHash } = require('node:crypto');
const bsc = require('brighterscript');
const corpus = require('./fixtures/roku-vod-index/corpus');
const newlineCorpus = require('./fixtures/roku-vod-preflight/newlines')(corpus);
const root = path.resolve(__dirname, '../..');
const fixturePath = path.join(__dirname, 'fixtures/roku-vod-preflight/main.brs');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const indexPath = 'source/utils/rokuVodIndex.brs';
const runtimePath = 'source/utils/rokuVodRuntime.brs';
const taskPath = 'components/Tasks/GetTwitchContent/GetTwitchContent.brs';
const dependencies = [indexPath, runtimePath, 'source/utils/rokuVodDescriptor.brs',
    'source/utils/rokuDemuxDescriptor.brs', 'source/utils/playbackHls.brs'];
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

// GitHub's Windows runners took just over 60 s for one boundary fixture.
function runChild(args, cwd, timeoutMs = 120000, outputLimit = 1024 * 1024) {
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

function normal(result) {
    const detail = result.output.slice(-14000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}

function accept(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /STITCH_VOD_PREFLIGHT_FAIL:/);
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_VOD_PREFLIGHT_RESULT: '));
    assert.equal(lines.length, 1, result.output);
    assert.ok(lines[0].startsWith(`STITCH_VOD_PREFLIGHT_RESULT: ${marker} `), 'fresh result required');
    const summary = JSON.parse(lines[0].slice(`STITCH_VOD_PREFLIGHT_RESULT: ${marker} `.length));
    assert.ok(Number.isInteger(summary.assertions) && summary.assertions > 0);
    assert.equal(summary.failures, 0);
    return summary.assertions;
}

function golden(text) {
    const records = [];
    let offset = 0, start = 0n, pending;
    for (const rawLine of text.split('\n')) {
        const line = rawLine.replace(/\r$/, '');
        if (line.startsWith('#EXTINF:')) {
            const [whole, fraction = ''] = line.slice(8).split(',')[0].split('.');
            pending = BigInt(whole) * 1000000n + BigInt(fraction.padEnd(6, '0') || '0');
        } else if (line && !line.startsWith('#')) {
            assert.notEqual(pending, undefined);
            const record = Buffer.alloc(24);
            record.writeUInt32BE(offset, 0);
            record.writeUInt32BE(Buffer.byteLength(line), 4);
            record.writeBigUInt64BE(pending, 8);
            record.writeBigUInt64BE(start, 16);
            records.push(record);
            start += pending;
            pending = undefined;
        }
        offset += Buffer.byteLength(rawLine) + 1;
    }
    const last = records.at(-1);
    return { recordsDigest: sha(Buffer.concat(records)), lastStartUs: Number(last.readBigUInt64BE(16)), lastDurationUs: Number(last.readBigUInt64BE(8)) };
}

async function fixture(mode, mutation) {
    const prefix = 'stitch-vod-preflight-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const originals = new Map(await Promise.all([...dependencies, taskPath].map(async file => [file, await fs.readFile(path.join(root, file))])));
    try {
        const marker = randomUUID();
        const names = [];
        for (const file of dependencies) {
            let body = originals.get(file).toString();
            if (mutation?.file === file) {
                assert.equal(body.split(mutation.before).length, 2, 'one actual mutation anchor');
                body = body.replace(mutation.before, mutation.after);
            }
            if (mode === 'writes' && file === indexPath) {
                const anchor = 'sub nviPut32(data as object, offset as integer, value as longinteger)';
                assert.equal(body.split(anchor).length, 2);
                body = body.replace(anchor, `${anchor}\n    throw "fixture: packed writes reached"`);
            }
            if (mode === 'traversal' && file === indexPath) {
                const anchor = 'lineParts = text.Split(newline)';
                assert.equal(body.split(anchor).length, 2);
                body = body.replace(anchor, 'lineParts = fixtureBoundedSplit(text, newline)');
            }
            assert.deepEqual(bsc.Parser.parse(body, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            const name = path.basename(file);
            names.push(name);
            await fs.writeFile(path.join(dir, name), body);
            if (!(mutation?.file === file) && !(['writes', 'traversal'].includes(mode) && file === indexPath)) {
                assert.deepEqual(await fs.readFile(path.join(dir, name)), originals.get(file), 'actual dependencies copied byte-identically');
            }
        }
        const task = originals.get(taskPath).toString();
        const extracted = task.match(/^function isMuxedCmafVariant\([^]*?^end function/gm);
        assert.equal(extracted?.length, 1, 'exact actual callback required');
        let callback = extracted[0];
        if (mutation?.file === taskPath) {
            assert.equal(callback.split(mutation.before).length, 2);
            callback = callback.replace(mutation.before, mutation.after);
        }
        const long = corpus.packed(7376, 10000000n);
        const origin = 'https://dfixture123.cloudfront.net';
        const source = `${origin}/archive/index.m3u8?master=fixture%2Bquery`;
        const pin = body => body.replaceAll(corpus.origin, origin);
        const goodBodies = [
            ['fractional', corpus.small], ['CRLF', corpus.small.replaceAll('\n', '\r\n')],
            ['no trailing LF', corpus.small.slice(0, -1)], ['default sequence', corpus.single.replace('#EXT-X-MEDIA-SEQUENCE:17\n', '')],
            ['absolute pinned query', corpus.single.replace('0.m4s', `${corpus.origin}/absolute.m4s?x=fixture%2B%25`)],
            ...corpus.comments.map(sample => [sample.name, sample.text]), ...newlineCorpus.good
        ];
        const data = { source, origin, single: pin(corpus.single),
            good: goodBodies.map(([name, body]) => { const text = pin(body); return { name, text, ...golden(text) }; }),
            bad: [...corpus.bad, ...newlineCorpus.bad].map(sample => ({ name: sample.name, text: pin(sample.text) })) };
        await fs.writeFile(path.join(dir, 'corpus.json'), JSON.stringify(data));
        const existingLines = corpus.single.split('\n').length - 1;
        const entries = (count, duration = '10', target = 10) => pin(corpus.playlist(count, duration, target));
        const maxBytesBase = pin(corpus.single);
        const bytesPadding = length => {
            let remaining = length - Buffer.byteLength(maxBytesBase), comments = '';
            while (remaining > 0) {
                const amount = Math.min(remaining, 4096);
                if (amount === 1) { comments += '\n'; remaining--; }
                else { comments += '#' + 'x'.repeat(amount - 2) + '\n'; remaining -= amount; }
            }
            return maxBytesBase.replace('#EXT-X-ENDLIST\n', comments + '#EXT-X-ENDLIST\n');
        };
        for (const [name, body] of [
            ['long.bin', pin(long.text)], ['entries-max.bin', entries(8192)], ['entries-over.bin', entries(8193)],
            ['duration-max.bin', entries(5760, '30', 30)], ['duration-over.bin', entries(5761, '30', 30)],
            ['lines-max.bin', pin(corpus.single) + '\n'.repeat(16448 - existingLines)],
            ['lines-over.bin', pin(corpus.single) + '\n'.repeat(16449 - existingLines)],
            ['unterminated-max.bin', pin(newlineCorpus.unterminatedMax)],
            ['unterminated-over.bin', pin(newlineCorpus.unterminatedOver)],
            ['newline-flood.bin', newlineCorpus.flood],
            ['bytes-max.bin', bytesPadding(262144)], ['bytes-over.bin', bytesPadding(262145)]
        ]) await fs.writeFile(path.join(dir, name), body);
        const main = (await fs.readFile(fixturePath, 'utf8')).replace('__MARKER__', marker)
            .replace('__MODE__', mode).replace('__LONG_RECORDS_DIGEST__', sha(long.records));
        assert.deepEqual(bsc.Parser.parse(main + '\n' + callback, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), main + '\n' + callback);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=VOD Preflight Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const result = await runChild([cli, '--no-sg', '--root', dir, ...names, 'main.brs'], dir);
        for (const [file, original] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), original, 'source immutable during focused execution');
        return { result, marker };
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual shared scan preserves grammar, complete packed goldens and fresh VOD deadline admission', { timeout: 90000 }, async t => {
    const { result, marker } = await fixture('grammar');
    t.diagnostic(`${accept(result, marker)} actual scan/runtime/callback assertions; HTTP/clock boundaries mocked`);
});

test('actual long full index and validation share7376 entries while preflight omits packed writes', { timeout: 150000 }, async t => {
    for (const mode of ['long', 'writes']) {
        const { result, marker } = await fixture(mode);
        t.diagnostic(`${mode}: ${accept(result, marker)} actual assertions`);
    }
});

test('both scan modes retain exact count,48h,line and byte ceilings', { timeout: 270000 }, async t => {
    for (const mode of ['entries', 'duration', 'lines', 'bytes']) {
        const { result, marker } = await fixture(mode);
        t.diagnostic(`${mode}: ${accept(result, marker)} actual boundary assertions`);
    }
});

test('actual traversal rejects excess LF fragmentation before Split and retains raw offsets and CR rules', { timeout: 210000 }, async t => {
    const positive = await fixture('traversal');
    t.diagnostic(`${accept(positive.result, positive.marker)} actual pre-Split allocation/line-ceiling assertions`);
    for (const mutation of [
        { file: indexPath, before: 'if lineCount > 16448 then return invalid', after: 'if lineCount > 999999 then return invalid', mode: 'traversal', label: 'excess lines refused before Split allocation' },
        { file: indexPath, before: 'nviPut32(records, at, offset + 0&)', after: 'nviPut32(records, at, offset + 1&)', mode: 'grammar', label: 'all independent packed records exact' }
    ]) {
        const { result, marker } = await fixture(mutation.mode, mutation);
        normal(result);
        assert.ok(result.output.includes(`STITCH_VOD_PREFLIGHT_FAIL: ${mutation.label}`), result.output.slice(-14000));
        assert.throws(() => accept(result, marker));
        t.diagnostic(`${mutation.label}: actual source mutation rejected normally`);
    }
});

test('ENDLIST,unknownEXT,count,full-builder and deadline regressions fail despite normal engine exit', { timeout: 330000 }, async t => {
    for (const mutation of [
        { file: indexPath, before: 'if not ended or count < 1', after: 'if count < 1', mode: 'grammar', label: 'validate refuses missing ENDLIST' },
        { file: indexPath, before: 'ended = true\r\n                    else\r\n                        return invalid', after: 'ended = true\r\n                    else\r\n                        \' Deliberate missing refusal', mode: 'grammar', label: 'validate refuses unknown required tag' },
        { file: indexPath, before: 'length > 2048 or count >= 8192', after: 'length > 2048 or count >= 8193', mode: 'count-refusal', label: 'validation rejects8193 entries' },
        { file: runtimePath, before: 'return rokuVodIndexValidate(bytes, sourceUrl, nviUrl(sourceUrl).origin)', after: 'return rokuVodIndexParse(bytes, sourceUrl, nviUrl(sourceUrl).origin) <> invalid', mode: 'writes', label: 'preflight never invokes packed writes' },
        { file: taskPath, before: 'm.playbackProbeClock.TotalMilliseconds() >= 15000', after: 'm.playbackProbeClock.TotalMilliseconds() > 999999', mode: 'callback', label: 'completion at or after deadline refuses' }
    ]) {
        // The formatter may choose LF or CRLF; anchor only adapts line separators.
        const source = await fs.readFile(path.join(root, mutation.file), 'utf8');
        if (!source.includes(mutation.before) && mutation.before.includes('\r\n')) {
            mutation.before = mutation.before.replaceAll('\r\n', '\n');
            mutation.after = mutation.after.replaceAll('\r\n', '\n');
        }
        const { result, marker } = await fixture(mutation.mode, mutation);
        normal(result);
        assert.ok(result.output.includes(`STITCH_VOD_PREFLIGHT_FAIL: ${mutation.label}`), result.output.slice(-14000));
        assert.throws(() => accept(result, marker));
        t.diagnostic(`${mutation.label}: actual source mutant rejected normally`);
    }
});

test('fresh preflight validator retains stale,failure,zero,crash,timeout,output and nonzero guards', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const valid = `STITCH_VOD_PREFLIGHT_RESULT: ${marker} {"assertions":1,"failures":0}\n`;
    const result = output => ({ code: 0, output, timedOut: false, exceeded: false });
    accept(result(valid), marker);
    for (const output of [valid.replace(marker, randomUUID()), valid + valid, valid.replace('"assertions":1', '"assertions":0'),
        valid.replace('"failures":0', '"failures":1'), valid + 'STITCH_VOD_PREFLIGHT_FAIL: deliberate\n',
        valid + 'BRIGHTSCRIPT: ERROR: deliberate\n', valid.replace('"failures":0', '"failures":')]) {
        assert.throws(() => accept(result(output), marker));
    }
    const timed = await runChild(['-e', 'setInterval(() => {},100);'], os.tmpdir(), 150, 1024);
    assert.equal(timed.timedOut, true);
    assert.throws(() => accept(timed, marker));
    const overflow = await runChild(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(overflow.exceeded, true);
    assert.throws(() => accept(overflow, marker));
    const nonzero = await runChild(['-e', `process.stdout.write(${JSON.stringify(valid)});process.exitCode=7;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 7);
    assert.throws(() => accept(nonzero, marker));
});
