'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const bsc = require('brighterscript');
const {createHash} = require('node:crypto');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/ad-mixed-epoch-integration');
const prefix = 'stitch-ad-mixed-epoch-integration-';
const server = 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs';
const gate = 'source/utils/rokuDemuxInitGate.brs';
const fetch = 'source/utils/rokuDemuxFetch.brs';
const helpers = ['rokuDemuxCommon', 'rokuDemuxProtocol', 'rokuDemuxBulk', 'rokuDemuxInitMetadata',
    'rokuDemuxInitGate', 'rokuDemuxDescriptor', 'rokuDemuxServerPolicy', 'playbackHls', 'deviceCapabilities',
    'rokuDemuxCore', 'rokuDemuxFetch', 'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol'].map(name => `source/utils/${name}.brs`);

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one exact production ${name} required`);
    return matches[0] + '\n';
}

function child(args, cwd, timeoutMs = 40000, outputLimit = 65536) {
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
    assert.doesNotMatch(result.output, /STITCH_AD_EPOCH_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const summaries = lines.filter(line => line.startsWith('STITCH_AD_EPOCH_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_AD_EPOCH_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'one fresh actual execution marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['admissions', 'assertions', 'cases', 'goldens', 'manifests', 'pairs']);
    for (const value of Object.values(counts)) assert.ok(Number.isSafeInteger(value) && value > 0);
    const cases = lines.filter(line => line.startsWith('STITCH_EPOCH_INTEGRATION_CASE: '));
    assert.deepEqual(cases, ['mixed-source-local-PDT-cue-http-and-leases', 'same-map-timestamp-reset-keeps-exact-anchors',
        'ambiguous-UTC-is-optional-canonical-fallback'].map(name => 'STITCH_EPOCH_INTEGRATION_CASE: ' + name));
    assert.equal(counts.cases, cases.length);
    assert.equal(counts.manifests, 8);
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
        await write('hex-reference.brs', ['playbackHexValue','twitchVariantVideoFormat'].map(name => exactFunction(originals.get('source/utils/deviceCapabilities.brs').toString(),name)).join('\n'));
        const main = await fs.readFile(path.join(fixture, 'main.brs'), 'utf8');
        const support = await fs.readFile(path.join(fixture, 'support.brs'), 'utf8');
        const boundary = await fs.readFile(path.join(fixture, 'boundary.brs'), 'utf8');
        for (const source of [main, boundary, support]) assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await write('boundary.brs', boundary);
        await write('support.brs', support);
        // Substitute only completed-file/event primitives, leaving every
        // framing, owner, feed, initialization and metadata decision intact.
        let runtimeFetch = originals.get(fetch).toString();
        for (const [before, after] of [
            ['Type(event) <> "roUrlEvent"', 'adEventType(event) <> "roUrlEvent"'],
            ['payload = ReadAsciiFile(nlInputPath())', 'payload = adRead(nlInputPath())']
        ]) {
            assert.equal(runtimeFetch.split(before).length, 2, 'one exact native IO boundary');
            runtimeFetch = runtimeFetch.replace(before, after);
        }
        assert.ok(runtimeFetch.includes('CreateObject("roFileSystem")'));
        runtimeFetch = runtimeFetch.replaceAll('CreateObject("roFileSystem")', 'adFileSystem()');
        assert.deepEqual(bsc.Parser.parse(runtimeFetch, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await write(fetch, runtimeFetch);
        const corpusBytes = await fs.readFile(path.join(fixture, 'corpus.json'));
        const corpus = JSON.parse(corpusBytes);
        const provenance = JSON.parse(await fs.readFile(path.join(fixture, 'provenance.json')));
        assert.equal(createHash('sha256').update(corpusBytes).digest('hex'), provenance.corpusSha256);
        assert.equal(provenance.synthetic, true);
        assert.equal(provenance.actualDecoderApproval, false);
        assert.equal(provenance.runtimePythonRequired, false);
        for (const record of [...Object.values(corpus.inits), ...corpus.media, corpus.ptsMedia]) {
            for (const key of ['input', 'video', 'audio']) {
                const bytes = Buffer.from(record[key].hex, 'hex');
                assert.equal(bytes.length, record[key].count);
                assert.equal(createHash('sha256').update(bytes).digest('hex'), record[key].sha256);
            }
        }
        assert.notEqual(corpus.inits.content.videoTrackId, corpus.inits.ad.videoTrackId);
        assert.notEqual(corpus.inits.content.audioTimescale, corpus.inits.ad.audioTimescale);
        await write('corpus.json', corpusBytes);
        const files = helpers.filter(file => !/deviceCapabilities\.brs$/.test(file))
            .concat(['hex-reference.brs', server, 'boundary.brs', 'support.brs', 'main.brs']);
        const execute = async () => {
            const marker = randomUUID();
            await write('main.brs', main.replaceAll('__MARKER__', marker));
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir, ...files], dir);
            return {...result, marker};
        };
        await action({originals, write, execute});
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, 'production source unchanged by fixture execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, {recursive: true, force: true});
    }
}

test('actual completed Fetch/Core/gate/Server preserves PDT and cues across source epochs', {timeout: 60000}, async t => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
        t.diagnostic('actual media/timing decisions; only native completed-file/socket/decoder primitives substituted; no hardware claim');
    });
});

test('mixed timing scalar-regression/seal/UTC mutations are rejected at normal exit', {timeout: 160000}, async t => {
    await withFixture(async ({originals, write, execute}) => {
        for (const [file, before, after, failure] of [
            ['source/utils/twitchAdProtocol.brs', 'return twitchAdClockEpochProject(state, publication)',
                'return twitchAdClockProject(state.adClockTimeline, publication, state.epoch)',
                'epoch-integration-fixture: HEAD/GET exact projected content length'],
            [server, 'if FormatJson(projection) = entry.adProjectionSeal then bytes = twitchAdClockManifest(request.track, publication, projection)',
                'bytes = twitchAdClockManifest(request.track, publication, projection)',
                'epoch-integration-fixture: actual Server rejects changed frozen timing sidecar'],
            ['source/utils/twitchAdClock.brs', 'if segment.epoch <> previous.epoch and difference < 0& then return false',
                "' Deliberately removed cross-epoch UTC nonoverlap",
                'epoch-integration-fixture: actual valid media feed rejects ambiguous optional UTC only']
        ]) {
            const source = originals.get(file).toString();
            assert.equal(source.split(before).length, 2, 'one actual timing guard mutation');
            const changed = source.replace(before, after);
            assert.deepEqual(bsc.Parser.parse(changed, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await write(file, changed);
            const result = await execute();
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_AD_EPOCH_FAIL: ${result.marker} ${failure}`), result.output);
            assert.throws(() => positive(result, result.marker));
            t.diagnostic(JSON.stringify({mutation: before, normalExit: true, rejected: true, elapsedMs: result.elapsedMs}));
            await write(file, originals.get(file));
        }
    });
});

