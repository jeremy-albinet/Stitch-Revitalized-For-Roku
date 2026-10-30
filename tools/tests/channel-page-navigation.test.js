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
const fixtures = path.join(__dirname, 'fixtures/channel-page-navigation');

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
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    xml = xml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
    await addFile(dir, `${folder}/${name}.xml`, xml);
    await copyFile(dir, `${folder}/${name}.brs`);
    await addFile(dir, `components/${name}Fixture.brs`, probe);
}

async function buildPackage(dir, marker, mainFile = 'main.brs') {
    await addFile(dir, 'manifest', 'title=ChannelPage Navigation Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/contentBuilder.brs', 'source/utils/sceneFactory.brs', 'source/utils/lifecycle.brs',
        'components/SceneManager/Group/SceneManagerGroup.xml', 'components/SceneManager/Group/SceneManagerGroup.brs',
        'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.xml', 'components/Modules/RecentlyWatchedBar/RecentlyWatchedItem.brs',
    ]) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/StatusPanel', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoItem', 'components/Modules/EmojiLabel', 'components/Modules/CirclePoster',
        'components/Modules/MenuBar/ButtonGroupHoriz',
    ]) await copyTree(dir, folder);
    // Reuse the existing offline I/O and unsupported widget/regex boundaries.
    for (const file of ['config.brs', 'recentlyWatched.brs', 'task.brs', 'TwitchApiTask.xml', 'InfoBoundary.xml']) {
        const dest = ['config.brs', 'recentlyWatched.brs'].includes(file) ? `source/utils/${file}` : `components/${file}`;
        await addFile(dir, dest, await fs.readFile(path.join(__dirname, 'fixtures/ui', file)));
    }
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs',
        await fs.readFile(path.join(__dirname, 'fixtures/ui-phase2-player/EmojiLabelRegex.brs')));
    for (const file of ['scene.brs', 'FixtureScene.xml']) {
        await addFile(dir, `components/${file}`, await fs.readFile(path.join(fixtures, file)));
    }
    let main = await fs.readFile(path.join(fixtures, mainFile), 'utf8');
    if (mainFile !== 'main.brs') {
        const navigation = await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8');
        const helpers = navigation.indexOf('function fixtureResponse()');
        assert.ok(helpers > 0, 'shared fixture response and assertion helpers are present');
        main += `\n${navigation.slice(helpers)}`;
    }
    await addFile(dir, 'source/main.brs', main.replaceAll('__PASS_MARKER__', marker));

    await addComponent(dir, 'components/Scenes/ChannelPage', 'ChannelPage', `function fixtureRead() as object
    return { task: m.GetContentTask, rowlist: m.rowlist }
end function
`, [['<SimpleLabel', '<Label'], ['<InfoPane', '<InfoBoundary'], ['fontSize="32"', ''], ['fontSize="20"', ''],
        ['fontUri="pkg:/fonts/Archivo-Bold.otf"', ''], ['fontUri="pkg:/fonts/Archivo-Regular.otf"', '']]);
    await addComponent(dir, 'components/Scenes/Following', 'Following', `function fixtureRead() as object
    return { task: m.GetContentTask, rowlist: m.rowlist, status: m.status }
end function

sub fixtureDeliverFocusChange()
    onGetFocus()
end sub
`);
    // The generated thumbnail uses a local image; production URL behavior has
    // separate assertions in ui-behavior. No network requests are needed here.
    const channelPath = 'components/Scenes/ChannelPage/ChannelPage.brs';
    const channelSource = await fs.readFile(path.join(root, channelPath), 'utf8');
    assert.ok(channelSource.includes('https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-1280x720.jpg'));
    await addFile(dir, channelPath, channelSource.replaceAll(
        'https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-1280x720.jpg', 'pkg:/images/default_banner.png'));
    await addComponent(dir, 'components/Modules/MenuBar', 'MenuBar', '');
    await addComponent(dir, 'components/Modules/RecentlyWatchedBar', 'RecentlyWatchedBar', `function fixtureSelect() as boolean
    return onKeyEvent("OK", true)
end function
`);
    // Only register references to the actual cards created by the actual
    // RowList; leave init/showcontent and all focus/key handlers intact.
    const cardPath = 'components/Modules/VideoItem/VideoItem.brs';
    const cardSource = await fs.readFile(path.join(root, cardPath), 'utf8');
    assert.match(cardSource, /^sub init\(\)/);
    await addFile(dir, cardPath, cardSource.replace('sub init()', `sub init()
    fixtureCards = m.global.fixtureCards
    fixtureCards.push(m.top)
    m.global.fixtureCards = fixtureCards`));

    // Extract complete, current heroScene navigation functions. Playback is an
    // inert output boundary, so first OK can be inspected without starting video.
    const hero = await fs.readFile(path.join(root, 'components/heroScene.brs'), 'utf8');
    const actual = ['buildNode', 'discardScene', 'teardownAllScenes', 'onRecentSelected', 'onBackPressed', 'focusedMenuItem'].map(name => {
        const match = hero.match(new RegExp(`^(?:sub|function)\\s+${name}\\b[^\\n]*\\n[\\s\\S]*?^end (?:sub|function)\\s*$`, 'im'));
        assert.ok(match, `production function missing: ${name}`);
        return match[0];
    }).join('\n\n');
    await addFile(dir, 'components/HeroActual.brs', actual);
}

