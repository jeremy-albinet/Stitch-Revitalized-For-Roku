'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/roku-demux-server');
const prefix = 'stitch-roku-demux-server-';
const helpers = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch', 'rokuDemuxCommon',
    'rokuDemuxProtocol', 'rokuDemuxInitMetadata', 'rokuDemuxServerPolicy', 'rokuDemuxInitGate',
    'rokuDemuxDescriptor', 'deviceCapabilities', 'playbackHls',
    'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol'].map(name => `source/utils/${name}.brs`);
const server = 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs';

function exactFunction(source, name) {
    const matches = source.match(new RegExp(`^(?:function|sub) ${name}\\b[^]*?^end (?:function|sub)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one actual production ${name} required`);
    return matches[0] + '\n';
}

function requireNativeKeys(source) {
    const parsed = bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript});
    assert.deepEqual(parsed.diagnostics, []);
    const expected = new Set(['sessionId', 'actualInitValidated', 'decoderApproved']);
    const seen = new Set();
    parsed.ast.walk(bsc.createVisitor({AAMemberExpression(member) {
        const quoted = member.keyToken.kind === bsc.TokenKind.StringLiteral;
        const text = quoted ? member.keyToken.text.slice(1, -1) : member.keyToken.text;
        const canonical = [...expected].find(key => key.toLowerCase() === text.toLowerCase());
        if (!canonical) return;
        seen.add(canonical);
        assert.equal(quoted ? text : text.toLowerCase(), canonical, `quote native field ${canonical}`);
    }}), {walkMode: bsc.WalkMode.visitAllRecursive});
    assert.deepEqual([...seen].sort(), [...expected].sort());
}

function run(dir, files, control) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'),
            '--no-sg', '--root', dir, '--deep-link', `control=${control}`, ...files],
            {cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, exceeded = false, timedOut = false, startupError;
        const timer = setTimeout(() => {timedOut = true; child.kill();}, 45000);
        const collect = data => {
            bytes += data.length;
            if (bytes > 65536) {exceeded = true; child.kill(); return;}
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => {startupError = error;});
        child.once('close', code => {clearTimeout(timer); resolve({code, output, exceeded, timedOut, startupError});});
    });
}

function requireExecution(result) {
    const detail = result.output.slice(-10000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception/i, detail);
    assert.doesNotMatch(result.output, /fixtureSignature|fixture%2Btoken|canned\.ttvnw\.net|"sourceUrl"/, 'signed descriptor must not reach logs');
    return detail;
}

function requirePositive(result, marker) {
    const detail = requireExecution(result);
    assert.doesNotMatch(result.output, /STITCH_ROKU_SERVER_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/);
    const pass = lines.filter(line => line.startsWith(`STITCH_ROKU_SERVER_PASS: ${marker}`));
    assert.equal(pass.length, 1, `one fresh marker required\n${detail}`);
    const counts = pass[0].match(/ cases=\s*(\d+) assertions=\s*(\d+)$/);
    assert.ok(counts, detail);
    const cases = lines.filter(line => line.startsWith('STITCH_ROKU_SERVER_CASE: '));
    assert.equal(cases.length, new Set(cases).size, 'duplicate case markers are not coverage');
    assert.equal(Number(counts[1]), cases.length);
    assert.equal(cases.length, 130, 'complete narrowed HTTP/adapter corpus required');
    assert.equal(Number(counts[2]), 451, 'all actual assertions must execute');
    for (const name of ['adapter-default-off', 'adapter-stop-before-init', 'adapter-signed-query-and-initialization-failure',
        'adapter-actual-init-and-ready-gate', 'adapter-stop-during-init-validation', 'adapter-actual-decoder-refusal',
        'adapter-master-only-bind-refusal', 'adapter-steady-quota-boundaries', 'adapter-steady-clock-and-lifetime-send',
        'helper-failure-during-error-send', 'manifest-pin-cleanup-order']) {
        assert.ok(cases.includes(`STITCH_ROKU_SERVER_CASE: ${name}`), `required actual case ${name}`);
    }
    return {cases: Number(counts[1]), assertions: Number(counts[2])};
}

test('server opt-in and exact native session proof fields reject actual source mutation', async () => {
    const source = await fs.readFile(path.join(root, server), 'utf8');
    requireNativeKeys(source);
    assert.throws(() => requireNativeKeys(source.replace('"sessionId": m.sessionId', 'sessionId: m.sessionId')), /quote native field sessionId/);
    assert.doesNotMatch(source, /\b(?:print|loopbackLog|WriteAsciiFile|ReadAsciiFile|loopbackLoadConfig|loopbackLoadSteadyConfig)\b/i);
    const gate = await fs.readFile(path.join(root, 'source/utils/rokuDemuxInitGate.brs'), 'utf8');
    assert.doesNotMatch(gate, /\b(?:print|loopbackLog)\b/i);
    const xml = await fs.readFile(path.join(root, server.replace('.brs', '.xml')), 'utf8');
    assert.match(xml, /<field id="experimentalMode" type="boolean" value="false"\s*\/>/);
    assert.match(xml, /<field id="cacheBudgetBytes" type="integer" value="16777216"\s*\/>/);
    assert.match(xml, /<field id="result" type="assocarray" alwaysNotify="true"\s*\/>/);
    assert.match(xml, /<field id="ready" type="assocarray" alwaysNotify="true"\s*\/>/);
    assert.match(xml, /pkg:\/source\/utils\/rokuDemuxInitGate\.brs/);
    assert.doesNotMatch(source, /\.control\s*=\s*"stop"/i, 'server must return naturally after cleanup');
});

