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
const fixtures = path.join(__dirname, 'fixtures/roku-vod-player');
const sharedFixtures = path.join(__dirname, 'fixtures/roku-demux-player');
const managerPath = 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs';
const managerXml = 'components/Modules/RokuDemuxSession/RokuDemuxSession.xml';
const playerPath = 'components/Scenes/VideoPlayer/VideoPlayer.brs';
const playerXml = 'components/Scenes/VideoPlayer/VideoPlayer.xml';
const taskPath = 'components/Tasks/GetTwitchContent/GetTwitchContent.brs';
const runtimePath = 'source/utils/rokuVodRuntime.brs';
const dependencies = ['source/utils/taskFactory.brs', 'source/utils/recentlyWatched.brs', 'source/utils/rokuDemuxDescriptor.brs',
    'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs', runtimePath,
    'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs',
    'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs'];
const snapshotPaths = [managerPath, managerXml, playerPath, playerXml, taskPath,
    'components/Tasks/GetTwitchContent/GetTwitchContent.xml',
    'components/Scenes/VideoPlayer/RokuPlayback.brs', ...dependencies];

async function snapshot() {
    return Promise.all(snapshotPaths.map(async file => [file,
        createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

async function add(dir, file, body) {
    const target = path.join(dir, file);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, body);
}

async function copy(dir, file) {
    await add(dir, file, await fs.readFile(path.join(root, file)));
}

async function tree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await tree(dir, file);
        else await copy(dir, file);
    }
}

async function probeXml(dir, file, probeFile, probe) {
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    assert.ok(exports, 'actual-handler probe exports missing');
    const original = await fs.readFile(path.join(root, file), 'utf8');
    assert.equal(original.split('</interface>').length, 2);
    assert.equal(original.split('</component>').length, 2);
    await add(dir, file, original.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', `<script uri="pkg:/components/${probeFile}" /></component>`));
    await add(dir, `components/${probeFile}`, probe);
}

async function build(dir, marker, capability, mutation) {
    await add(dir, 'manifest', 'title=Offline VOD Player Contract\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/analytics.brs',
        'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircGifs.brs', 'source/utils/chatAnimationGif.brs', ...dependencies]) await copy(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster',
        'components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler', 'components/Modules/StitchVideo',
        'components/Modules/CustomVideo', 'components/Modules/AdCountdown',
        'components/Modules/AdMetadataOwner', 'components/Tasks/LowLatencyRelay']) await tree(dir, folder);
    for (const file of ['source/utils/lowLatencyPlaylist.brs', 'source/utils/rokuDemuxCommon.brs']) await copy(dir, file);
    for (const file of ['TwitchAdMetadata.xml', 'TwitchAdMetadata.brs']) {
        await add(dir, `components/${file}`, await fs.readFile(path.join(root, 'tools/tests/fixtures/ad-countdown-player', file)));
    }
    for (const asset of ['ChatAnimationAsset.xml', 'ChatAnimationAsset.brs', 'ChatGifAtlas.brs']) await add(dir, `components/Modules/Chat/ChatAnimationAsset/${asset}`, await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimationAsset', asset)));
    await add(dir, 'source/utils/chatAnimationWebp.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
    for (const file of ['Chat.xml', 'Chat.brs', 'ChatAnimations.brs']) await copy(dir, `components/Modules/Chat/${file}`);
    for (const file of ['EmojiLabel.xml', 'EmojiLabel.brs', 'EmojiLabelUtil.brs']) await copy(dir, `components/Modules/EmojiLabel/${file}`);
    for (const file of ['RokuPlayerHost.xml', 'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs',
        'TwitchApiTask.xml', 'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml']) {
        await add(dir, `components/${file}`, await fs.readFile(path.join(sharedFixtures, file)));
    }
    await add(dir, 'components/TwitchEngagementTask.xml',
        await fs.readFile(path.join(root, 'tools/tests/fixtures/ui-phase2-player/TwitchEngagementTask.xml')));
    await add(dir, 'source/utils/config.brs', `${await fs.readFile(path.join(sharedFixtures, 'config.brs'), 'utf8')}\n${await fs.readFile(path.join(__dirname, 'fixtures/ui-account-settings/registry.brs'), 'utf8')}`);
    await add(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(sharedFixtures, 'EmojiLabelRegex.brs')));
    for (const file of [managerPath, playerPath, 'components/Scenes/VideoPlayer/RokuPlayback.brs', 'components/Scenes/VideoPlayer/LowLatencyPlayback.brs', 'components/Scenes/VideoPlayer/ChatLayout.brs', 'components/Scenes/VideoPlayer/ChannelFollow.brs', 'components/Scenes/VideoPlayer/ContentAdvisory.brs']) {
        await copy(dir, file);
        assert.deepEqual(await fs.readFile(path.join(dir, file)), await fs.readFile(path.join(root, file)), 'actual owner/player handlers must execute unchanged');
    }
    for (const [file, name, fixture] of [[managerXml, 'ManagerProbe.brs', 'ManagerProbe.brs'],
        [playerXml, 'PlayerProbe.brs', '../roku-demux-player/PlayerProbe.brs'],
        ['components/Modules/CustomVideo/CustomVideo.xml', 'VideoProbe.brs', 'VideoProbe.brs']]) {
        await probeXml(dir, file, name, await fs.readFile(path.join(fixtures, fixture), 'utf8'));
    }
    // The Task body is actual production. Only its native decoder query is a
    // deterministic offline IO boundary, with reversibility checked below.
    const originalTask = await fs.readFile(path.join(root, taskPath), 'utf8');
    const nativeDecoder = 'device = CreateObject("roDeviceInfo")';
    assert.equal(originalTask.split(nativeDecoder).length, 2);
    const controlledTask = originalTask.replace(nativeDecoder, 'device = fixtureDecoder()');
    assert.equal(controlledTask.replace('device = fixtureDecoder()', nativeDecoder), originalTask);
    await add(dir, 'components/VodContentBody.brs', controlledTask);
    await add(dir, 'components/ContentBoundary.brs', await fs.readFile(path.join(fixtures, 'ContentBoundary.brs')));
    await add(dir, 'components/VodContentProbe.xml', `<component name="VodContentProbe" extends="Group"><interface>
      <function name="loadHlsContent" /><field id="response" type="node" /><field id="metadata" type="array" />
      <field id="enableRokuDemux" type="boolean" /><field id="fixtureMaster" type="string" /><field id="fixturePlaylist" type="string" />
      <field id="fixtureMasterStatus" type="integer" /><field id="httpRequests" type="array" /><field id="graphqlCount" type="integer" />
      </interface><script uri="VodContentBody.brs" /><script uri="ContentBoundary.brs" />
      ${['source/utils/config.brs', 'source/utils/analytics.brs', 'source/utils/misc.brs', ...dependencies].map(file => `<script uri="pkg:/${file}" />`).join('')}</component>`);
    const workerFields = `<field id="sessionId" type="string" /><field id="inputDescriptor" type="assocarray" />
      <field id="experimentalMode" type="boolean" /><field id="cacheBudgetBytes" type="integer" /><field id="listenPort" type="integer" />
      <field id="stopRequested" type="boolean" /><field id="ready" type="assocarray" alwaysNotify="true" />
      <field id="result" type="assocarray" alwaysNotify="true" /><field id="functionName" type="string" />
      <field id="control" type="string" onChange="onControl" /><field id="state" type="string" value="init" alwaysNotify="true" />`;
    for (const name of ['RokuDemuxServer', 'RokuVodDemuxServer']) {
        const optionalFields = name === 'RokuDemuxServer' ? '<field id="enableAdMetadata" type="boolean" value="false" />' : '';
        await add(dir, `components/${name}.xml`, `<component name="${name}" extends="Group"><interface>${workerFields}${optionalFields}</interface><script uri="WorkerBoundary.brs" /></component>`);
    }
    await add(dir, 'components/WorkerBoundary.brs', 'sub onControl()\n    if m.top.control = "run" then m.top.state = "run"\n    if m.top.control = "stop" then m.top.state = "stop"\nend sub\n');
    await add(dir, 'components/VodVideoBoundary.xml', '<component name="VodVideoBoundary" extends="Group"><interface><field id="control" type="string" /><field id="state" type="string" alwaysNotify="true" /></interface></component>');
    const actualRuntime = await fs.readFile(path.join(dir, runtimePath), 'utf8');
    assert.equal(actualRuntime, await fs.readFile(path.join(root, runtimePath), 'utf8'));
    const availability = /function rokuVodRuntimeAvailable\(\) as boolean\r?\n    return true\r?\nend function/;
    assert.equal([...actualRuntime.matchAll(new RegExp(availability.source, 'g'))].length, 1);
    assert.ok(capability === 'enabled' || capability === 'disabled');
    // Enabled cases retain the actual production body. Disabled cases change
    // only the compiled capability boundary, preserving its line endings.
    if (capability === 'disabled') {
        const productionBody = actualRuntime.match(availability)[0];
        const disabledBody = productionBody.replace('return true', 'return false');
        const controlled = actualRuntime.replace(productionBody, disabledBody);
        assert.equal(controlled.replace(disabledBody, productionBody), actualRuntime);
        await add(dir, runtimePath, controlled);
    }
    let main = (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replace('__CAPABILITY__', capability);
    if (mutation === 'failed-assertion' || mutation === 'stale-marker') {
        const actualMain = main.match(/sub main\(\)[\s\S]*?end sub/)[0];
        main = main.replace(actualMain, actualMain.replace('        testContentTask()\n', '')
            .replace(/        if m.enabled[\s\S]*?        end if/, ''));
    }
    if (mutation === 'failed-assertion') {
        assert.equal(main.split('check(true, "negative summary anchor")').length, 2);
        main = main.replace('check(true, "negative summary anchor")', 'check(false, "deliberate VOD assertion failure")');
    }
    if (mutation === 'ready-path') {
        const body = await fs.readFile(path.join(dir, runtimePath), 'utf8');
        const guard = '        if not rokuDemuxString(ready["masterPath"]) or ready["masterPath"] <> "/vod/" + sessionId + "/master.m3u8" then return false';
        assert.equal(body.split(guard).length, 2);
        await add(dir, runtimePath, body.replace(guard, ''));
        const actualMain = main.match(/sub main\(\)[\s\S]*?end sub/)[0];
        main = main.replace(actualMain, actualMain.replace('        testContentTask()\n', '')
            .replace('            testOwnerReplacement()\n', '').replace('            testPlayer()\n', ''));
    }
    if (mutation === 'video-stop') {
        const body = await fs.readFile(path.join(dir, managerPath), 'utf8');
        const method = /function sessionCleanupAcknowledged\(\) as boolean[\s\S]*?end function/;
        const original = body.match(method)?.[0];
        const proof = '    if m.video <> invalid\r?\n        if m.video.state <> "stopped" then return false\r?\n    end if';
        const proofPattern = new RegExp(proof);
        assert.equal([...original.matchAll(new RegExp(proof, 'g'))].length, 1);
        await add(dir, managerPath, body.replace(method, original.replace(proofPattern, '')));
        const actualMain = main.match(/sub main\(\)[\s\S]*?end sub/)[0];
        main = main.replace(actualMain, actualMain.replace('        testContentTask()\n', '')
            .replace('            testOwnerReady()\n', '').replace('            testPlayer()\n', ''));
    }
    await add(dir, 'source/main.brs', main);
    const summary = mutation === 'stale-marker' ? `STITCH_UI_PASS:${randomUUID()}` : marker;
    await add(dir, 'source/support.brs', (await fs.readFile(path.join(fixtures, 'support.brs'), 'utf8')).replaceAll('__PASS_MARKER__', summary));
    await add(dir, 'bsconfig.json', JSON.stringify({ rootDir: dir, files: ['source/**/*', 'components/**/*', 'manifest'],
        createPackage: false, copyToStaging: false, deploy: false, watch: false, logLevel: 'off', showDiagnosticsInConsole: false,
        // Existing intentional SceneManagerGroup onDestroy/onKeyEvent overrides.
        diagnosticFilters: [{ src: playerPath, codes: [1010] }] }));
    const builder = new bsc.ProgramBuilder();
    try {
        await builder.run({ project: path.join(dir, 'bsconfig.json') });
        assert.deepEqual(builder.getDiagnostics().map(d => ({ code: d.code, message: d.message, file: d.file?.pkgPath, line: d.range?.start.line })), []);
    } finally { builder.program?.dispose(); }
}

function run(command, args, cwd, timeoutMs = 40000, outputLimit = 1024 * 1024) {
    return new Promise((resolve, reject) => {
        const started = Date.now();
        const child = spawn(command, args, { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, output, bytes, timedOut, exceeded, elapsedMs: Date.now() - started }); });
    });
}

