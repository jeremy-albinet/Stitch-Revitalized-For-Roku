'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixturePath = path.join(__dirname, 'fixtures/roku-demux-session');
const managerPath = 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs';
const managerXmlPath = 'components/Modules/RokuDemuxSession/RokuDemuxSession.xml';
const prefix = 'stitch-roku-demux-session-';

function run(zip, mode, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'),
            '--deep-link', `control=${mode}`, zip], { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', outputBytes = 0, exceeded = false, timedOut = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
        const collect = data => {
            if (exceeded) return;
            outputBytes += data.length;
            if (outputBytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, exceeded, timedOut, startupError });
        });
    });
}

function requireNormal(result) {
    const detail = result.output.slice(-16000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|Syntax Error|unhandled exception/i, detail);
    return detail;
}

function requirePositive(result, marker) {
    const detail = requireNormal(result);
    assert.doesNotMatch(result.output, /SESSION_ASSERT_FAIL:|SESSION_FAIL_/, detail);
    const passes = result.output.split(/\r?\n/).filter(line => line.startsWith(`SESSION_PASS_${marker}:`));
    assert.equal(passes.length, 1, `expected one fresh session summary\n${detail}`);
    const counts = passes[0].match(/:\s*(\d+)\s*$/);
    assert.ok(counts && Number(counts[1]) >= 110, detail);
    return Number(counts[1]);
}

test('session runner rejects timeout, output limit, crash and missing fresh summaries', () => {
    const valid = { startupError: undefined, timedOut: false, exceeded: false, code: 0,
        output: 'SESSION_PASS_CURRENT: 127\n' };
    assert.equal(requirePositive(valid, 'CURRENT'), 127);
    for (const control of [
        { timedOut: true }, { exceeded: true }, { code: 1 }, { startupError: new Error('inert spawn failure') },
        { output: 'SESSION_PASS_OLD: 127\n' }, { output: 'SESSION_PASS_CURRENT: 0\n' },
        { output: valid.output + valid.output }, { output: 'EXIT_BRIGHTSCRIPT_CRASH\n' + valid.output },
        { output: 'SESSION_ASSERT_FAIL: control\n' + valid.output },
    ]) assert.throws(() => requirePositive({ ...valid, ...control }, 'CURRENT'));
});

