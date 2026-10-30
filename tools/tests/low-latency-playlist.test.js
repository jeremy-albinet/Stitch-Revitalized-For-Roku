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
const sourcePath = path.join(root, 'source/utils/lowLatencyPlaylist.brs');
const fixturePath = path.join(__dirname, 'fixtures/low-latency-playlist/main.brs');
const prefix = 'stitch-low-latency-';
const modes = ['master', 'media', 'boundary', 'refusal'];

function child(args, cwd, timeoutMs = 30000, outputLimit = 65536) {
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
            resolve({code, output, timedOut, exceeded, startupError});
        });
    });
}

function normalExit(result) {
    const detail = result.output.slice(-8000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}

function positive(result, marker, mode) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_LOW_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_LOW_CASE: ')), [`STITCH_LOW_CASE: ${mode}`]);
    const summaries = lines.filter(line => line.startsWith('STITCH_LOW_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_LOW_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'fresh helper marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    return counts.assertions;
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const original = await fs.readFile(sourcePath);
    try {
        assert.deepEqual(bsc.Parser.parse(original.toString(), {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        const harness = await fs.readFile(fixturePath, 'utf8');
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await fs.writeFile(path.join(dir, 'lowLatencyPlaylist.brs'), original);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Low Latency Playlist Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const execute = async mode => {
            const marker = randomUUID();
            await fs.writeFile(path.join(dir, 'main.brs'), harness.replaceAll('__MODE__', mode).replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, 'lowLatencyPlaylist.brs', 'main.brs'], dir);
            return {...result, marker};
        };
        await action({dir, original, execute});
        assert.deepEqual(await fs.readFile(sourcePath), original, 'source unchanged after execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('relay playlists keep the newest segments, an anchored first segment, discontinuities, maps and ad cues', {timeout: 120000}, async t => {
    await withFixture(async ({execute}) => {
        for (const mode of modes) {
            const result = await execute(mode);
            t.diagnostic(JSON.stringify({mode, assertions: positive(result, result.marker, mode)}));
        }
    });
});

test('anchor, discontinuity, trimming and refusal mutations fail the fixture', {timeout: 180000}, async () => {
    await withFixture(async ({dir, original, execute}) => {
        const source = original.toString();
        const mutations = [
            ['    if anchor < 0 then state.anchor = sequence + start\n', '', 'media', 'sequence and anchor follow the first kept segment'],
            ['    for index = 0 to start\n', '    for index = 0 to start - 1\n', 'boundary', 'a discontinuity on the first kept segment is counted, not emitted'],
            ['    if total - start > maxCount then start = total - maxCount\n', '', 'media', 'window slides once it reaches the maximum'],
            ['            dateRanges.Push(line)\n', '', 'boundary', 'ad cues survive when their segments are trimmed'],
            ['        else if line.Left(13) = "#EXT-X-MEDIA:" and line.InStr("URI=") >= 0\n            return invalid\n', '', 'master', 'separate audio renditions are refused']
        ];
        for (const [before, after, mode, expected] of mutations) {
            assert.equal(source.split(before).length, 2, `one exact mutation anchor: ${expected}`);
            await fs.writeFile(path.join(dir, 'lowLatencyPlaylist.brs'), source.replace(before, after));
            const result = await execute(mode);
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_LOW_FAIL: ${result.marker} low-latency-fixture: ${expected}`), result.output);
            assert.throws(() => positive(result, result.marker, mode));
        }
        await fs.writeFile(path.join(dir, 'lowLatencyPlaylist.brs'), original);
    });
});