function normal(result) {
    const detail = JSON.stringify({ ...result, output: result.output.slice(-18000) });
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    // Existing engine limitation only: native legacy stream arrays cannot be
    // stored. Every other runtime/compiler/crash diagnostic stays a failure.
    let supported = result.output;
    for (const location of result.arrayLocations ?? []) {
        const escaped = location.file.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        supported = supported.replace(new RegExp(`^BRIGHTSCRIPT: ERROR: roSGNode\\.AddReplace: "TwitchContentNode\\.(?:streams|streamqualities)": Type mismatch! pkg:[^\\r\\n]*${escaped}\\(${location.line}\\)\\r?\\n`, 'gmi'), '');
    }
    assert.doesNotMatch(supported, /BRIGHTSCRIPT:\s*ERROR:|Syntax Error|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception|failed to set up component/i, detail);
    assert.match(result.output, /EXIT_USER_NAV/, detail);
}

function positive(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /STITCH_UI_FAIL:/, result.output.slice(-18000));
    const all = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
    assert.equal(all.length, 1, result.output.slice(-18000));
    assert.equal(all[0][0].split(': ')[0], marker, 'fresh success marker missing');
    assert.ok(Number(all[0][1]) > 0, 'zero actual assertions');
    return Number(all[0][1]);
}

