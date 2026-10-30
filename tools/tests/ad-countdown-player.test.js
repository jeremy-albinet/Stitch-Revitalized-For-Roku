'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const {zipFolder} = require('roku-deploy');
const bsc = require('brighterscript');
const root = path.resolve(__dirname, '../..');
const fixtureDir = path.join(__dirname, 'fixtures/ad-countdown-player');
const prefix = 'stitch-ad-countdown-player-';
const ownFiles = ['source/utils/twitchAdClock.brs', 'components/Modules/AdMetadataOwner/AdMetadataOwner.brs'];

async function write(dir, file, bytes) {
    const target = path.join(dir, file);
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.writeFile(target, bytes);
}
async function copy(dir, file) {await write(dir, file, await fs.readFile(path.join(root, file)));}
async function tree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), {withFileTypes: true})) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await tree(dir, file); else await copy(dir, file);
    }
}
async function component(dir, name, probe) {
    const folder = `components/Modules/${name}`;
    let xml = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)].map(m => `<function name="${m[1]}" />`).join('');
    assert.ok(exports);
    xml = xml.replace('</interface>', `${exports}</interface>`).replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
    await write(dir, `${folder}/${name}.xml`, xml);
    await copy(dir, `${folder}/${name}.brs`);
    await write(dir, `components/${name}Fixture.brs`, probe);
}

async function build(dir, marker, mutation) {
    await write(dir, 'manifest', 'title=Ad Countdown Integration Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/uiContrast.brs', 'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs']) await copy(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster', 'components/Modules/AdCountdown', 'components/Modules/EmojiLabel']) await tree(dir, folder);
    // Explicit engine boundary: the Unicode regex source cannot run in brs-engine.
    // Actual EmojiLabel handlers are copied unchanged; no ad text contains emoji.
    await write(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(root, 'tools/tests/fixtures/ui-phase2-player/EmojiLabelRegex.brs')));
    // Explicit registry boundary; no device storage/network/decoder is accessed.
    await write(dir, 'source/utils/config.brs', await fs.readFile(path.join(root, 'tools/tests/fixtures/ui-phase2-player/config.brs')));
    const probe = await fs.readFile(path.join(fixtureDir, 'probe.brs'), 'utf8');
    const wrapperProbe = probe.slice(0, probe.indexOf('function fixtureAdOwnerRead')) + '\n' + await fs.readFile(path.join(fixtureDir, 'retention-probe.brs'), 'utf8');
    const ownerProbe = probe.slice(probe.indexOf('function fixtureAdOwnerRead'));
    for (const name of ['StitchVideo', 'CustomVideo']) await component(dir, name, wrapperProbe);
    await component(dir, 'AdMetadataOwner', ownerProbe);
    // The only worker replacement is unavailable network IO: real Task lifecycle,
    // typed stop, response/state observers, owner handlers and badge run normally.
    for (const file of ['TwitchAdMetadata.xml', 'TwitchAdMetadata.brs', 'AdClockHost.xml']) await write(dir, `components/${file}`, await fs.readFile(path.join(fixtureDir, file)));
    await write(dir, 'source/main.brs', (await fs.readFile(path.join(fixtureDir, 'main.brs'), 'utf8')).replaceAll('__MARKER__', marker).replaceAll('__RETENTION_ONLY__', mutation?.retentionOnly ? 'true' : 'false'));
    if (mutation) {
        const actual = await fs.readFile(path.join(dir, mutation.file), 'utf8');
        assert.equal(actual.split(mutation.before).length, 2, 'unique actual production guard');
        await write(dir, mutation.file, actual.replace(mutation.before, mutation.after));
    }
}