test('actual guarded server handlers preserve IO bounds, init gate, failure and cleanup', {timeout: 180000}, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = randomUUID();
    const sources = new Map();
    async function add(file, bytes) {
        const target = path.join(dir, file);
        await fs.mkdir(path.dirname(target), {recursive: true});
        await fs.writeFile(target, bytes);
    }
    try {
        for (const file of [...helpers, server, server.replace('.brs', '.xml')]) {
            const bytes = await fs.readFile(path.join(root, file));
            sources.set(file, bytes.toString());
            await add(file, bytes);
            assert.deepEqual(await fs.readFile(path.join(dir, file)), bytes, 'actual production bytes copied unchanged');
        }
        await add('manifest', 'title=Offline Guarded Roku Server\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\nrsg_version=1.2\nbs_const=tests=false\n');
        await add('bsconfig.json', JSON.stringify({rootDir: dir, files: ['source/**/*', 'components/**/*', 'manifest'],
            plugins: [], createPackage: false, copyToStaging: false, deploy: false, watch: false,
            logLevel: 'off', showDiagnosticsInConsole: false}));
        const builder = new bsc.ProgramBuilder();
        try {
            await builder.run({project: path.join(dir, 'bsconfig.json')});
            assert.equal(path.resolve(builder.rootDir), path.resolve(dir));
            assert.deepEqual(builder.getDiagnostics().map(value => ({code: value.code, message: value.message,
                file: value.file?.pkgPath, line: value.range?.start.line})), [], 'complete runtime/Task source must compile without suppressed diagnostics');
            t.diagnostic('scoped complete actual runtime/Task XML compile: zero diagnostics');
        } finally {builder.program?.dispose();}
        const core = sources.get('source/utils/rokuDemuxCore.brs');
        const clock = ['nlCheck', 'nlInteger', 'nativeLiveClockCreate', 'nativeLiveClockAdvance'].map(name => exactFunction(core, name)).join('\n');
        await add('clock-reference.brs', clock);
        await add('feed-reference.brs', exactFunction(sources.get('source/utils/rokuDemuxFetch.brs'), 'rokuDemuxFeedInput'));
        await add('hex-reference.brs', exactFunction(sources.get('source/utils/deviceCapabilities.brs'), 'playbackHexValue'));
        const main = await fs.readFile(path.join(fixture, 'main.brs'), 'utf8');
        await add('main.brs', main.replace('__RUN_MARKER__', marker));
        for (const file of ['adapter.brs', 'init-corpus.json']) await add(file, await fs.readFile(path.join(fixture, file)));
        const files = ['source/utils/rokuDemuxCommon.brs', 'source/utils/rokuDemuxProtocol.brs',
            'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs', 'source/utils/twitchAdProtocol.brs',
            'source/utils/playbackHls.brs', 'source/utils/rokuDemuxDescriptor.brs',
            'source/utils/rokuDemuxBulk.brs', 'source/utils/rokuDemuxInitMetadata.brs',
            'source/utils/rokuDemuxInitGate.brs', 'source/utils/rokuDemuxServerPolicy.brs',
            'clock-reference.brs', 'feed-reference.brs', 'hex-reference.brs', server, 'main.brs', 'adapter.brs'];
        const positive = await run(dir, files, 'positive');
        const counts = requirePositive(positive, marker);
        t.diagnostic(`fresh actual execution marker: ${marker}`);
        t.diagnostic(`${counts.cases} actual handler cases / ${counts.assertions} assertions; mocked native transport/decoder boundaries`);
        assert.throws(() => requirePositive(positive, 'STALE_MARKER'), /one fresh marker required/);
        for (const [control, failure] of [['header', 'header-400 complete bytes'], ['fatal', 'helper failure remains fatal']]) {
            const negative = await run(dir, files, control);
            requireExecution(negative);
            const failures = negative.output.split(/\r?\n/).filter(line => line.startsWith('STITCH_ROKU_SERVER_FAIL:'));
            assert.deepEqual(failures, [`STITCH_ROKU_SERVER_FAIL: http-fixture: ${failure}`]);
            assert.doesNotMatch(negative.output, /STITCH_ROKU_SERVER_PASS:/);
            assert.throws(() => requirePositive(negative, marker), /STITCH_ROKU_SERVER_FAIL/);
        }
        t.diagnostic('genuine reversed header/helper-failure expectations and stale marker rejected');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, {recursive: true, force: true});
        await assert.rejects(fs.stat(resolved), {code: 'ENOENT'});
    }
});