async function fixture(capability = 'enabled', mutation = '') {
    const prefix = 'stitch-vod-player-';
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const before = await snapshot();
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const dir = path.join(temp, 'package');
        await build(dir, marker, capability, mutation);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await run(process.execPath, [path.join(sharedFixtures, 'key-driver.js'), path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], temp);
        result.arrayLocations = [];
        for (const [file, anchor] of [['components/VodContentBody.brs', '    content.SetFields(metadata[index])'],
            ['components/Scenes/VideoPlayer/RokuPlayback.brs', '        playable.setFields(fields)'],
            ['components/Modules/TwitchContentNode/TwitchContentNode.brs', '    m.top.title = m.top.contentTitle']]) {
            const body = await fs.readFile(path.join(dir, file), 'utf8');
            assert.equal(body.split(anchor).length, 2);
            result.arrayLocations.push({ file: path.basename(file), line: body.slice(0, body.indexOf(anchor)).split(/\r?\n/).length });
        }
        assert.deepEqual(await snapshot(), before, 'production owner/player/helper snapshot changed');
        return { result, marker };
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual VOD Task, owner and player preserve the native capability gate and recorded contracts', { timeout: 100000 }, async t => {
    for (const capability of ['disabled', 'enabled']) {
        const { result, marker } = await fixture(capability);
        t.diagnostic(`${capability}: ${positive(result, marker)} actual assertions, ${result.elapsedMs}ms/${result.bytes} output bytes; HTTP/GQL/decoder/worker are explicit inert IO, no native delivery proof`);
    }
});