function run(zip, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
            {cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const start = performance.now();
        const timer = setTimeout(() => {timedOut = true; child.kill();}, 30000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 65536) {exceeded = true; child.kill(); return;}
            output += data.toString();
        };
        child.stdout.on('data', collect); child.stderr.on('data', collect);
        child.once('error', error => {startupError = error.name;});
        child.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({output, bytes, timedOut, exceeded, startupError, code, signal, elapsedMs: Math.round(performance.now() - start)});
        });
    });
}
function normal(result) {
    const detail = result.output.slice(-10000);
    assert.equal(result.timedOut, false, detail); assert.equal(result.exceeded, false, detail);
    assert.equal(result.startupError, undefined, detail); assert.equal(result.code, 0, detail); assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception|failed to set up component/i, detail);
}
function accepted(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /STITCH_AD_PLAYER_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const start = `STITCH_AD_PLAYER_BEGIN: ${marker}`;
    const endPrefix = `STITCH_AD_PLAYER_END: ${marker} `;
    assert.deepEqual(lines.filter(l => l.startsWith('STITCH_AD_PLAYER_BEGIN: ')), [start]);
    const ends = lines.filter(l => l.startsWith('STITCH_AD_PLAYER_END: '));
    assert.equal(ends.length, 1); assert.ok(ends[0].startsWith(endPrefix));
    assert.ok(lines.indexOf(start) < lines.indexOf(ends[0]));
    const count = JSON.parse(ends[0].slice(endPrefix.length));
    assert.deepEqual(Object.keys(count).sort(), ['assertions', 'failures']);
    assert.ok(Number.isSafeInteger(count.assertions) && count.assertions > 0);
    assert.equal(count.failures, 0);
    return {assertions: count.assertions, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}
async function execute(mutation) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = randomUUID();
    const baseline = new Map(await Promise.all(ownFiles.map(async file => [file, await fs.readFile(path.join(root, file))])));
    try {
        await build(dir, marker, mutation);
        const zip = path.join(dir, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await run(zip, dir);
        for (const [file, bytes] of baseline) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes);
        return {...result, marker};
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive: true, force: true});
    }
}

test('actual retained owner, both player wrappers and badge use only presented native frame timing', {timeout: 40000}, async t => {
    const result = await execute();
    t.diagnostic(JSON.stringify(accepted(result, result.marker)));
});
test('actual stale-owner and closed-before-stopped guard removals are rejected', {timeout: 75000}, async t => {
    for (const mutation of [
        {file: 'source/utils/twitchAdClock.brs', before: 'if m.disposed or m.adBadge = invalid or owner <> m.adOwner or owner = "" then return false', after: 'if m.disposed or m.adBadge = invalid or owner = "" then return false'},
        {file: 'components/Modules/AdMetadataOwner/AdMetadataOwner.brs', before: 'if m.worker.state = "stop" then releaseAdWorker()', after: 'releaseAdWorker()'}
    ]) {
        const result = await execute(mutation);
        // The second invalid mutant force-stops a pending native owner; the real
        // handler assertions must reject it even when the engine exits normally.
        normal(result);
        assert.throws(() => accepted(result, result.marker));
        assert.match(result.output, /STITCH_AD_PLAYER_FAIL:/);
        t.diagnostic(JSON.stringify({guard: mutation.before, rejected: true, normalExit: true, elapsedMs: result.elapsedMs}));
    }
});
test('actual latest-only, cross-publication overlap and retention-cap mutations are rejected', {timeout: 75000}, async t => {
    for (const mutation of [
        {before: 'retainedBounds = twitchAdClockRetain(m.adBounds, bounds, false)', after: 'retainedBounds = bounds'},
        {before: 'if not ((lastOld and fromOld) or (lastNew and fromNew)) then return invalid', after: 'if false then return invalid'},
        {before: 'if result.Count() = cap then result.Shift()', after: 'if false then result.Shift()'}
    ]) {
        const result = await execute({...mutation, file: 'source/utils/twitchAdClock.brs', retentionOnly: true});
        normal(result);
        assert.match(result.output, /STITCH_AD_PLAYER_FAIL:/);
        assert.throws(() => accepted(result, result.marker));
        t.diagnostic(JSON.stringify({guard: mutation.before, rejected: true, normalExit: true, elapsedMs: result.elapsedMs}));
    }
});
test('bounded real-child output validator accepts LF/CRLF and refuses stale, zero, failure and crash', () => {
    const marker = 'output-control';
    const output = `STITCH_AD_PLAYER_BEGIN: ${marker}\nSTITCH_AD_PLAYER_END: ${marker} {"assertions":1,"failures":0}\n`;
    const r = {output, bytes: output.length, timedOut: false, exceeded: false, code: 0, signal: null};
    accepted(r, marker); accepted({...r, output: output.replaceAll('\n', '\r\n')}, marker);
    for (const bad of [{...r, timedOut: true}, {...r, exceeded: true}, {...r, code: 1}, {...r, signal: 'SIGTERM'}, {...r, startupError: 'Error'},
        {...r, output: output.replace('"assertions":1', '"assertions":0')}, {...r, output: output.replace('"failures":0', '"failures":1')},
        {...r, output: output.replaceAll(marker, 'stale')}, {...r, output: output + output}, {...r, output: output.trim().split('\n').reverse().join('\n')},
        {...r, output: output + 'BRIGHTSCRIPT: ERROR: crash\n'}]) assert.throws(() => accepted(bad, marker));
});
