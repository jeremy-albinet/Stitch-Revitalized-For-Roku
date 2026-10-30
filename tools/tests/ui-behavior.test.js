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
const fixtures = path.join(__dirname, 'fixtures/ui');
const timeoutMs = 25000;
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

async function addComponent(dir, folder, name, probe, replacements = []) {
    let xml = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
    for (const [from, to] of replacements) {
        assert.ok(xml.includes(from), `${name} fixture boundary no longer matches ${from}`);
        xml = xml.replaceAll(from, to);
    }
    const extraExports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    xml = xml.replace('</interface>', `${extraExports}<function name="fixtureKey" /><function name="fixtureCleanup" /></interface>`)
        .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
    await addFile(dir, `${folder}/${name}.xml`, xml);
    // Production bodies stay unchanged. Inspection exports exist only in this package.
    await copyFile(dir, `${folder}/${name}.brs`);
    await addFile(dir, `components/${name}Fixture.brs`, `${probe}
function fixtureKey(key as string, press = true as boolean) as boolean
    return onKeyEvent(key, press)
end function
sub fixtureCleanup()
    onDestroy()
end sub
`);
}

async function selectFunctions(file, names) {
    const source = await fs.readFile(path.join(root, file), 'utf8');
    return names.map(name => {
        const match = source.match(new RegExp(`^(?:sub|function)\\s+${name}\\b[^\\n]*\\n[\\s\\S]*?^end (?:sub|function)\\s*$`, 'im'));
        assert.ok(match, `production function missing: ${name}`);
        return match[0];
    }).join('\n\n');
}

async function buildPackage(dir, marker) {
    await addFile(dir, 'manifest', 'title=Offline UI Regression Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of [
        'source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/contentBuilder.brs', 'source/utils/sceneFactory.brs', 'source/utils/lifecycle.brs',
        'components/SceneManager/Group/SceneManagerGroup.xml',
        'components/SceneManager/Group/SceneManagerGroup.brs',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.xml',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.brs',
    ]) await copyFile(dir, file);
    for (const folder of [
        'fonts', 'images', 'components/Modules/StatusPanel', 'components/Modules/TwitchContentNode', 'components/Modules/VideoItem', 'components/Modules/EmojiLabel',
        'components/Modules/CirclePoster', 'components/Modules/MenuBar/ButtonGroupHoriz',
    ]) await copyTree(dir, folder);
    // The interpreter cannot compile the native Unicode emoji regex. Keep the
    // actual label/card handlers and use the existing pattern-source boundary.
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs',
        await fs.readFile(path.join(__dirname, 'fixtures/ui-phase2-player/EmojiLabelRegex.brs')));

    // These are explicit I/O/view boundaries, never substitute tested handlers.
    // Native Task worker startup can crash in canvas; Groups retain real native
    // fields/observers and exercise the production createApiTask/destroyTask code.
    for (const file of ['config.brs', 'task.brs', 'keyboard.brs', 'recentlyWatched.brs', 'scene.brs',
        'TwitchApiTask.xml', 'CardBoundary.xml', 'InfoBoundary.xml', 'KeyboardBoundary.xml', 'FixtureScene.xml']) {
        const dest = file === 'config.brs' || file === 'recentlyWatched.brs'
            ? `source/utils/${file}` : `components/${file}`;
        await addFile(dir, dest, await fs.readFile(path.join(fixtures, file)));
    }
    await addFile(dir, 'source/main.brs', (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));

    const rowBoundary = ['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"'];
    const detailProbe = `function fixtureRead() as object
    return { task: m.GetContentTask, shell: m.GetShellTask, disposed: m.disposed, rowlist: m.rowlist, status: m.status, signedIn: m.signedIn }
end function
sub fixtureSelect(row as integer)
    ' Only the read-only RowList selection fields are an input boundary.
    original = m.rowlist
    m.rowlist = { content: original.content, focusedChild: { id: "fixture" }, rowItemSelected: [row, 0] }
    handleItemSelected()
    m.rowlist = original
end sub
`;
    for (const name of ['Following', 'GamePage', 'ChannelPage']) {
        const replacements = [rowBoundary];
        if (name === 'ChannelPage') {
            // brs-engine does not implement these profile widgets. Their native
            // field boundaries keep the actual response/shell handlers runnable.
            replacements.push(['<SimpleLabel', '<Label'], ['<InfoPane', '<InfoBoundary'],
                ['fontSize="32"', ''], ['fontSize="20"', ''],
                ['fontUri="pkg:/fonts/Archivo-Bold.otf"', ''], ['fontUri="pkg:/fonts/Archivo-Regular.otf"', '']);
        }
        await addComponent(dir, `components/Scenes/${name}`, name, detailProbe, replacements);
    }
    await addComponent(dir, 'components/Scenes/Browse', 'Browse', `function fixtureRead() as object
    return { featured: m.featuredTask, categories: m.categoriesTask, live: m.liveTask, disposed: m.disposed, rowlist: m.rowlist, status: m.status, failed: m.sectionsFailed, liveBuffering: m.liveBuffering }
end function
sub fixtureMore()
    appendMoreLive()
end sub
`, [rowBoundary]);
    await addComponent(dir, 'components/Scenes/Search', 'Search', `function fixtureRead() as object
    return { task: m.GetContentTask, disposed: m.disposed, rowlist: m.rowlist, status: m.searchStatus, timer: m.searchTimer, kb: m.kb, recents: m.recents }
end function
`, [rowBoundary, ['<DynamicMiniKeyboard', '<KeyboardBoundary']]);
    await addComponent(dir, 'components/Modules/MenuBar', 'MenuBar', `function fixtureRead() as object
    return { tabs: m.menuOptions, icons: m.iconOptions, caption: m.iconCaption, label: m.iconCaptionLabel, disposed: m.disposed, loginTask: m.loginIconTask, profileId: get_user_setting("id", "") }
end function
`);
    await addComponent(dir, 'components/Modules/RecentlyWatchedBar', 'RecentlyWatchedBar', `function fixtureRead() as object
    return { items: m.items, index: m.currentIndex, caption: m.caption, label: m.captionLabel, task: m.liveStatusTask, timer: m.refreshTimer, disposed: m.disposed }
end function
sub fixtureRefresh()
    onRefreshTimer()
end sub
`);
    // Only actual complete navigation functions are extracted. Startup/auth and
    // playback remain outside this fixture; no copied navigation implementation.
    await addFile(dir, 'components/HeroActual.brs', await selectFunctions('components/heroScene.brs', [
        'buildNode', 'discardScene', 'teardownAllScenes', 'openPage', 'onMenuRequest',
        'isContentTab', 'hideStartupStatus', 'showChangelogDialog',
    ]));
}

async function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true });
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
        // Wait for own child to close before removing its package/temp directory.
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

test('offline UI states, navigation, focus and disposal execute current SceneGraph handlers', { timeout: 35000 }, async t => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-ui-'));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-16000);
        assert.equal(result.timedOut, false, `UI fixture timed out\n${failure}`);
        assert.equal(result.exceeded, false, `UI fixture exceeded output limit\n${failure}`);
        assert.equal(result.code, 0, `UI fixture exited ${result.code} (${result.signal})\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, `UI fixture did not close normally\n${failure}`);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary, `fresh UI fixture success marker missing\n${failure}`);
        assert.ok(Number(summary[1]) > 0, `UI fixture executed zero assertions\n${failure}`);
        t.diagnostic(`${summary[1]} current-source assertions; Task/registry/card/keyboard boundaries are inert; pixels/network/video are not tested`);
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith('stitch-ui-'), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
});
