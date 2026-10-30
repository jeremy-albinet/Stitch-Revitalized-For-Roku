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
const fixture = path.join(__dirname, 'fixtures/roku-demux-epoch-integration');
const prefix = 'stitch-roku-epoch-integration-';
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
    assert.doesNotMatch(result.output, /STITCH_EPOCH_INTEGRATION_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const summaries = lines.filter(line => line.startsWith('STITCH_EPOCH_INTEGRATION_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    const tag = `STITCH_EPOCH_INTEGRATION_PASS: ${marker} `;
    assert.ok(summaries[0].startsWith(tag), 'one fresh actual execution marker required');
    const counts = JSON.parse(summaries[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), ['admissions', 'assertions', 'cases', 'goldens', 'manifests', 'pairs']);
    for (const value of Object.values(counts)) assert.ok(Number.isSafeInteger(value) && value > 0);
    const cases = lines.filter(line => line.startsWith('STITCH_EPOCH_INTEGRATION_CASE: '));
    assert.deepEqual(cases, ['actual-content-ad-content-approval-publication-request', 'actual-mixed-later-init-http', 'same-map-actual-tfdt-reset',
        'incompatible-init-and-native-decision-before-feed', 'typed-policy-default-off-and-malformed-refusals',
        'actual-send-failure-stop-and-transfer-cancel-cleanup'].map(name => 'STITCH_EPOCH_INTEGRATION_CASE: ' + name));
    assert.equal(counts.cases, cases.length);
    assert.equal(counts.manifests, 6);
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
        const boundary = await fs.readFile(path.join(fixture, 'boundary.brs'), 'utf8');
        for (const source of [main, boundary]) assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
        await write('boundary.brs', boundary);
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
            .concat(['hex-reference.brs', server, 'boundary.brs', 'main.brs']);
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


test('actual combined Core/Fetch/gate/Protocol/Server source transitions and cleanup', {timeout: 60000}, async t => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
        t.diagnostic('actual production Core/Fetch/gate/Protocol/Server; only native device decision/socket I/O mocked, no network or hardware claim');
    });
});

test('actual integrated master/decoder/advertisement/approval-order mutations fail at normal exit', {timeout: 120000}, async t => {
    await withFixture(async ({originals, write, execute}) => {
        const mutants = [
            [fetch, '    if kind = "init"\n        \' Reject changed bytes before the gate can replace the approved metadata.',
                '    nativeLiveFeed(state, kind, payload, nowMs)\n    if kind = "init"\n        \' Reject changed bytes before the gate can replace the approved metadata.',
                'native-live: actual init owner or phase invalid'],
            [gate, 'nlCheck(liveInitMasterCompatible(actual, timing), "actual init master incompatible")',
                "' Deliberately removed immutable master compatibility", 'epoch-integration-fixture: incompatible or stopped init is refused before real Core staging entry'],
            [gate, 'nlCheck(allowed, "actual init decoder rejected")',
                "' Deliberately removed native decoder refusal", 'epoch-integration-fixture: incompatible or stopped init is refused before real Core staging decoder'],
            [server, 'if asset.id = id', 'if asset.id = id and (id = entry.publication.initVideoId or id = entry.publication.initAudioId or liveAssetRole(entry.publication,id) = "media")',
                'epoch-integration-fixture: all actual later epoch initialization pairs are advertised']
        ];
        for (const [file, before, after, failure] of mutants) {
            const source = originals.get(file).toString().replaceAll('\r\n','\n');
            assert.equal(source.split(before).length, 2, 'one exact actual production guard mutation');
            let changed = source.replace(before, after);
            if(file === fetch) {
                const trailing='    nativeLiveFeed(state, kind, payload, nowMs)\n    return true';
                assert.equal(changed.split(trailing).length,2,'actual trailing feed moves, with no duplication');
                changed=changed.replace(trailing,'    return true');
            }
            assert.deepEqual(bsc.Parser.parse(changed, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await write(file, changed);
            const result = await execute();
            normalExit(result);
            assert.ok(result.output.includes(`STITCH_EPOCH_INTEGRATION_FAIL: ${result.marker} ${failure}`), result.output);
            assert.throws(() => positive(result,result.marker));
            t.diagnostic(JSON.stringify({mutation:failure,elapsedMs:result.elapsedMs}));
            await write(file,originals.get(file));
        }
    });
});

test('integrated runner rejects stale/zero/duplicate/crash and actual finite child failures across LF/CRLF', {timeout: 15000}, async () => {
    const marker=randomUUID();
    const cases=['actual-content-ad-content-approval-publication-request','actual-mixed-later-init-http','same-map-actual-tfdt-reset',
        'incompatible-init-and-native-decision-before-feed','typed-policy-default-off-and-malformed-refusals',
        'actual-send-failure-stop-and-transfer-cancel-cleanup'];
    const output=cases.map(name=>'STITCH_EPOCH_INTEGRATION_CASE: '+name+'\n').join('')+
        'STITCH_EPOCH_INTEGRATION_PASS: '+marker+' '+JSON.stringify({assertions:1,cases:6,goldens:1,pairs:1,manifests:6,admissions:1})+'\n';
    const valid=await child(['-e',`process.stdout.write(${JSON.stringify(output)});`],os.tmpdir(),2000);
    positive(valid,marker);
    positive({...valid,output:output.replaceAll('\n','\r\n')},marker);
    for(const bad of [{output:output.replace(marker,'OLD')},{output:output.replace('"assertions":1','"assertions":0')},
        {output:output+output},{output:output+'EXIT_BRIGHTSCRIPT_CRASH\n'},{code:7},{signal:'SIGTERM'},
        {output:output.replace('STITCH_EPOCH_INTEGRATION_CASE: same-map','IGNORED_CASE: same-map')},
        {output:output+'STITCH_EPOCH_INTEGRATION_FAIL: failed\n'},{startupError:'spawn failed'}]) {
        assert.throws(()=>positive({...valid,...bad},marker));
    }
    const timeout=await child(['-e','setInterval(()=>{},100)'],os.tmpdir(),150,1024);
    assert.equal(timeout.timedOut,true);assert.throws(()=>positive(timeout,marker));
    const overflow=await child(['-e','process.stdout.write("x".repeat(2048))'],os.tmpdir(),2000,1024);
    assert.equal(overflow.exceeded,true);assert.throws(()=>positive(overflow,marker));
    const nonzero=await child(['-e','process.exitCode=9'],os.tmpdir(),2000,1024);
    assert.equal(nonzero.code,9);assert.throws(()=>positive(nonzero,marker));
});
