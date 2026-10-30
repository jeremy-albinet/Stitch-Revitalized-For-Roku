'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {createHash, randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/roku-demux-map-rotation');
const corpusFixture = path.join(__dirname, 'fixtures/roku-demux-core');
const prefix = 'stitch-roku-map-rotation-';
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const sourceFiles = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch', 'rokuDemuxCommon',
    'rokuDemuxProtocol', 'rokuDemuxInitMetadata', 'rokuDemuxInitGate', 'rokuDemuxServerPolicy',
    'rokuDemuxDescriptor', 'deviceCapabilities', 'playbackHls',
    'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol'].map(name => `source/utils/${name}.brs`);
const server = 'components/Tasks/RokuDemuxServer/RokuDemuxServer';
const sha = data => createHash('sha256').update(data).digest('hex');
const cases = ['equivalent-map-pending-gate-media-and-held-lease', 'binary-refusal-same-length-valid',
    'binary-refusal-longer-valid', 'binary-refusal-malformed', 'pending-before', 'pending-during',
    'pending-decoder-refusal', 'source-refusal-epoch', 'source-refusal-mixed-map',
    'source-refusal-cached-media-uri', 'source-refusal-unapproved-origin', 'transport-deadline-retry', 'transport-deadline',
    'transport-work-quota', 'transport-cancel-failure', 'transport-healthy-pending',
    'successful-only-safe-alias-telemetry-and-exhaustion'];

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one actual ${name} body`);
    return matches[0] + '\n';
}

function runChild(args, cwd, timeoutMs = 45000, outputLimit = 65536) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, args, {cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => {timedOut = true; child.kill();}, timeoutMs);
        const collect = data => {
            bytes += data.length;
            if (bytes > outputLimit) {exceeded = true; child.kill(); return;}
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => {startupError = error;});
        child.once('close', code => {clearTimeout(timer); resolve({code, output, timedOut, exceeded, startupError});});
    });
}

function requireExecution(result) {
    const detail = result.output.slice(-12000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, `child timeout\n${detail}`);
    assert.equal(result.exceeded, false, `child output limit\n${detail}`);
    assert.equal(result.code, 0, `child exit ${result.code}\n${detail}`);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    assert.doesNotMatch(result.output, /fixtureSigned|fixtureAlias|cdn\.example\.invalid|"sourceUrl"/, 'input URLs must not reach output');
    return detail;
}

function requirePositive(result, marker) {
    const detail = requireExecution(result);
    assert.doesNotMatch(result.output, /STITCH_ROKU_MAP_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_ROKU_MAP_CASE: ')), cases.map(name => `STITCH_ROKU_MAP_CASE: ${name}`));
    const passes = lines.filter(line => line.startsWith('STITCH_ROKU_MAP_PASS: '));
    assert.equal(passes.length, 1, detail);
    assert.ok(passes[0].startsWith(`STITCH_ROKU_MAP_PASS: ${marker} `), 'fresh marker required');
    const counts = passes[0].match(/ cases=\s*(\d+) assertions=\s*(\d+)$/);
    assert.ok(counts, detail);
    assert.equal(Number(counts[1]), cases.length);
    assert.equal(Number(counts[2]), 563, 'complete real-function assertions required');
    return {cases: Number(counts[1]), assertions: Number(counts[2])};
}

async function narrowCorpus() {
    const raw = await fs.readFile(path.join(corpusFixture, 'corpus.json'));
    const provenance = JSON.parse(await fs.readFile(path.join(corpusFixture, 'provenance.json')));
    assert.equal(sha(raw), provenance.corpusSha256, 'released synthetic Python corpus identity');
    const prior = JSON.parse(raw);
    const init = Buffer.from(prior.init.input.hex, 'hex');
    assert.equal(sha(init), prior.init.input.sha256);
    const sameLength = Buffer.from(init);
    const tkhd = sameLength.indexOf(Buffer.from('tkhd')) - 4;
    assert.ok(tkhd >= 0);
    // Change a legal creation-time byte, preserving all sample/config/decoder metadata.
    sameLength[tkhd + 12] ^= 1;
    const longer = Buffer.concat([init, Buffer.from('0000000866726565', 'hex')]);
    const malformed = init.subarray(0, init.length - 1);
    const changed = [['same-length-valid', sameLength, true], ['longer-valid', longer, true],
        ['malformed', malformed, false]].map(([name, bytes, valid]) => ({name, hex: bytes.toString('hex'),
        count: bytes.length, sha256: sha(bytes), valid}));
    const media = prior.media.slice(0, 4);
    for (const item of [prior.init.input, prior.init.video, prior.init.audio,
        ...media.flatMap(item => [item.input, item.video, item.audio])]) {
        const bytes = Buffer.from(item.hex, 'hex');
        assert.equal(bytes.length, item.count);
        assert.equal(sha(bytes), item.sha256);
    }
    return {init: {...prior.init, metadata: {videoCodec: prior.init.metadata.videoCodec,
        audioCodec: prior.init.metadata.audioCodec, width: prior.init.metadata.width,
        height: prior.init.metadata.height, frameRate: '60.000', bandwidth: 8042999, isHD: true}}, media, changed};
}

test('actual same-init MAP rotation retains approved assets and refuses changed bytes/epoch/unsafe IO', {timeout: 180000}, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const sources = new Map();
    const marker = randomUUID();
    async function add(name, bytes) {
        const target = path.join(dir, name);
        await fs.mkdir(path.dirname(target), {recursive: true});
        await fs.writeFile(target, bytes);
    }
    try {
        for (const name of [...sourceFiles, `${server}.brs`, `${server}.xml`]) {
            const bytes = await fs.readFile(path.join(root, name));
            sources.set(name, bytes);
            await add(name, bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, name)), bytes, 'complete actual source copied unchanged');
        }
        await add('manifest', 'title=Offline MAP Identity Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add('bsconfig.json', JSON.stringify({rootDir: dir, files: ['source/**/*', 'components/**/*', 'manifest'],
            plugins: [], createPackage: false, copyToStaging: false, deploy: false, watch: false,
            logLevel: 'off', showDiagnosticsInConsole: false}));
        const builder = new bsc.ProgramBuilder();
        try {
            await builder.run({project: path.join(dir, 'bsconfig.json')});
            assert.equal(path.resolve(builder.rootDir), path.resolve(dir));
            assert.deepEqual(builder.getDiagnostics().map(value => ({code: value.code, message: value.message,
                file: value.file?.pkgPath, line: value.range?.start.line})), [], 'full actual Task XML/runtime compile');
            t.diagnostic('complete actual runtime/Task XML scoped compile: zero diagnostics');
        } finally {builder.program?.dispose();}
        const coreName = 'source/utils/rokuDemuxCore.brs';
        const fetch = sources.get('source/utils/rokuDemuxFetch.brs').toString();
        const fetchBodies = ['nlInputPath', 'nativeLiveInputCleanup', 'nlCancelInput', 'nlSafeError', 'nlTimeout',
            'nativeLiveTick', 'nativeLiveDiagnostics', 'nativeLiveClose', 'rokuDemuxFeedInput']
            .map(name => exactFunction(fetch, name)).join('\n');
        await add('fetch-reference.brs', fetchBodies);
        await add('alias-reference.brs', exactFunction(sources.get(`${server}.brs`).toString(), 'recordLiveInitAliases'));
        const harness = (await fs.readFile(path.join(fixture, 'main.brs'), 'utf8')).replace('__MARKER__', marker);
        assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await add('main.brs', harness);
        await add('corpus.json', JSON.stringify(await narrowCorpus()));
        const args = [cli, '--no-sg', '--root', dir, 'source/utils/rokuDemuxBulk.brs', coreName,
            'source/utils/rokuDemuxCommon.brs', 'source/utils/rokuDemuxProtocol.brs',
            'source/utils/rokuDemuxInitMetadata.brs', 'source/utils/rokuDemuxInitGate.brs',
            'fetch-reference.brs', 'alias-reference.brs', 'main.brs'];
        const execute = () => runChild(args, dir);
        const positive = await execute();
        const counts = requirePositive(positive, marker);
        assert.throws(() => requirePositive(positive, randomUUID()), /fresh marker required/);
        t.diagnostic(`fresh actual-function execution ${marker}: ${counts.cases} cases / ${counts.assertions} assertions`);
        const core = sources.get(coreName).toString();
        const equality = 'payload.Count() = state.initByteCount and digest = state.initDigest';
        // Mutate the original path; opted-in source transitions have their own
        // identity checks and negative controls in the epoch integration suite.
        const legacyIdentity = `        else\n            nlCheck(${equality}, "selected map initialization changed")\n        end if`;
        assert.equal(core.split(legacyIdentity).length, 2);
        await add(coreName, core.replace(legacyIdentity, legacyIdentity.replace(equality, 'true')));
        const wrongIdentity = await execute();
        requireExecution(wrongIdentity);
        assert.match(wrongIdentity.output, /STITCH_ROKU_MAP_FAIL: map-fixture: changed binary rejected same-length-valid/);
        assert.throws(() => requirePositive(wrongIdentity, marker));
        await add(coreName, sources.get(coreName));
        const precheck = 'if state.phase = "init-rotation" then unused = nlInitDigest(state, payload)';
        assert.equal(fetchBodies.split(precheck).length, 2);
        await add('fetch-reference.brs', fetchBodies.replace(precheck, "' Deliberate failed control: remove pre-gate identity check."));
        const wrongOrder = await execute();
        requireExecution(wrongOrder);
        assert.match(wrongOrder.output, /STITCH_ROKU_MAP_FAIL: map-fixture: changed candidate never reaches decoder gate or replaces approved metadata/);
        assert.throws(() => requirePositive(wrongOrder, marker));
        t.diagnostic('genuine actual SHA identity and gate-order mutations rejected; IO boundaries are mocked, not native evidence');
        for (const [name, bytes] of sources) assert.deepEqual(await fs.readFile(path.join(root, name)), bytes, 'production bytes remain frozen during tests');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, {recursive: true, force: true});
        await assert.rejects(fs.stat(resolved), {code: 'ENOENT'});
    }
});

test('MAP fixture runner rejects actual failure, timeout, overflow and nonzero processes', {timeout: 15000}, async () => {
    const execute = code => runChild(['-e', code], os.tmpdir(), 1500, 1024);
    const failed = await execute('console.log("STITCH_ROKU_MAP_FAIL: deliberate");');
    assert.throws(() => requirePositive(failed, randomUUID()));
    const timedOut = await runChild(['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timedOut.timedOut, true);
    assert.throws(() => requirePositive(timedOut, randomUUID()), /child timeout/);
    const overflow = await execute('process.stdout.write("x".repeat(2048));');
    assert.equal(overflow.exceeded, true);
    assert.throws(() => requirePositive(overflow, randomUUID()), /child output limit/);
    const nonzero = await execute('process.exitCode=9;');
    assert.equal(nonzero.code, 9);
    assert.throws(() => requirePositive(nonzero, randomUUID()), /child exit 9/);
});
