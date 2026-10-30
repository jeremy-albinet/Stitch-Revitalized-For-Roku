'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');
const {zipFolder} = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtureDir = path.join(__dirname, 'fixtures/ad-countdown-ui');
const prefix = 'stitch-ad-countdown-ui-';
const componentPath = 'components/Modules/AdCountdown/AdCountdown.brs';
const helperPath = 'source/utils/twitchAdCountdown.brs';

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
        processChild.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({code, signal, output, bytes, timedOut, exceeded, startupError, elapsedMs: Math.round(performance.now() - started)});
        });
    });
}

function normalExit(result) {
    const detail = result.output.slice(-12000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception|failed to set up component/i, detail);
    assert.match(result.output, /EXIT_USER_NAV/, `SceneGraph screen must close normally\n${detail}`);
}

function positive(result, marker) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_AD_UI_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_AD_UI_BEGIN: ')), [`STITCH_AD_UI_BEGIN: ${marker}`]);
    const summaries = lines.filter(line => line.startsWith('STITCH_AD_UI_END: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_AD_UI_END: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'fresh actual SceneGraph fixture marker required');
    assert.ok(lines.indexOf(`STITCH_AD_UI_BEGIN: ${marker}`) < lines.indexOf(summaries[0]), 'fresh markers must be ordered');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions', 'failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    return {assertions: counts.assertions, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}

async function write(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), {recursive: true});
    await fs.writeFile(dest, data);
}

async function withFixture(action) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const component = await fs.readFile(path.join(root, componentPath));
    const helper = await fs.readFile(path.join(root, helperPath));
    const main = await fs.readFile(path.join(fixtureDir, 'main.brs'), 'utf8');
    try {
        for (const source of [component.toString(), helper.toString(), main]) {
            assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        }
        const packageDir = path.join(temp, 'package');
        for (const file of ['components/Modules/AdCountdown/AdCountdown.xml', componentPath, helperPath,
            'fonts/Archivo-Regular.otf', 'images/twitch-redesign/round6.9.png']) {
            const bytes = await fs.readFile(path.join(root, file));
            await write(packageDir, file, bytes);
            assert.deepEqual(await fs.readFile(path.join(packageDir, file)), bytes, 'production file copied byte-for-byte');
        }
        await write(packageDir, 'manifest', 'title=Ad Corner Badge Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await write(packageDir, 'components/AdCountdownFixture.xml', await fs.readFile(path.join(fixtureDir, 'AdCountdownFixture.xml')));
        const execute = async (source = component.toString()) => {
            const marker = randomUUID();
            await write(packageDir, componentPath, source);
            await write(packageDir, 'source/main.brs', main.replaceAll('__MARKER__', marker));
            const zip = path.join(temp, 'fixture.zip');
            await zipFolder(packageDir, zip);
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], temp);
            return {...result, marker};
        };
        await action({component: component.toString(), execute});
        assert.deepEqual(await fs.readFile(path.join(root, componentPath)), component, 'actual UI source unchanged by fixtures');
        assert.deepEqual(await fs.readFile(path.join(root, helperPath)), helper, 'released pure helper stays unchanged');
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('real ad badge Label/Group updates preserve presented-time ceil, ownership, pause, disposal and safe localized geometry', {timeout: 40000}, async t => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
        t.diagnostic('SceneGraph component evidence only; provider ad delivery, native UTC mapping, TV pixels and attachment are not tested');
    });
});

test('actual UI countdown mutation is rejected despite normal engine exit', {timeout: 40000}, async t => {
    await withFixture(async ({component, execute}) => {
        const before = 'seconds = view.remainingSeconds - minutes * 60';
        assert.equal(component.split(before).length, 2, 'one exact source mutation anchor');
        const result = await execute(component.replace(before, `${before} + 1`));
        normalExit(result);
        assert.ok(result.output.includes(`STITCH_AD_UI_FAIL: ${result.marker} fractional first duration rounds upward`), result.output);
        assert.throws(() => positive(result, result.marker));
        t.diagnostic(JSON.stringify({mutation: 'one-second wrong rendered countdown', elapsedMs: result.elapsedMs, outputBytes: result.bytes}));
    });
});

test('ad UI runner rejects stale, empty, duplicate, runtime and real child failures', {timeout: 15000}, async () => {
    const marker = randomUUID();
    const output = `STITCH_AD_UI_BEGIN: ${marker}\nSTITCH_AD_UI_END: ${marker} {"assertions":1,"failures":0}\nEXIT_USER_NAV\n`;
    const base = {code: 0, signal: null, output, bytes: output.length, timedOut: false, exceeded: false, startupError: undefined};
    positive(base, marker);
    positive({...base, output: output.replaceAll('\n', '\r\n')}, marker);
    for (const changed of [{output: output.replaceAll(marker, randomUUID())}, {output: output.replace('"assertions":1', '"assertions":0')},
        {output: output.replace('"failures":0', '"failures":1')}, {output: output + output},
        {output: output.replace(`STITCH_AD_UI_BEGIN: ${marker}\n`, '')}, {output: output.replace('EXIT_USER_NAV', '')},
        {output: `STITCH_AD_UI_END: ${marker} {"assertions":1,"failures":0}\nSTITCH_AD_UI_BEGIN: ${marker}\nEXIT_USER_NAV\n`},
        {output: output + 'STITCH_AD_UI_FAIL: false pass\n'}, {output: output + 'BRIGHTSCRIPT: ERROR: false pass\n'},
        {output: output + 'EXIT_BRIGHTSCRIPT_CRASH\n'},
        {output: output + 'BrightScript Debugger'}, {output: output.replace('"assertions":1', '"assertions":0.5')},
        {code: 7}, {signal: 'SIGTERM'}, {startupError: 'spawn failed'}]) assert.throws(() => positive({...base, ...changed}, marker));
    const timed = await child(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timed.timedOut, true);
    assert.throws(() => positive(timed, marker));
    const over = await child(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(over.exceeded, true);
    assert.throws(() => positive(over, marker));
    const nonzero = await child(['-e', `process.stdout.write(${JSON.stringify(output)}); process.exitCode=7;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 7);
    assert.throws(() => positive(nonzero, marker));
});
