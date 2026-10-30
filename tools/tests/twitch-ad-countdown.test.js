'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');
const corpus = require('./fixtures/twitch-ad-countdown/corpus');
const root = path.resolve(__dirname, '../..');
const sourcePath = path.join(root, 'source/utils/twitchAdCountdown.brs');
const fixturePath = path.join(__dirname, 'fixtures/twitch-ad-countdown/main.brs');
const prefix = 'stitch-ad-countdown-';

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
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}

function positive(result, marker, mode) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_AD_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_AD_CASE: ')), [`STITCH_AD_CASE: ${mode}`]);
    const summaries = lines.filter(line => line.startsWith('STITCH_AD_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_AD_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'fresh actual helper marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions', 'failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    const cues = lines.filter(line => line.startsWith('STITCH_AD_CUES: '));
    assert.equal(cues.length, mode === 'parser' ? 1 : 0);
    if (mode === 'parser') assert.deepEqual(JSON.parse(cues[0].slice('STITCH_AD_CUES: '.length)), corpus.golden, 'all sanitized cue fields equal independent UTC/microsecond goldens');
    return {assertions: counts.assertions, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const original = await fs.readFile(sourcePath);
    try {
        assert.deepEqual(bsc.Parser.parse(original.toString(), {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await fs.writeFile(path.join(dir, 'twitchAdCountdown.brs'), original);
        assert.deepEqual(await fs.readFile(path.join(dir, 'twitchAdCountdown.brs')), original);
        const harness = await fs.readFile(fixturePath, 'utf8');
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await fs.writeFile(path.join(dir, 'corpus.json'), JSON.stringify(corpus));
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Pure Ad Countdown Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const execute = async mode => {
            const marker = randomUUID();
            await fs.writeFile(path.join(dir, 'main.brs'), harness.replaceAll('__MODE__', mode).replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, 'twitchAdCountdown.brs', 'main.brs'], dir);
            return {...result, marker};
        };
        await action({dir, original, execute});
        assert.deepEqual(await fs.readFile(sourcePath), original, 'actual owned source unchanged after execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('actual ad parser/view/clock keep exact fractional cues, privacy, bounded refusals and presented-time ownership', {timeout: 100000}, async t => {
    await withFixture(async ({execute}) => {
        for (const mode of ['parser', 'view', 'clock']) {
            const result = await execute(mode);
            t.diagnostic(JSON.stringify({mode, ...positive(result, result.marker, mode)}));
        }
        t.diagnostic('synthetic helper evidence only; native Twitch metadata delivery, usable UTC clock and corner badge remain pending');
    });
});

test('duration, ordinal, epoch, end, overlap and class mutations fail actual native assertions normally', {timeout: 195000}, async t => {
    await withFixture(async ({dir, original, execute}) => {
        const source = original.toString();
        const mutations = [
            ['value = whole * 1000000& + fraction', 'value = whole * 1000000& + fraction + 1000000&', 'parser', 'exact observed fractional ad duration'],
            ['number = selected.podPosition + 1', 'number = selected.podPosition', 'view', 'per-ad ceiling and one-based valid ordinal'],
            ['if positionInfo.epoch <> 1 or not tadNumber(positionInfo.video)', 'if not tadNumber(positionInfo.video)', 'clock', 'relative clock cannot masquerade as UTC'],
            ['presentedUtcUs < cue.endUs', 'presentedUtcUs <= cue.endUs', 'view', 'half-open end hides exactly at ad finish'],
            ['if overlap > 1000& or cue.podCount = 0& or cue.podCount <> prior.podCount or cue.podPosition <> prior.podPosition + 1&', 'if false', 'parser', 'ambiguous overlap refusal excess overlap'],
            ['if attributes["CLASS"] <> "twitch-stitched-ad" then return invalid', 'if false then return invalid', 'parser', 'unknown metadata class never creates ad']
        ];
        for (const [before, after, mode, expected] of mutations) {
            assert.equal(source.split(before).length, 2, 'one exact actual source mutation anchor');
            await fs.writeFile(path.join(dir, 'twitchAdCountdown.brs'), source.replace(before, after));
            const result = await execute(mode);
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_AD_FAIL: ${result.marker} ad-countdown-fixture: ${expected}`), result.output);
            assert.throws(() => positive(result, result.marker, mode));
            t.diagnostic(JSON.stringify({mutation: expected, elapsedMs: result.elapsedMs}));
        }
    });
});

test('ad runner rejects stale, zero, duplicate, runtime, incorrect golden and real transport failures', {timeout: 15000}, async () => {
    const marker = randomUUID();
    const output = `STITCH_AD_CASE: clock\nSTITCH_AD_PASS: ${marker} {"assertions":1,"failures":0}\n`;
    const base = {code: 0, output, bytes: output.length, timedOut: false, exceeded: false, startupError: undefined};
    positive(base, marker, 'clock');
    for (const changed of [{output: output.replace(marker, randomUUID())}, {output: output.replace('"assertions":1', '"assertions":0')},
        {output: output.replace('"failures":0', '"failures":1')}, {output: output + output},
        {output: output.replace('CASE: clock', 'CASE: view')}, {output: output + 'STITCH_AD_FAIL: false pass\n'},
        {output: output + 'BRIGHTSCRIPT: ERROR: false pass\n'}, {output: output + 'BrightScript Debugger'},
        {code: 7}, {startupError: 'spawn failed'}]) assert.throws(() => positive({...base, ...changed}, marker, 'clock'));
    const goldenOutput = `STITCH_AD_CUES: ${JSON.stringify(corpus.golden)}\nSTITCH_AD_CASE: parser\nSTITCH_AD_PASS: ${marker} {"assertions":1,"failures":0}\n`;
    positive({...base, output: goldenOutput}, marker, 'parser');
    assert.throws(() => positive({...base, output: goldenOutput.replace('30239000', '30239001')}, marker, 'parser'));
    const timed = await child(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timed.timedOut, true);
    assert.throws(() => positive(timed, marker, 'clock'));
    const over = await child(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(over.exceeded, true);
    assert.throws(() => positive(over, marker, 'clock'));
    const nonzero = await child(['-e', `process.stdout.write(${JSON.stringify(output)}); process.exitCode=7;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 7);
    assert.throws(() => positive(nonzero, marker, 'clock'));
});
