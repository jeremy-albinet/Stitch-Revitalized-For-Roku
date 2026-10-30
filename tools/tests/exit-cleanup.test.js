'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/exit-cleanup');
const prefix = 'stitch-exit-cleanup-';
const tracked = ['source/main.brs', 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs',
    'components/Modules/RokuDemuxSession/RokuDemuxSession.xml', 'source/utils/taskFactory.brs',
    'source/utils/rokuDemuxDescriptor.brs', 'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs',
    'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs'];

async function snapshots() {
    return Promise.all(tracked.map(async file => [file,
        createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

function run(zip, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
            { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => {
            clearTimeout(timer);
            resolve({ code, output, timedOut, exceeded, startupError });
        });
    });
}

function normal(result) {
    const detail = result.output.slice(-22000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|unhandled exception|Syntax Error/i, detail);
    return detail;
}

function positive(result, marker) {
    const detail = normal(result);
    assert.doesNotMatch(result.output, /EXIT_CLEANUP_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith(`${marker}:`));
    assert.equal(lines.length, 1, `expected one fresh exit cleanup summary\n${detail}`);
    const count = lines[0].match(/:\s*(\d+) assertions, 8 cases$/);
    assert.ok(count && Number(count[1]) >= 100, detail);
    return Number(count[1]);
}

test('Main keeps render alive for bounded actual session cleanup without forced worker stop', { timeout: 100000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const packageDir = path.join(dir, 'package');
    const marker = `STITCH_EXIT_CLEANUP_PASS:${randomUUID()}`;
    const before = await snapshots();
    async function add(file, data) {
        const destination = path.join(packageDir, file);
        await fs.mkdir(path.dirname(destination), { recursive: true });
        await fs.writeFile(destination, data);
    }
    try {
        const mainSource = await fs.readFile(path.join(root, 'source/main.brs'), 'utf8');
        const parser = bsc.Parser.parse(mainSource, { mode: bsc.ParseMode.BrightScript });
        assert.deepEqual(parser.diagnostics, []);
        assert.match(mainSource, /    finishMainScene\(screen, m\.scene, m\.port, screenClosed\)\r?\n    m\.scene = invalid\r?\nend sub/);
        const helpers = [...mainSource.matchAll(/^sub finishMainScene\([^]*?^end sub\r?$/gm)];
        assert.equal(helpers.length, 1, 'execute exactly one complete actual Main helper');
        const actualHelper = helpers[0][0];
        const clockFactory = 'clock = CreateObject("roTimeSpan")';
        const portWait = 'msg = wait(timeout, port)';
        assert.equal(actualHelper.split(clockFactory).length, 2);
        assert.equal(actualHelper.split(portWait).length, 2);
        const boundedHelper = actualHelper.replace(clockFactory, 'clock = exitFixtureClock()')
            .replace(portWait, 'msg = exitFixtureWait(timeout, port)');
        assert.equal(boundedHelper.replace('clock = exitFixtureClock()', clockFactory)
            .replace('msg = exitFixtureWait(timeout, port)', portWait), actualHelper,
        'only explicit clock and wait IO boundaries may change production helper bytes');
        for (const file of tracked.slice(3)) await add(file, await fs.readFile(path.join(root, file)));
        const managerPath = tracked[1];
        const managerSource = await fs.readFile(path.join(root, managerPath), 'utf8');
        const workerFactory = 'CreateObject("roSGNode", "RokuDemuxServer")';
        assert.equal(managerSource.split(workerFactory).length, 2);
        const managerBoundary = managerSource.replace(workerFactory, 'CreateObject("roSGNode", "ExitWorkerBoundary")');
        assert.equal(managerBoundary.replace('CreateObject("roSGNode", "ExitWorkerBoundary")', workerFactory), managerSource,
            'only the native worker creation IO boundary may change manager bytes');
        await add(managerPath, managerBoundary);
        const managerXml = await fs.readFile(path.join(root, tracked[2]), 'utf8');
        await add(tracked[2], managerXml.replace('</interface>', '<function name="fixtureOwner" /></interface>')
            .replace('</component>', '<script uri="SessionProbe.brs" /></component>'));
        await add('components/Modules/RokuDemuxSession/SessionProbe.brs', await fs.readFile(path.join(fixtures, 'SessionProbe.brs')));
        for (const file of ['ExitHost.xml', 'ExitVideoBoundary.xml', 'ExitWorkerBoundary.xml', 'ExitWorkerBoundary.brs']) {
            await add(`components/${file}`, await fs.readFile(path.join(fixtures, file)));
        }
        // These unused taskFactory constructors need declarations for scoped compilation.
        for (const name of ['TwitchApiTask', 'GetTwitchContent']) {
            await add(`components/${name}.xml`, `<component name="${name}" extends="Group" />`);
        }
        await add('manifest', 'title=Offline Main Exit Cleanup\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add('bsconfig.json', JSON.stringify({ rootDir: packageDir,
            files: ['source/**/*', 'components/**/*', 'manifest'], createPackage: false,
            copyToStaging: false, deploy: false, watch: false, logLevel: 'off', showDiagnosticsInConsole: false }));
        const fixture = await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8');
        const deadline = /        remaining = 15000 - clock\.TotalMilliseconds\(\)\r?\n        if remaining <= 0 then exit while\r?\n        timeout = 100\r?\n        if remaining < timeout then timeout = remaining/;
        const drain = /    while session <> invalid[^]*?    end while/;
        assert.equal(boundedHelper.match(deadline)?.length, 1);
        assert.equal(boundedHelper.match(drain)?.length, 1);
        for (const mode of ['positive', 'assertion', 'early-close', 'missing-deadline']) {
            let helper = boundedHelper;
            if (mode === 'early-close') helper = helper.replace(drain, '');
            if (mode === 'missing-deadline') helper = helper.replace(deadline, '        timeout = 100');
            if (mode !== 'positive' && mode !== 'assertion') assert.notEqual(helper, boundedHelper);
            await add('source/exitHelper.brs', helper);
            await add('source/main.brs', fixture.replace('__PASS_MARKER__', marker)
                .replace('__NEGATIVE_CONTROL__', mode === 'assertion' ? 'yes' : 'no'));
            if (mode === 'positive') {
                const builder = new bsc.ProgramBuilder();
                try {
                    await builder.run({ project: path.join(packageDir, 'bsconfig.json') });
                    assert.deepEqual(builder.getDiagnostics().map(diagnostic => ({
                        code: diagnostic.code, message: diagnostic.message, file: diagnostic.file?.pkgPath,
                    })), [], 'actual helper/session package compiles without suppressed diagnostics');
                } finally { builder.program?.dispose(); }
            }
            const zip = path.join(dir, `${mode}.zip`);
            await zipFolder(packageDir, zip);
            const result = await run(zip, dir);
            if (mode === 'positive') {
                t.diagnostic(`${positive(result, marker)} assertions across 8 Main exit cases; actual session handlers, controlled IO`);
                assert.throws(() => positive(result, 'STALE_MARKER'), /expected one fresh exit cleanup summary/);
            } else {
                normal(result);
                const expected = mode === 'assertion' ? 'deliberate assertion control'
                    : mode === 'early-close' ? 'screen cannot close before cooperative acknowledgment or deadline'
                    : 'Main drain exceeded bounded deadline';
                assert.ok(result.output.includes(`EXIT_CLEANUP_FAIL: ${expected}`), result.output.slice(-22000));
                assert.doesNotMatch(result.output, new RegExp(marker));
                assert.throws(() => positive(result, marker), /EXIT_CLEANUP_FAIL:/);
                t.diagnostic(`${mode}: real fixture assertion rejects the control despite normal engine exit`);
            }
        }
        assert.deepEqual(await snapshots(), before, 'all actual production source files remain unchanged during fixture execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolved), { code: 'ENOENT' });
    }
});