test('production session manager enforces owner cleanup, typed ready, queue and experimental options', { timeout: 110000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const packageDir = path.join(dir, 'package');
    const marker = randomUUID();
    async function add(file, data) {
        const target = path.join(packageDir, file);
        await fs.mkdir(path.dirname(target), { recursive: true });
        await fs.writeFile(target, data);
    }
    try {
        const actual = await fs.readFile(path.join(root, managerPath), 'utf8');
        const boundary = 'CreateObject("roSGNode", "RokuDemuxServer")';
        assert.equal(actual.split(boundary).length, 2, 'only the worker IO boundary may be replaced');
        const fixtureSource = actual.replace(boundary, 'CreateObject("roSGNode", "SessionWorkerBoundary")') + `
function fixtureRead() as object
    return { worker: m.worker, video: m.video, pending: m.pending, currentId: m.currentId,
        stopping: m.stopping, workerResult: m.workerResult, cleanupClock: m.cleanupClock, disposed: m.disposed }
end function
function fixtureDiagnostic(result as object) as object
    return sessionWorkerDiagnostic(result)
end function
sub fixtureTimeout()
    m.cleanupClock = { TotalMilliseconds: function() as integer
        return 15000
    end function }
    onCleanupTick()
end sub
sub fixtureArmResult(result as object)
    m.workerResult = result
end sub
sub fixtureTick()
    onCleanupTick()
end sub
`;
        await add(managerPath, fixtureSource);
        assert.equal(fixtureSource.slice(0, actual.replace(boundary, 'CreateObject("roSGNode", "SessionWorkerBoundary")').length)
            .replace('CreateObject("roSGNode", "SessionWorkerBoundary")', boundary), actual,
        'every production manager handler must execute unchanged');
        let xml = await fs.readFile(path.join(root, managerXmlPath), 'utf8');
        assert.equal(xml.split('</interface>').length, 2);
        xml = xml.replace('</interface>', '<function name="fixtureRead" /><function name="fixtureDiagnostic" /><function name="fixtureTimeout" /><function name="fixtureArmResult" /><function name="fixtureTick" /></interface>');
        await add(managerXmlPath, xml);
        const dependencies = ['source/utils/taskFactory.brs', 'source/utils/rokuDemuxDescriptor.brs',
            'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs',
            'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs'];
        for (const file of dependencies) {
            const bytes = await fs.readFile(path.join(root, file));
            await add(file, bytes);
            assert.deepEqual(await fs.readFile(path.join(packageDir, file)), bytes, `${file} must remain unchanged`);
        }
        await add('components/SessionWorkerBoundary.xml', `<component name="SessionWorkerBoundary" extends="Group"><interface>
          <field id="sessionId" type="string" /><field id="inputDescriptor" type="assocarray" />
          <field id="experimentalMode" type="boolean" value="false" /><field id="enableAdMetadata" type="boolean" value="false" /><field id="cacheBudgetBytes" type="integer" value="16777216" />
          <field id="listenPort" type="integer" value="0" /><field id="functionName" type="string" />
          <field id="control" type="string" onChange="onControl" /><field id="state" type="string" value="init" alwaysNotify="true" />
          <field id="ready" type="assocarray" alwaysNotify="true" /><field id="result" type="assocarray" alwaysNotify="true" />
          <field id="stopRequested" type="boolean" value="false" />
          </interface><script uri="SessionWorkerBoundary.brs" /></component>`);
        await add('components/SessionWorkerBoundary.brs', 'sub onControl()\n    if m.top.control = "run" then m.top.state = "run"\n    if m.top.control = "stop" then m.top.state = "stop"\nend sub\n');
        await add('components/RokuVodDemuxServer.xml', '<component name="RokuVodDemuxServer" extends="SessionWorkerBoundary" />');
        await add('components/SessionVideoBoundary.xml', '<component name="SessionVideoBoundary" extends="Group"><interface><field id="control" type="string" /><field id="state" type="string" value="none" /></interface></component>');
        // Uncalled taskFactory branches need known compile declarations only;
        // none of these inert Groups perform Task/network/Video work.
        for (const name of ['TwitchApiTask', 'GetTwitchContent']) {
            await add(`components/${name}.xml`, `<component name="${name}" extends="Group" />`);
        }
        await add('components/SessionHarness.xml', '<component name="SessionHarness" extends="Scene"><interface><function name="runTests" /><field id="testResult" type="assocarray" /></interface><script uri="session-tests.brs" /></component>');
        await add('components/session-tests.brs', await fs.readFile(path.join(fixturePath, 'session-tests.brs')));
        await add('manifest', 'title=Offline Production Session Contract\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add('source/main.brs', `sub main(input as dynamic)
    screen = CreateObject("roSGScreen")
    scene = screen.CreateScene("SessionHarness")
    screen.Show()
    scene.callFunc("runTests", input.control)
    result = scene.testResult
    if result <> invalid and result.failures = 0
        print "SESSION_PASS_${marker}: "; result.assertions
    else
        print "SESSION_FAIL_${marker}: "; FormatJSON(result)
    end if
    screen.Close()
end sub
`);
        await add('bsconfig.json', JSON.stringify({ rootDir: packageDir, files: ['source/**/*', 'components/**/*', 'manifest'],
            createPackage: false, copyToStaging: false, deploy: false, watch: false,
            logLevel: 'off', showDiagnosticsInConsole: false }));
        const builder = new bsc.ProgramBuilder();
        try {
            await builder.run({ project: path.join(packageDir, 'bsconfig.json') });
            assert.equal(path.resolve(builder.rootDir), path.resolve(packageDir));
            assert.deepEqual(builder.getDiagnostics().map(diagnostic => ({ code: diagnostic.code, message: diagnostic.message,
                file: diagnostic.file?.pkgPath, line: diagnostic.range?.start.line })), []);
            t.diagnostic('scoped actual-handler BrightScript/SceneGraph compile: zero diagnostics');
        } finally {
            builder.program?.dispose();
        }
        const zip = path.join(dir, 'session.zip');
        await zipFolder(packageDir, zip);
        for (const mode of ['positive', 'early', 'cleanup']) {
            const result = await run(zip, mode, dir);
            if (mode === 'positive') {
                const count = requirePositive(result, marker);
                assert.doesNotMatch(result.output, /DIAGNOSTIC_SECRET_TOKEN|private\.invalid|unexpected_sensitive_error/,
                    'actual result logging must exclude private input and unrecognized text');
                assert.match(result.output, /"helperReason"\s*:\s*"continuity_window_crosses_map_or_discontinuity"/,
                    'actual known continuity failure logs only its static code');
                assert.match(result.output, /"helperReason"\s*:\s*"selected_window_crosses_map_or_discontinuity"/,
                    'actual selected-window failure logs only its fixed static code');
                t.diagnostic(`${count} actual manager-handler assertions; worker/Video IO is inert`);
                assert.throws(() => requirePositive(result, 'STALE_MARKER'), /expected one fresh session summary/);
            } else {
                requireNormal(result);
                const failures = result.output.split(/\r?\n/).filter(line => line.startsWith('SESSION_ASSERT_FAIL:')).map(line => line.trim());
                const reason = mode === 'early' ? 'deliberate early-release control' : 'deliberate false-cleanup control';
                assert.deepEqual(failures, [`SESSION_ASSERT_FAIL: ${reason}`]);
                assert.doesNotMatch(result.output, /SESSION_PASS_/);
                assert.throws(() => requirePositive(result, marker), /SESSION_ASSERT_FAIL/);
            }
        }
        // Remove only the new post-cleanup owner guard from the actual handler.
        // This must reproduce the real reviewed S-1 continuation defect.
        const ownerGuard = /    if not m\.stopping or m\.worker = invalid or m\.cleanupClock = invalid then return\r?\n    if m\.currentId <> ownerId or not m\.worker\.isSameNode\(owner\) then return/;
        assert.equal(fixtureSource.match(ownerGuard)?.length, 1);
        const mutation = fixtureSource.replace(ownerGuard, '    if m.worker = invalid then return');
        await add(managerPath, mutation);
        const mutationZip = path.join(dir, 'timer-mutation.zip');
        await zipFolder(packageDir, mutationZip);
        const failed = await run(mutationZip, 'timer', dir);
        assert.equal(failed.startupError, undefined);
        assert.equal(failed.timedOut, false);
        assert.equal(failed.exceeded, false);
        assert.notEqual(failed.code, 0, failed.output.slice(-8000));
        assert.match(failed.output, /EXIT_BRIGHTSCRIPT_CRASH/);
        assert.match(failed.output, /invalid BrightScript Component or interface reference/);
        assert.doesNotMatch(failed.output, /SESSION_PASS_/);
        assert.throws(() => requirePositive(failed, marker));
        t.diagnostic('early-release, false-cleanup, stale-marker and actual S-1 timer mutation controls rejected');
        const terminalWait = /        m\.cleanupClock = invalid\r?\n        m\.top\.busy = false\r?\n        return/;
        assert.equal(fixtureSource.match(terminalWait)?.length, 1);
        await add(managerPath, fixtureSource.replace(terminalWait, '        m.cleanupClock = invalid\n        return'));
        const terminalZip = path.join(dir, 'terminal-wait-mutation.zip');
        await zipFolder(packageDir, terminalZip);
        const terminalFailure = await run(terminalZip, 'positive', dir);
        requireNormal(terminalFailure);
        assert.match(terminalFailure.output, /SESSION_ASSERT_FAIL: one-shot unsafe stop ends UI wait/);
        assert.doesNotMatch(terminalFailure.output, /SESSION_PASS_/);
        assert.throws(() => requirePositive(terminalFailure, marker));
        t.diagnostic('actual terminal busy-clear removal reproduces R2-1 and is rejected');
        const blockedGate = /function canLeaveBlockedSession\(sessionId as string\) as boolean[\s\S]*?end function/;
        const gateBody = fixtureSource.match(blockedGate)?.[0];
        assert.ok(gateBody);
        const actualVideoStop = '        if m.video.state <> "stopped" then return false';
        assert.equal(gateBody.split(actualVideoStop).length, 2);
        await add(managerPath, fixtureSource.replace(gateBody, gateBody.replace(actualVideoStop, '')));
        const videoProofZip = path.join(dir, 'blocked-video-proof-mutation.zip');
        await zipFolder(packageDir, videoProofZip);
        const videoProofFailure = await run(videoProofZip, 'positive', dir);
        requireNormal(videoProofFailure);
        assert.match(videoProofFailure.output, /SESSION_ASSERT_FAIL: playing Video refuses blocked UI exit despite stop control/);
        assert.doesNotMatch(videoProofFailure.output, /SESSION_PASS_/);
        assert.throws(() => requirePositive(videoProofFailure, marker));
        t.diagnostic('actual blocked-exit Video STOP proof removal is rejected');
        const resultLog = 'FormatJSON(sessionWorkerDiagnostic(result))';
        assert.equal(fixtureSource.split(resultLog).length, 2);
        await add(managerPath, fixtureSource.replace(resultLog, 'FormatJSON(result)'));
        const rawLogZip = path.join(dir, 'raw-result-log-mutation.zip');
        await zipFolder(packageDir, rawLogZip);
        const rawLogFailure = await run(rawLogZip, 'positive', dir);
        requirePositive(rawLogFailure, marker);
        assert.match(rawLogFailure.output, /DIAGNOSTIC_SECRET_TOKEN/);
        assert.throws(() => assert.doesNotMatch(rawLogFailure.output,
            /DIAGNOSTIC_SECRET_TOKEN|private\.invalid|unexpected_sensitive_error/));
        t.diagnostic('raw result logging mutation exposes the sentinel and is rejected');
        const destroyBody = /sub onDestroy\(\)[\s\S]*?end sub/;
        const destroySource = fixtureSource.match(destroyBody)?.[0];
        assert.ok(destroySource);
        const prematureDetach = destroySource.replace('    stopSession("")', `    if m.worker <> invalid
        m.worker.unobserveField("ready")
        m.worker.unobserveField("result")
        m.worker.unobserveField("state")
    end if
    if m.cleanupTimer <> invalid
        m.cleanupTimer.control = "stop"
        m.cleanupTimer.unobserveField("fire")
    end if
    stopSession("")`);
        await add(managerPath, fixtureSource.replace(destroySource, prematureDetach));
        const detachZip = path.join(dir, 'premature-detach-mutation.zip');
        await zipFolder(packageDir, detachZip);
        const detachFailure = await run(detachZip, 'positive', dir);
        requireNormal(detachFailure);
        assert.match(detachFailure.output, /SESSION_ASSERT_FAIL: disposal completes only after actual acknowledgment/);
        assert.throws(() => requirePositive(detachFailure, marker));
        t.diagnostic('premature teardown observer removal abandons acknowledgment and is rejected');
        for (const [gate, expected, name] of [
            ['    if not m.readyReceived then return "worker_finished"', 'transition classification requires exact ready reason and safe cleanup', 'startup-ready'],
            ['    if not sessionCleanupSafe() then return "worker_finished"', 'transition classification requires exact ready reason and safe cleanup', 'unsafe-resource-cleanup']
        ]) {
            assert.equal(fixtureSource.split(gate).length, 2, `one actual ${name} transition guard required`);
            await add(managerPath, fixtureSource.replace(gate, ''));
            const guardZip = path.join(dir, `${name}-transition-mutation.zip`);
            await zipFolder(packageDir, guardZip);
            const guardFailure = await run(guardZip, 'positive', dir);
            requireNormal(guardFailure);
            assert.ok(guardFailure.output.includes(`SESSION_ASSERT_FAIL: ${expected}`));
            assert.throws(() => requirePositive(guardFailure, marker));
            t.diagnostic(`actual ${name} transition guard removal is rejected`);
        }
        const transitionReturn = 'or result.helperFailureReason = "native-live: source sequence gap" then return "source_transition"';
        assert.equal(fixtureSource.split(transitionReturn).length, 2, 'three known exact reasons share one transition result');
        await add(managerPath, fixtureSource.replace(transitionReturn, transitionReturn.replace('return "source_transition"', 'return "old_source_transition"')));
        const oldTransitionZip = path.join(dir, 'old-source-transition-mutation.zip');
        await zipFolder(packageDir, oldTransitionZip);
        const oldTransitionFailure = await run(oldTransitionZip, 'positive', dir);
        requireNormal(oldTransitionFailure);
        for (const label of ['selected epoch', 'continuity window', 'selected window']) {
            assert.ok(oldTransitionFailure.output.includes(`SESSION_ASSERT_FAIL: transition classification requires exact ready reason and safe cleanup: ${label}`));
        }
        assert.throws(() => requirePositive(oldTransitionFailure, marker));
        t.diagnostic('shared transition-result mutation independently rejects all three exact native reasons');
        const selectedWindow = ' or result.helperFailureReason = "native-live: selected window crosses map or discontinuity"';
        assert.equal(fixtureSource.split(selectedWindow).length, 2, 'one exact selected-window classification seam');
        await add(managerPath, fixtureSource.replace(selectedWindow, ''));
        const selectedWindowZip = path.join(dir, 'selected-window-classification-mutation.zip');
        await zipFolder(packageDir, selectedWindowZip);
        const selectedWindowFailure = await run(selectedWindowZip, 'positive', dir);
        requireNormal(selectedWindowFailure);
        assert.match(selectedWindowFailure.output, /SESSION_ASSERT_FAIL: transition classification requires exact ready reason and safe cleanup: selected window/);
        assert.throws(() => requirePositive(selectedWindowFailure, marker));
        t.diagnostic('actual exact selected-window classifier removal is rejected normally');
        const httpStatusGate = 'if status = 401 or status = 403 or (status >= 500 and status <= 599) then return "source_transition"';
        assert.equal(fixtureSource.split(httpStatusGate).length, 2, 'one recoverable HTTP status gate');
        await add(managerPath, fixtureSource.replace(httpStatusGate, 'if status <> invalid then return "source_transition"'));
        const broadHttpZip = path.join(dir, 'broad-http-recovery-mutation.zip');
        await zipFolder(packageDir, broadHttpZip);
        const broadHttpFailure = await run(broadHttpZip, 'positive', dir);
        requireNormal(broadHttpFailure);
        assert.match(broadHttpFailure.output, /SESSION_ASSERT_FAIL: transition classification requires exact ready reason and safe cleanup: deterministic or malformed HTTP result/);
        assert.throws(() => requirePositive(broadHttpFailure, marker));
        t.diagnostic('broad recovery of deterministic HTTP failures is rejected');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolved), { code: 'ENOENT' });
    }
});
