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
const fixtures = path.join(__dirname, 'fixtures/ui-startup-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const timeoutMs = 45000;
const outputLimit = 1024 * 1024;

async function addFile(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, data);
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

async function fixture(file) {
    return fs.readFile(path.join(fixtures, file), 'utf8');
}

// Copies a production component unchanged except for explicit, asserted XML
// boundaries and test-only inspection exports appended to its interface.
async function addComponent(dir, folder, name, probe = '', replacements = []) {
    let xml = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
    for (const [from, to] of replacements) {
        assert.ok(xml.includes(from), `${name} fixture boundary no longer matches ${from}`);
        xml = xml.replaceAll(from, to);
    }
    if (probe) {
        const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
            .map(match => `<function name="${match[1]}" />`).join('');
        xml = xml.replace('</interface>', `${exports}</interface>`)
            .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
        await addFile(dir, `components/${name}Fixture.brs`, probe);
    }
    await addFile(dir, `${folder}/${name}.xml`, xml);
    await copyFile(dir, `${folder}/${name}.brs`);
}

async function addCommon(dir, title, marker, main) {
    await addFile(dir, 'manifest', `title=${title}\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n`);
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/lifecycle.brs', 'source/utils/analytics.brs',
        'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster', 'components/Modules/AdCountdown']) await copyTree(dir, folder);
    // Explicit I/O boundaries: in-memory registry and an inert Task-shaped node.
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    await addFile(dir, 'components/TwitchApiTask.xml', await fixture('TwitchApiTask.xml'));
    await addFile(dir, 'source/main.brs', (await fixture(main)).replaceAll('__PASS_MARKER__', marker));
}

async function buildHeroPackage(dir, marker) {
    await addCommon(dir, 'Offline Startup Navigation Fixture', marker, 'hero-main.brs');
    // The cooperative owner is idle here: no local playback Task is started.
    await copyTree(dir, 'components/Modules/RokuDemuxSession');
    for (const file of ['source/utils/rokuDemuxDescriptor.brs', 'source/utils/rokuVodIndex.brs',
        'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs',
        'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs']) await copyFile(dir, file);
    for (const file of ['source/changelog.brs', 'source/utils/sceneFactory.brs', 'source/utils/contentBuilder.brs'])
        await copyFile(dir, file);
    for (const folder of ['components/SceneManager/Scene', 'components/SceneManager/Group',
        'components/Modules/MenuBar', 'components/Modules/StatusPanel', 'components/Modules/TwitchContentNode']) {
        await copyTree(dir, folder);
    }
    // brs-engine adds XML role="textFont" Font nodes as real ButtonGroup
    // children and then focuses a Font instead of a button, so OK is never
    // handled. Roku assigns role nodes to fields only; dropping the two font
    // nodes keeps the actual buttons, focus and selection path intact.
    await addComponent(dir, 'components/Modules/StatusPanel', 'StatusPanel', '', [
        ['<Font role="textFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', ''],
        ['<Font role="focusedTextFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', ''],
    ]);
    await addFile(dir, 'source/utils/recentlyWatched.brs', await fixture('recentlyWatched.brs'));
    await addFile(dir, 'components/CardBoundary.xml', await fixture('CardBoundary.xml'));
    // Settings and sign-in belong to a later phase; only their navigation
    // contract matters to the startup guard, so they are view boundaries.
    const page = await fixture('PageBoundary.xml');
    for (const name of ['Settings', 'LoginPage']) await addFile(dir, `components/${name}.xml`, page.replaceAll('__NAME__', name));

    // The whole production heroScene runs, including init, key handling and
    // disposal. fixtureRead only reads state. brs-engine reports a
    // ButtonGroupHoriz itself as its focusedChild, so focusedMenuItem() cannot
    // resolve the focused tab id; fixtureOpen calls the actual openPage that
    // menu selection reaches with that id.
    await addComponent(dir, 'components', 'heroScene', `function fixtureRead() as object
    return { task: m.getDeviceCodeTask, pending: m.deviceCodePending, failures: m.deviceCodeFailures, active: m.activeNode, footprints: m.footprints.count(), status: m.startupStatus, menu: m.menu, rail: m.recentBar }
end function
sub fixtureOpen(name as string)
    openPage(name)
end sub
`);
    await copyTree(dir, 'components/Modules/RecentlyWatchedBar');
    await addComponent(dir, 'components/Modules/RecentlyWatchedBar', 'RecentlyWatchedBar', `sub fixtureRefresh()
    onRefreshTimer()
end sub
`);
    await addComponent(dir, 'components/Scenes/Following', 'Following', `function fixtureRead() as object
    return { task: m.GetContentTask, rowlist: m.rowlist, status: m.status }
end function
`, [['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"']]);
}

async function buildPlayerPackage(dir, marker) {
    await addCommon(dir, 'Offline Player Key Fixture', marker, 'player-main.brs');
    await copyTree(dir, 'components/Modules/EmojiLabel');
    await addFile(dir, 'components/PlayerHost.xml', await fixture('PlayerHost.xml'));
    // Both wrappers run unchanged; the export only reads key-handling state.
    for (const name of ['StitchVideo', 'CustomVideo']) {
        await addComponent(dir, `components/Modules/${name}`, name, `function fixtureRead() as object
    return { overlay: m.isOverlayVisible, seekMode: m.isSeekMode = true, held: m.buttonHeld }
end function
`);
    }
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(fixtures, 'key-driver.js'), cli, zip],
            { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
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
        // Wait for the own child to close before its temp directory is removed.
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

async function runFixture(prefix, build) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await build(packageDir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-16000);
        assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
        assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
        assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary, `fresh fixture success marker missing\n${failure}`);
        assert.ok(Number(summary[1]) > 0, `fixture executed zero assertions\n${failure}`);
        return Number(summary[1]);
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith(prefix), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
}

test('first launch recovery, rail Back and root exit run the whole heroScene with real remote keys', { timeout: 60000 }, async t => {
    const count = await runFixture('stitch-ui-startup-', buildHeroPackage);
    t.diagnostic(`${count} assertions; registry/Task/card/Settings/LoginPage are inert boundaries; network, pixels and hardware remotes are not tested`);
});

test('hidden player controls act on the first Play, Rewind and Fast-forward press in both wrappers', { timeout: 60000 }, async t => {
    const count = await runFixture('stitch-ui-player-', buildPlayerPackage);
    t.diagnostic(`${count} assertions; no media is loaded, so playback state is a fixture input and decoding is not tested`);
});