test('mixed timing runner refuses stale, empty, duplicate, failed and crashed summaries', () => {
    const marker = randomUUID();
    const cases = ['mixed-source-local-PDT-cue-http-and-leases', 'same-map-timestamp-reset-keeps-exact-anchors',
        'ambiguous-UTC-is-optional-canonical-fallback'];
    const output = cases.map(name => 'STITCH_EPOCH_INTEGRATION_CASE: ' + name + '\n').join('') +
        `STITCH_AD_EPOCH_PASS: ${marker} ` + JSON.stringify({assertions: 1, cases: 3, goldens: 1, pairs: 1, manifests: 8, admissions: 1}) + '\n';
    const valid = {code: 0, signal: null, timedOut: false, exceeded: false, output, elapsedMs: 1, bytes: output.length};
    positive(valid, marker);
    positive({...valid, output: output.replaceAll('\n', '\r\n')}, marker);
    for (const bad of [{output: output.replace(marker, 'OLD')}, {output: output.replace('"assertions":1', '"assertions":0')},
        {output: output + output}, {output: output + 'EXIT_BRIGHTSCRIPT_CRASH\n'}, {code: 7}, {signal: 'SIGTERM'},
        {output: output + 'STITCH_AD_EPOCH_FAIL: rejected\n'}, {timedOut: true}, {exceeded: true}, {startupError: 'spawn failed'}]) {
        assert.throws(() => positive({...valid, ...bad}, marker));
    }
});