async function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'),
            path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true });
        let output = '';
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
        const collect = data => {
            if (exceeded) return;
            output += data.toString();
            if (Buffer.byteLength(output) > 1024 * 1024) { exceeded = true; child.kill(); }
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

test('Recents opens one ChannelPage with an owned LIVE card, first OK and one Back', { timeout: 35000 }, async t => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-channel-navigation-'));
    const marker = `STITCH_CHANNEL_NAV_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-16000);
        assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
        assert.equal(result.exceeded, false, `fixture output exceeded limit\n${failure}`);
        assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_CHANNEL_NAV_FAIL:|FIXTURE_DRIVER_ERROR:|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, failure);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary && Number(summary[1]) >= 10, `fresh regression success marker missing\n${failure}`);
        t.diagnostic(`${summary[1]} actual navigation/RowList/VideoItem assertions; no device, registry, network or video playback`);
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith('stitch-channel-navigation-'));
        await fs.rm(resolved, { recursive: true, force: true });
    }
});

test('retained Following focus callbacks and late responses preserve profile input and deferred refresh', { timeout: 60000 }, async t => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-following-focus-'));
    const marker = `STITCH_FOLLOWING_FOCUS_PASS:${randomUUID()}`;
    const followingPath = 'components/Scenes/Following/Following.brs';
    const source = await fs.readFile(path.join(root, followingPath), 'utf8');
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker, 'retained-following.brs');
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-18000);
        assert.equal(result.timedOut, false, failure);
        assert.equal(result.exceeded, false, failure);
        assert.equal(result.code, 0, failure);
        assert.doesNotMatch(result.output, /STITCH_CHANNEL_NAV_FAIL:|FIXTURE_DRIVER_ERROR:|EXIT_BRIGHTSCRIPT_CRASH|BRIGHTSCRIPT:\s*ERROR:|failed to set up component|runtime error|BrightScript Debugger/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, failure);
        const summaries = [...result.output.matchAll(new RegExp(`${marker}:\\s*(\\d+) assertions`, 'g'))];
        assert.equal(summaries.length, 1, failure);
        assert.equal((result.output.match(/FOLLOWING_FOCUS_CASE:/g) || []).length, 9, failure);
        assert.ok(Number(summaries[0][1]) >= 128, failure);
        t.diagnostic(`${summaries[0][1]} actual Following/ChannelPage/StatusPanel/Hero assertions across anonymous and signed-in mock responses; explicit native focus-loss callback ordering`);

        // Restore the pre-fix callback in the temporary package only. This
        // must reproduce lost profile OK and Back through the real input path.
        const guard = /    if not m\.top\.IsInFocusChain\(\)\r?\n        updateRowListFocusFeedback\(\)\r?\n        return\r?\n    end if\r?\n/;
        assert.match(source, guard);
        await addFile(packageDir, followingPath, source.replace(guard, ''));
        const negativeZip = path.join(temp, 'no-focus-guard.zip');
        await zipFolder(packageDir, negativeZip);
        const negative = await runPackage(negativeZip, temp);
        const detail = negative.output.slice(-18000);
        assert.equal(negative.timedOut, false, detail);
        assert.equal(negative.exceeded, false, detail);
        assert.equal(negative.code, 0, detail);
        assert.doesNotMatch(negative.output, /EXIT_BRIGHTSCRIPT_CRASH|BRIGHTSCRIPT:\s*ERROR:|runtime error|BrightScript Debugger/i, detail);
        assert.match(negative.output, /STITCH_CHANNEL_NAV_FAIL:retained Following focus-loss callback cannot reclaim input/, detail);
        assert.match(negative.output, /STITCH_CHANNEL_NAV_FAIL:first real OK on the loaded profile selects its playable LIVE card/, detail);
        assert.match(negative.output, /STITCH_CHANNEL_NAV_FAIL:one real Back returns input from profile to retained Following/, detail);
        assert.ok(!negative.output.includes(marker), detail);
        assert.equal(await fs.readFile(path.join(root, followingPath), 'utf8'), source, 'negative control never changes production Following');
        t.diagnostic('pre-fix negative control loses visible profile focus, first LIVE OK and one Back; removing only the ownership guard reproduces the failure');
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith('stitch-following-focus-'));
        await fs.rm(resolved, { recursive: true, force: true });
    }
});
