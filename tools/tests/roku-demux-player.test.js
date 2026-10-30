'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/roku-demux-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const keyDriver = path.join(fixtures, 'key-driver.js');
const snapshotFiles = ['components/Scenes/VideoPlayer/VideoPlayer.brs',
    'components/Scenes/VideoPlayer/VideoPlayer.xml', 'components/Scenes/VideoPlayer/RokuPlayback.brs',
    'components/heroScene.brs', 'components/heroScene.xml',
    'components/Modules/StitchVideo/StitchVideo.brs', 'components/Modules/StitchVideo/StitchVideo.xml',
    'components/Modules/VideoErrorHandler/VideoErrorHandler.brs', 'source/utils/rokuDemuxCore.brs'];
async function snapshot() {
    return Promise.all(snapshotFiles.map(async file => [file,
        createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

async function addFile(dir, file, data) {
    const target = path.join(dir, file);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, data);
}

async function copyFile(dir, file) {
    await addFile(dir, file, await fs.readFile(path.join(root, file)));
}

async function copyTree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await copyTree(dir, file);
        else await copyFile(dir, file);
    }
}

async function fixture(name) {
    return fs.readFile(path.join(fixtures, name), 'utf8');
}

function selectRecoveryEntry(main, recoveryOnly) {
    const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
    assert.ok(start, 'fixture main entry required');
    const recoveryCalls = ['testNativeRecoveryStartupDeadline()', 'testObsoleteLiveReconnect()', 'testFailedRefreshRecoveryOwnership()'];
    for (const call of recoveryCalls) assert.equal(start.split(call).length, 2, `one actual ${call} entry required`);
    return main.replace(start, start.split(/\r?\n/).filter(line => !/^\s+test/.test(line)
        || recoveryCalls.includes(line.trim()) === recoveryOnly).join('\n'));
}

async function buildPackage(dir, marker, mode = 'normal') {
    await addFile(dir, 'manifest', 'title=Roku Player Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/recentlyWatched.brs', 'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircGifs.brs', 'source/utils/chatAnimationGif.brs',
        'source/utils/rokuDemuxDescriptor.brs', 'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs',
        'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs',
        'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster',
        'components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler', 'components/Modules/StitchVideo',
        'components/Modules/CustomVideo', 'components/Modules/AdCountdown']) await copyTree(dir, folder);
    const qualityXmlPath = 'components/Modules/StitchVideo/StitchVideo.xml';
    const qualityXml = await fs.readFile(path.join(dir, qualityXmlPath), 'utf8');
    await addFile(dir, qualityXmlPath, qualityXml
        .replace('</interface>', '<function name="fixtureQualityDialog" /></interface>')
        .replace('</component>', '<script uri="pkg:/components/QualityProbe.brs" /></component>'));
    await addFile(dir, 'components/QualityProbe.brs', 'function fixtureQualityDialog() as object\n    return m.qualityDialog\nend function\n');
    const liveCore = await fs.readFile(path.join(root, 'source/utils/rokuDemuxCore.brs'), 'utf8');
    const liveWindowBodies = ['nlCheck', 'nlWindow'].map(name => {
        const match = liveCore.match(new RegExp(`^(?:sub|function) ${name}\\b[^]*?^end (?:sub|function)\\r?$`, 'm'));
        assert.ok(match, `actual ${name} body required`);
        return match[0];
    }).join('\n\n');
    await addFile(dir, 'source/ActualLiveWindow.brs', liveWindowBodies);
    for (const asset of ['ChatAnimationAsset.xml', 'ChatAnimationAsset.brs', 'ChatGifAtlas.brs']) await addFile(dir, `components/Modules/Chat/ChatAnimationAsset/${asset}`, await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimationAsset', asset)));
    await addFile(dir, 'source/utils/chatAnimationWebp.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
    for (const file of ['Chat.xml', 'Chat.brs', 'ChatAnimations.brs']) await copyFile(dir, `components/Modules/Chat/${file}`);
    // Actual EmojiLabel rendering code; pattern construction is an explicit
    // existing engine boundary. Transport/bookmarks/registry never start.
    for (const file of ['EmojiLabel.xml', 'EmojiLabel.brs', 'EmojiLabelUtil.brs']) await copyFile(dir, `components/Modules/EmojiLabel/${file}`);
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fixture('EmojiLabelRegex.brs'));
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    for (const file of ['RokuPlayerHost.xml', 'SessionBoundary.xml', 'SessionBoundary.brs',
        'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    // Inert relay boundary: the loopback server and its playlists are covered
    // by the offline low-latency-playlist fixture.
    await addFile(dir, 'components/LowLatencyRelay.xml', '<component name="LowLatencyRelay" extends="Group"><interface><field id="sourceUrl" type="string" /><field id="startCount" type="integer" value="3" /><field id="maxCount" type="integer" value="15" /><field id="stopRequested" type="boolean" value="false" /><field id="status" type="assocarray" /><field id="ended" type="boolean" value="false" /><field id="control" type="string" /></interface></component>');
    await addFile(dir, 'components/DialogKeyBoundary.xml', '<component name="DialogKeyBoundary" extends="Group"><interface><field id="pressCount" type="integer" /></interface><script uri="DialogKeyBoundary.brs" /></component>');
    await addFile(dir, 'components/DialogKeyBoundary.brs', 'function onKeyEvent(key as string, press as boolean) as boolean\n    if LCase(key) = "ok" and press then m.top.pressCount++\n    return true\nend function\n');
    const probe = await fixture('PlayerProbe.brs');
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    assert.ok(exports, 'read-only inspection exports missing');
    const originalXml = await fs.readFile(path.join(root, snapshotFiles[1]), 'utf8');
    const xml = originalXml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', '<script uri="pkg:/components/PlayerProbe.brs" /></component>');
    await addFile(dir, snapshotFiles[1], xml);
    await addFile(dir, 'components/PlayerProbe.brs', probe);
    await copyFile(dir, 'components/Scenes/VideoPlayer/LowLatencyPlayback.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ChannelFollow.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ContentAdvisory.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ChatLayout.brs');
    for (const file of [snapshotFiles[0], snapshotFiles[2]]) {
        await copyFile(dir, file);
        assert.deepEqual(await fs.readFile(path.join(dir, file)), await fs.readFile(path.join(root, file)), `${file} must execute unchanged`);
    }
    // Control only the watchdog's native wall-clock read; its health/stall
    // handlers and all other production bodies remain byte-identical.
    const playerPath = snapshotFiles[0];
    const actualPlayer = await fs.readFile(path.join(dir, playerPath), 'utf8');
    const watchdog = /sub onWatchdogFire\(\)[\s\S]*?end sub/;
    const watchdogSource = actualPlayer.match(watchdog)?.[0];
    const nativeClock = 'nowSec = CreateObject("roDateTime").AsSeconds()';
    assert.equal(watchdogSource?.split(nativeClock).length, 2, 'one actual watchdog clock read required');
    const controlledWatchdog = watchdogSource.replace(nativeClock, 'nowSec = fixtureWatchdogClock()');
    assert.equal(controlledWatchdog.replace('nowSec = fixtureWatchdogClock()', nativeClock), watchdogSource);
    await addFile(dir, playerPath, actualPlayer.replace(watchdog, controlledWatchdog));
    // The absolute startup clock is the second explicit time boundary. Keep
    // the actual assignment/Mark and all deadline/progress decisions intact.
    const startupClock = 'm.playbackInitTime = CreateObject("roTimeSpan")';
    const elapsedClock = 'm.playbackInitTime.TotalMilliseconds()';
    let controlledPlayer = await fs.readFile(path.join(dir, playerPath), 'utf8');
    assert.equal(controlledPlayer.split(startupClock).length, 2, 'one prepared-Video startup clock required');
    assert.equal(controlledPlayer.split(elapsedClock).length, 3, 'two actual remaining-startup reads required');
    controlledPlayer = controlledPlayer.replace(startupClock, 'm.playbackInitTime = fixtureStartupClock()')
        .replaceAll(elapsedClock, 'fixtureStartupElapsed()');
    await addFile(dir, playerPath, controlledPlayer);
    let main = await fixture('main.brs');
    if (mode === 'normal' || mode === 'crash-recovery') {
        main = selectRecoveryEntry(main, mode === 'crash-recovery');
    } else {
        // The full runs own every behavior case. Only delivery timing and the
        // report's deliberate failure need an additional focused engine run.
        const entries = { 'repeated-retry': 'testFailedRetryAndRecovery()',
            'failed-assertion': 'testChoiceReadyAndBack()' };
        const entry = entries[mode];
        assert.ok(entry, `unknown fixture mode: ${mode}`);
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.equal(start?.split(`    ${entry}`).length, 2, 'one actual scenario entry required');
        main = main.replace(start, start.split(/\r?\n/).filter(line => !/^\s+test/.test(line)
            || line.trim() === entry).join('\n'));
    }
    if (mode === 'failed-assertion') {
        assert.ok(main.includes('check(true, "failure-control anchor")'));
        main = main.replace('check(true, "failure-control anchor")', 'check(false, "deliberate wrong assertion")');
    }
    await addFile(dir, 'source/main.brs', main);
    await addFile(dir, 'source/support.brs', (await fixture('support.brs')).replaceAll('__PASS_MARKER__', marker));
}

function runChild(command, args, cwd, timeoutMs = 60000, outputLimit = 1024 * 1024) {
    return new Promise((resolve, reject) => {
        const started = Date.now();
        const child = spawn(command, args, { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
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
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded, elapsedMs: Date.now() - started });
        });
    });
}

function childDiagnostic(result, context = 'fixture') {
    const failures = result.output.split(/\r?\n/).filter(line => line.includes('STITCH_UI_FAIL:')).join('\n');
    return `${context}: code=${result.code} signal=${result.signal} timedOut=${result.timedOut} exceeded=${result.exceeded} elapsedMs=${result.elapsedMs}\n${failures}\n${result.output.slice(-16000)}`;
}

function assertNormalExit(result, context = 'fixture') {
    const failure = childDiagnostic(result, context);
    assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
    // brs-node cannot assign these native ContentNode fields; all production
    // scripts still execute unchanged. Do not claim their array storage or
    // hardware behavior. Every other engine error remains a failure.
    const supportedOutput = result.output.replace(/^BRIGHTSCRIPT: ERROR: roSGNode\.AddReplace: "TwitchContentNode\.(?:streams|streamqualities)": Type mismatch! pkg:.*TwitchContentNode\.brs\(\d+\)\r?\n/gm, '');
    assert.doesNotMatch(supportedOutput, /BRIGHTSCRIPT: ERROR:/, failure);
    assert.doesNotMatch(result.output, /FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
    assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
}

function acceptResult(result, marker) {
    assertNormalExit(result);
    const failure = childDiagnostic(result);
    assert.doesNotMatch(result.output, /STITCH_UI_FAIL:/, failure);
    const summaries = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
    assert.equal(summaries.length, 1, `expected exactly one summary\n${failure}`);
    const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
    assert.ok(summary, `fresh success marker missing\n${failure}`);
    assert.ok(Number(summary[1]) > 0, `zero actual assertions\n${failure}`);
    return Number(summary[1]);
}

async function runFixture(mode = 'normal') {
    const prefix = 'stitch-roku-player-';
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    const before = await snapshot();
    try {
        const dir = path.join(temp, 'package');
        await buildPackage(dir, marker, mode);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        let driver = keyDriver;
        if (mode === 'repeated-retry') {
            let script = await fs.readFile(keyDriver, 'utf8');
            const gap = 'const repeatGapMs = 250;';
            assert.equal(script.split(gap).length, 2);
            script = script.replace(gap, 'const repeatGapMs = 600;');
            const schedule = 'nextFree = start + hold;';
            assert.equal(script.split(schedule).length, 2);
            script = script.replace(schedule, 'if (key === lastKey && start === nextFree + repeatGapMs) process.stderr.write("FIXTURE_REPEAT_QUEUED\\n");\n    ' + schedule);
            driver = path.join(temp, 'controlled-key-driver.js');
            await fs.writeFile(driver, script);
        }
        const result = await runChild(process.execPath, [driver, cli, zip], temp);
        assert.deepEqual(await snapshot(), before, 'the production snapshot changed while the fixture ran');
        return { result, marker };
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('core and dedicated recovery entries cover every actual fixture case once', async () => {
    const main = await fixture('main.brs');
    const cases = source => source.match(/sub main\(\)[\s\S]*?end sub/)[0]
        .match(/^\s+test\w+\(\)/gm).map(line => line.trim());
    const core = cases(selectRecoveryEntry(main, false));
    const recovery = cases(selectRecoveryEntry(main, true));
    assert.deepEqual(recovery, ['testNativeRecoveryStartupDeadline()', 'testObsoleteLiveReconnect()', 'testFailedRefreshRecoveryOwnership()']);
    const combined = [...core, ...recovery];
    assert.equal(new Set(combined).size, combined.length, 'core and recovery must not repeat cases');
    assert.deepEqual(combined.sort(), cases(main).sort(), 'every original entry must still run');
    const declared = [...main.matchAll(/^sub (test\w+)\(\)/gm)].map(match => `${match[1]}()`);
    assert.deepEqual(combined, declared.sort(), 'every actual test method must have an entry');
});

test('actual player callbacks start eligible Roku playback, session ready, retry, quality switch, Back and disposal', { timeout: 90000 }, async t => {
    const { result, marker } = await runFixture();
    const count = acceptResult(result, marker);
    assert.throws(() => acceptResult(result, `STITCH_UI_PASS:${randomUUID()}`), /fresh success marker missing/);
    t.diagnostic(`${count} actual SceneGraph assertions; Session and network are explicit inert IO boundaries; no decoder/hardware proof`);
});

test('actual recovery callbacks preserve absolute native startup and discard only obsolete healthy-owner reconnects', { timeout: 90000 }, async t => {
    const { result, marker } = await runFixture('crash-recovery');
    t.diagnostic(`${acceptResult(result, marker)} actual callback assertions with controlled clocks and inert network/session boundaries; no native decoder proof`);
});

test('a genuine failed BrightScript assertion is rejected', { timeout: 180000 }, async () => {
    const failed = await runFixture('failed-assertion');
    assertNormalExit(failed.result, 'failed-assertion');
    assert.match(failed.result.output, /STITCH_UI_FAIL:deliberate wrong assertion/);
    assert.match(failed.result.output, /STITCH_UI_FAIL:\s*1 failures;\s*[1-9]\d* assertions/, childDiagnostic(failed.result, 'failed-assertion'));
    assert.throws(() => acceptResult(failed.result, failed.marker));
});

test('actual repeated Try again waits for delayed key delivery', { timeout: 180000 }, async t => {
    const actual = await runFixture('repeated-retry');
    assert.match(actual.result.output, /FIXTURE_REPEAT_QUEUED/);
    t.diagnostic(`${acceptResult(actual.result, actual.marker)} actual retry/session assertions after queued repeated OK`);
});

test('bounded child transport rejects failure output, timeout, overflow and nonzero exit', { timeout: 15000 }, async () => {
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    const valid = `${marker}: 1 assertions\nEXIT_USER_NAV\n`;
    const child = script => runChild(process.execPath, ['-e', script], os.tmpdir(), 2000, 1024);
    const badOutput = await child(`process.stdout.write(${JSON.stringify(valid + 'STITCH_UI_FAIL: deliberate\n')});`);
    assert.throws(() => acceptResult(badOutput, marker));
    const timeout = await runChild(process.execPath, ['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timeout.timedOut, true);
    assert.throws(() => acceptResult(timeout, marker), /timed out/);
    const overflow = await child('process.stdout.write("x".repeat(2048));');
    assert.equal(overflow.exceeded, true);
    assert.throws(() => acceptResult(overflow, marker), /output limit/);
    const nonzero = await child(`process.stdout.write(${JSON.stringify(valid)}); process.exitCode = 7;`);
    assert.equal(nonzero.code, 7);
    assert.throws(() => acceptResult(nonzero, marker), /exited 7/);
});
