'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const bsc = require('brighterscript');
const corpus = require('./fixtures/roku-demux-epoch-server/corpus');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/roku-demux-epoch-server');
const prefix = 'stitch-roku-epoch-server-';
const server = 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs';
const gate = 'source/utils/rokuDemuxInitGate.brs';
const helpers = ['rokuDemuxCommon', 'rokuDemuxProtocol', 'rokuDemuxBulk', 'rokuDemuxInitMetadata',
    'rokuDemuxInitGate', 'rokuDemuxDescriptor', 'rokuDemuxServerPolicy', 'playbackHls', 'deviceCapabilities',
    'rokuDemuxCore', 'rokuDemuxFetch', 'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol'].map(name => `source/utils/${name}.brs`);

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one exact production ${name} required`);
    return matches[0] + '\n';
}

function child(args, cwd, timeoutMs = 20000, outputLimit = 65536) {
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
    const detail = result.output.slice(-16000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    assert.doesNotMatch(result.output, /fixtureSignature|canned\.ttvnw\.net|"sourceUrl"/, 'private descriptor cannot reach output');
}

function positive(result, marker) {
    normalExit(result);
    assert.doesNotMatch(result.output, /STITCH_EPOCH_SERVER_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const summaries = lines.filter(line => line.startsWith('STITCH_EPOCH_SERVER_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_EPOCH_SERVER_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'one fresh actual execution marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions', 'cases']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    const cases = lines.filter(line => line.startsWith('STITCH_EPOCH_SERVER_CASE: '));
    assert.equal(cases.length, new Set(cases).size, 'duplicate case markers are not coverage');
    assert.equal(counts.cases, cases.length);
    for (const required of ['input-absent-default-off', 'input-owner-steady-refusal', 'init-genuine-compatible',
        'init-native-decoder-refusal', 'init-stop-during-gate', 'init-wrong-owner', 'init-alias-identity',
        'init-timescale-endpoint', 'publication-content-ad-content-assets', 'publication-no-native-proof',
        'publication-default-off', 'publication-refusal-missing', 'publication-refusal-corrupt', 'publication-refusal-stop',
        'publication-generation-mutation', 'publication-generation-rollback', 'publication-track-conflict',
        'publication-role-conflict', 'publication-pair-conflict', 'request-later-map-GET', 'request-later-map-HEAD',
        'request-active-generation-retention', 'request-grace-body-lease', 'request-unknown-asset', 'request-cleanup-stop', 'request-cleanup-failure']) {
        assert.ok(cases.includes(`STITCH_EPOCH_SERVER_CASE: ${required}`), `required actual case ${required}`);
    }
    return {...counts, elapsedMs: result.elapsedMs, outputBytes: result.bytes};
}

async function withFixture(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const originals = new Map();
    const write = async (file, bytes) => {
        await fs.mkdir(path.dirname(path.join(dir, file)), {recursive: true});
        await fs.writeFile(path.join(dir, file), bytes);
    };
    try {
        for (const file of [...helpers, server, server.replace('.brs', '.xml')]) {
            const bytes = await fs.readFile(path.join(root, file));
            originals.set(file, bytes);
            await write(file, bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, file)), bytes, 'actual production bytes copied unchanged');
        }
        await write('manifest', 'title=Offline Source Epoch Server\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\nrsg_version=1.2\nbs_const=tests=false\n');
        await write('bsconfig.json', JSON.stringify({rootDir: dir, files: ['source/**/*', 'components/**/*', 'manifest'], plugins: [],
            createPackage: false, copyToStaging: false, deploy: false, watch: false, logLevel: 'off', showDiagnosticsInConsole: false}));
        const builder = new bsc.ProgramBuilder();
        try {
            await builder.run({project: path.join(dir, 'bsconfig.json')});
            assert.deepEqual(builder.getDiagnostics().map(value => ({code: value.code, message: value.message, file: value.file?.pkgPath,
                line: value.range?.start.line})), [], 'scoped full runtime and actual Task XML compile');
        } finally {builder.program?.dispose();}
        const core = originals.get('source/utils/rokuDemuxCore.brs').toString();
        await write('core-reference.brs', ['nlCheck', 'nlInteger', 'nativeLiveClockCreate', 'nativeLiveClockAdvance'].map(name => exactFunction(core, name)).join('\n'));
        await write('hex-reference.brs', exactFunction(originals.get('source/utils/deviceCapabilities.brs').toString(), 'playbackHexValue'));
        const feed = exactFunction(originals.get('source/utils/rokuDemuxFetch.brs').toString(), 'rokuDemuxFeedInput');
        await write('feed-reference.brs', feed);
        const main = await fs.readFile(path.join(fixture, 'main.brs'), 'utf8');
        const boundary = await fs.readFile(path.join(fixture, 'boundary.brs'), 'utf8');
        for (const source of [main, boundary]) assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await write('boundary.brs', boundary);
        await write('corpus.json', JSON.stringify(corpus));
        const files = helpers.filter(file => !/(?:Core|Fetch|deviceCapabilities)\.brs$/.test(file))
            .concat(['core-reference.brs', 'hex-reference.brs', 'feed-reference.brs', server, 'boundary.brs', 'main.brs']);
        const execute = async () => {
            const marker = randomUUID();
            await write('main.brs', main.replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, ...files], dir);
            return {...result, marker};
        };
        await action({originals, feed, write, execute});
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, 'production source unchanged by fixture execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('default-off source epoch Server/gate preserve full assets, actual init approval, immutable master and lease/grace cleanup', {timeout: 30000}, async t => {
    const xml = await fs.readFile(path.join(root, server.replace('.brs', '.xml')), 'utf8');
    assert.match(xml, /<field id="enableSourceTransitions" type="boolean" value="false"\s*\/>/);
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
        t.diagnostic('actual Server/Protocol/Fetch feed/init parsers and gate; Core creation/publication/IO/native decoder boundaries explicitly mocked until integration');
    });
});

test('later-map advertising, request leases and init approval-order mutations fail with normal engine exit', {timeout: 90000}, async t => {
    await withFixture(async ({originals, feed, write, execute}) => {
        const production = originals.get(server).toString();
        const gateSource = originals.get(gate).toString();
        const mutants = [
            [server, production, 'for each asset in assets\n                if asset.id = id', 'for each asset in assets\n                if asset.id = id and (liveAssetRole(entry.publication, id) = "media" or id = entry.publication.initVideoId or id = entry.publication.initAudioId)', 'every content-ad-content init/media track is advertised'],
            [server, production, 'm.activeLease = request.assetId', 'm.activeLease = ""', 'later init request lease held after send until close'],
            ['feed-reference.brs', feed, 'if kind = "init"', 'nativeLiveFeed(state, kind, payload, nowMs)\n    if kind = "init"', 'first actual init approval precedes feed'],
            [gate, gateSource, 'nlCheck(allowed, "actual init decoder rejected")', "' removed actual native decoder approval", 'native decoder refusal occurs before changed init feed']
        ];
        for (const [file, source, before, after, failure] of mutants) {
            // Native checkout CRLF/LF differences cannot alter the exact anchor.
            const normalized = source.replaceAll('\r\n', '\n');
            assert.equal(normalized.split(before).length, 2, 'one exact production mutation anchor');
            let changed = normalized.replace(before, after);
            if (file === 'feed-reference.brs') {
                const trailingFeed = '    nativeLiveFeed(state, kind, payload, nowMs)\n    return true';
                assert.equal(changed.split(trailingFeed).length, 2, 'one original trailing feed is moved, not duplicated');
                changed = changed.replace(trailingFeed, '    return true');
            }
            await write(file, changed);
            const result = await execute();
            normalExit(result);
            assert.match(result.output, /STITCH_EPOCH_SERVER_FAIL:/, result.output);
            assert.ok(result.output.includes(`STITCH_EPOCH_SERVER_FAIL: ${result.marker} epoch-server-fixture: ${failure}`), `intended production defect must be rejected: ${failure}\n${result.output}`);
            assert.throws(() => positive(result, result.marker));
            t.diagnostic(JSON.stringify({mutation: failure, elapsedMs: result.elapsedMs}));
            await write(file, source);
        }
    });
});

test('epoch Server runner refuses stale, missing coverage, zero, duplicate, runtime and real child failures', {timeout: 15000}, async () => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        positive(result, result.marker);
        positive({...result, output: result.output.replaceAll('\r\n', '\n')}, result.marker);
        positive({...result, output: result.output.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')}, result.marker);
        for (const changed of [{output: result.output.replaceAll(result.marker, randomUUID())},
            {output: result.output.replace(/"assertions":\d+/, '"assertions":0')}, {output: result.output + result.output},
            {output: result.output.replace('STITCH_EPOCH_SERVER_CASE: init-genuine-compatible', 'IGNORED_CASE: init-genuine-compatible')},
            {output: result.output + 'STITCH_EPOCH_SERVER_FAIL: false pass\n'}, {output: result.output + 'BRIGHTSCRIPT: ERROR: false pass\n'},
            {output: result.output + 'EXIT_BRIGHTSCRIPT_CRASH\n'}, {code: 7}, {signal: 'SIGTERM'}, {startupError: 'spawn failed'}]) {
            assert.throws(() => positive({...result, ...changed}, result.marker));
        }
        const timed = await child(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
        assert.equal(timed.timedOut, true); assert.throws(() => positive(timed, result.marker));
        const over = await child(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
        assert.equal(over.exceeded, true); assert.throws(() => positive(over, result.marker));
        const nonzero = await child(['-e', 'process.stdout.write("not a valid summary"); process.exitCode=7;'], os.tmpdir(), 2000, 1024);
        assert.equal(nonzero.code, 7); assert.throws(() => positive(nonzero, result.marker));
    });
});