test('VOD readiness-path regression and normal-exit failed/stale summaries are rejected', { timeout: 150000 }, async t => {
    for (const mutation of ['ready-path', 'video-stop', 'failed-assertion', 'stale-marker']) {
        const { result, marker } = await fixture('enabled', mutation);
        normal(result);
        if (mutation === 'ready-path') assert.match(result.output, /STITCH_UI_FAIL:malformed current VOD Ready refuses and cooperatively stops: masterPath/);
        if (mutation === 'video-stop') assert.match(result.output, /STITCH_UI_FAIL:one STOP alone cannot replace the VOD owner/);
        if (mutation === 'failed-assertion') assert.match(result.output, /STITCH_UI_FAIL:deliberate VOD assertion failure/);
        if (mutation === 'stale-marker') assert.doesNotMatch(result.output, /STITCH_UI_FAIL:/);
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${mutation}: actual normal-exit control rejected, ${result.elapsedMs}ms/${result.bytes} bytes`);
    }
});

test('VOD result validator keeps positive-count, marker, crash, exit, deadline and output bounds', { timeout: 12000 }, async () => {
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    const good = { code: 0, signal: null, timedOut: false, exceeded: false, output: `${marker}: 1 assertions\nEXIT_USER_NAV\n` };
    for (const newline of ['\n', '\r\n']) assert.equal(positive({ ...good, output: good.output.replaceAll('\n', newline) }, marker), 1);
    for (const changed of [{ timedOut: true }, { exceeded: true }, { code: 3 },
        { output: good.output.replace(': 1 assertions', ': 0 assertions') }, { output: good.output + good.output },
        { output: good.output.replace(marker, `STITCH_UI_PASS:${randomUUID()}`) }, { output: '' },
        { output: good.output.replace('EXIT_USER_NAV', 'EXIT_BRIGHTSCRIPT_CRASH') },
        { output: good.output + 'STITCH_UI_FAIL:wrong\n' }, { output: good.output + 'BRIGHTSCRIPT: ERROR: extra\n' }]) {
        assert.throws(() => positive({ ...good, ...changed }, marker));
    }
    const timeout = await run(process.execPath, ['-e', 'setInterval(()=>{},100);'], os.tmpdir(), 150, 1024);
    assert.equal(timeout.timedOut, true);
    assert.throws(() => positive(timeout, marker));
    const overflow = await run(process.execPath, ['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.equal(overflow.exceeded, true);
    assert.throws(() => positive(overflow, marker));
    const nonzero = await run(process.execPath, ['-e', `process.stdout.write(${JSON.stringify(good.output)}); process.exitCode=3;`], os.tmpdir(), 2000, 1024);
    assert.equal(nonzero.code, 3);
    assert.throws(() => positive(nonzero, marker));
});
