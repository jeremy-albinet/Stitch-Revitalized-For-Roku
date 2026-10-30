'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/recent-ring');

async function write(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, data);
}

async function buildPackage(dir, marker, mutation) {
    await write(dir, 'manifest', 'title=Recent Ring Geometry Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of [
        'source/constants.brs', 'source/utils/taskFactory.brs', 'source/utils/misc.brs',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.xml',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.brs',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedBar.brs',
        'components/Modules/CirclePoster/CirclePoster.xml',
        'components/Modules/CirclePoster/CirclePoster.brs',
        'images/twitch-redesign/ring-64.png', 'images/twitch-redesign/live-dot.png',
        'images/twitch-redesign/round6.9.png', 'images/icons/recent.png',
        'images/profile-mask-540.png', 'images/profile-mask-540-white.png',
        'fonts/Archivo-Bold.otf',
    ]) await write(dir, file, await fs.readFile(path.join(root, file)));
    if (mutation) {
        const file = path.join(dir, 'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.xml');
        const xml = await fs.readFile(file, 'utf8');
        assert.ok(xml.includes(mutation[0]), 'the temporary negative-control boundary must match');
        await fs.writeFile(file, xml.replace(mutation[0], mutation[1]));
    }

    // Inspection and key entry only; production geometry/handlers are unchanged.
    const bar = await fs.readFile(path.join(root, 'components/Modules/RecentlyWatchedBar/RecentlyWatchedBar.xml'), 'utf8');
    await write(dir, 'components/Modules/RecentlyWatchedBar/RecentlyWatchedBar.xml', bar
        .replace('</interface>', '<function name="fixtureRead" /><function name="fixtureKey" /><function name="fixtureRefresh" /></interface>')
        .replace('</component>', '<script uri="pkg:/components/bar-probe.brs" /></component>'));
    await write(dir, 'components/bar-probe.brs', await fs.readFile(path.join(fixtures, 'bar-probe.brs')));
    await write(dir, 'source/utils/recentlyWatched.brs', await fs.readFile(path.join(fixtures, 'boundaries.brs')));
    await write(dir, 'source/utils/config.brs', "' No registry access in this fixture.\n");
    await write(dir, 'components/TwitchApiTask.xml', `<component name="TwitchApiTask" extends="Group"><interface>
        <field id="response" type="assocarray" alwaysNotify="true" /><field id="request" type="assocarray" />
        <field id="functionName" type="string" /><field id="control" type="string" value="stop" />
        </interface></component>`);

    // Use the actual rail placement and its actual ancestor XML, omitting app
    // startup, authentication, playback, registry and network activity.
    const hero = await fs.readFile(path.join(root, 'components/heroScene.xml'), 'utf8');
    const placement = hero.match(/<RecentlyWatchedBar\b[^>]*\/>/);
    assert.ok(placement, 'the production rail placement must be present');
    await write(dir, 'components/RecentRingHost.xml', `<component name="RecentRingHost" extends="SceneManagerScene"><children>${placement[0]}</children></component>`);
    const ancestor = 'components/SceneManager/Scene/SceneManagerScene.xml';
    const sceneXml = await fs.readFile(path.join(root, ancestor), 'utf8');
    await write(dir, ancestor, sceneXml.replace(/\s*<script\b[^>]*\/>/g, ''));
    await write(dir, 'source/main.brs', (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

async function runFixture(mutation) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-recent-ring-'));
    const marker = `STITCH_RECENT_RING_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker, mutation);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        return { marker, result: await runPackage(zip, temp) };
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith('stitch-recent-ring-'));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

function checkExecution(result) {
    const detail = result.output.slice(-16000);
    assert.equal(result.timedOut, false, `recent ring fixture timed out\n${detail}`);
    assert.equal(result.exceeded, false, `recent ring fixture exceeded output limit\n${detail}`);
    assert.equal(result.code, 0, `recent ring fixture exited ${result.code} (${result.signal})\n${detail}`);
    assert.doesNotMatch(result.output, /EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, detail);
    assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${detail}`);
}

test('recent rail focus is concentric, inside item and ancestor bounds, and survives reuse', { timeout: 35000 }, async t => {
    const { marker, result } = await runFixture();
    checkExecution(result);
    assert.doesNotMatch(result.output, /STITCH_RECENT_RING_FAIL/, result.output.slice(-16000));
    const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
    assert.ok(summary && Number(summary[1]) > 0, 'fresh fixture assertions missing');
    t.diagnostic(`${summary[1]} actual SceneGraph geometry/state assertions; local history and inert Task boundary; native rendering is not tested`);
});

for (const [name, mutation, failure] of [
    ['an offset face', ['translation="[3, 3]"', 'translation="[5, 5]"'], 'ring and masked face are concentric'],
    ['negative item bounds', ['<Group id="root">', '<Group id="root" translation="[-1,-1]">'], 'the full ring stays inside the item origin'],
    ['an ancestor clip across the ring', ['<Group id="root">', '<Group id="root" clippingRect="[1,1,63,63]">'], 'the full ring fits an active ancestor clippingRect'],
]) {
    test(`recent ring geometry rejects ${name}`, { timeout: 35000 }, async () => {
        const { marker, result } = await runFixture(mutation);
        checkExecution(result);
        assert.ok(result.output.includes(`STITCH_RECENT_RING_FAIL: first row: ${failure}`), result.output.slice(-16000));
        assert.ok(!result.output.includes(marker), 'a geometry regression must not produce the fresh success marker');
    });
}
