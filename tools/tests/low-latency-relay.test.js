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
const relayPath = path.join(root, 'components/Tasks/LowLatencyRelay/LowLatencyRelay.brs');
const helpers = ['source/utils/lowLatencyPlaylist.brs', 'source/utils/rokuDemuxCommon.brs'];
const fixturePath = path.join(__dirname, 'fixtures/low-latency-relay/main.brs');
const prefix = 'stitch-low-latency-relay-';
const modes = ['listen', 'budget'];

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
    assert.doesNotMatch(result.output, /STITCH_RELAY_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_RELAY_CASE: ')), [`STITCH_RELAY_CASE: ${mode}`]);
    const summaries = lines.filter(line => line.startsWith('STITCH_RELAY_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_RELAY_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'fresh relay marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    return counts.assertions;
}

// Only native socket creation and the upstream fetch are replaced.
function boundaries(source) {
    for (const native of ['CreateObject("roSocketAddress")', 'CreateObject("roStreamSocket")']) {
        assert.equal(source.split(native).length, 2, `one actual ${native}`);
    }
    const fetch = /^function relayFetch\(url as string\) as dynamic$[^]*?^end function$/m;
    assert.equal((source.match(new RegExp(fetch.source, 'gm')) || []).length, 1, 'one actual relayFetch');
    return source.replace('CreateObject("roSocketAddress")', 'fakeAddress()')
        .replace('CreateObject("roStreamSocket")', 'fakeListener()')
        .replace(fetch, 'function relayFetch(url as string) as dynamic\n    return m.upstream\nend function');
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const original = (await fs.readFile(relayPath)).toString();
    try {
        assert.deepEqual(bsc.Parser.parse(original, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        const harness = await fs.readFile(fixturePath, 'utf8');
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        for (const file of helpers) await fs.writeFile(path.join(dir, path.basename(file)), await fs.readFile(path.join(root, file)));
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Low Latency Relay Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const install = async source => fs.writeFile(path.join(dir, 'LowLatencyRelay.brs'), boundaries(source));
        await install(original);
        const execute = async mode => {
            const marker = randomUUID();
            await fs.writeFile(path.join(dir, 'main.brs'), harness.replaceAll('__MODE__', mode).replaceAll('__MARKER__', marker));
            const files = [...helpers.map(file => path.basename(file)), 'LowLatencyRelay.brs', 'main.brs'];
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, ...files], dir);
            return {...result, marker};
        };
        await action({original, install, execute});
        assert.equal((await fs.readFile(relayPath)).toString(), original, 'source unchanged after execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('relay publishes only an exact loopback bind and budgets failed refreshes per path', {timeout: 120000}, async t => {
    await withFixture(async ({execute}) => {
        for (const mode of modes) {
            const result = await execute(mode);
            t.diagnostic(JSON.stringify({mode, assertions: positive(result, result.marker, mode)}));
        }
    });
});

test('loopback, per-path budget and end-of-stream mutations fail the fixture', {timeout: 180000}, async () => {
    await withFixture(async ({original, install, execute}) => {
        const mutations = [
            [' and relayOnLoopback(listener.GetAddress(), listenPort)', '', 'listen', 'a bind the OS does not report on exact loopback is skipped'],
            ['        m.failures[path] = 0\n', '        m.failures = {}\n', 'budget', 'a healthy variant does not refresh a failing one\'s budget'],
            ['        if text.InStr("#EXT-X-ENDLIST") >= 0 then m.top.ended = true\n', '', 'budget', 'an upstream end of stream is reported']
        ];
        for (const [before, after, mode, expected] of mutations) {
            assert.equal(original.split(before).length, 2, `one exact mutation anchor: ${expected}`);
            await install(original.replace(before, after));
            const result = await execute(mode);
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_RELAY_FAIL: ${result.marker} low-latency-relay: ${expected}`), result.output);
            assert.throws(() => positive(result, result.marker, mode));
        }
        await install(original);
    });
});
