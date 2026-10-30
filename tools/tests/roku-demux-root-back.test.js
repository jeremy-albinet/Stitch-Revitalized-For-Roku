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
const fixtures = path.join(__dirname, 'fixtures/roku-demux-root-back');
const playerFixtures = path.join(__dirname, 'fixtures/roku-demux-player');
const startupFixtures = path.join(__dirname, 'fixtures/ui-startup-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const prefix = 'stitch-roku-demux-root-back-';
const tracked = ['components/heroScene.brs', 'components/Scenes/VideoPlayer/VideoPlayer.brs',
    'components/Scenes/VideoPlayer/VideoPlayer.xml', 'components/Scenes/VideoPlayer/RokuPlayback.brs',
    'components/Modules/RokuDemuxSession/RokuDemuxSession.brs',
    'components/Modules/StitchVideo/StitchVideo.brs', 'components/Modules/StitchVideo/StitchVideo.xml'];

async function snapshots() {
    return Promise.all(tracked.map(async file => [file, createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

function run(zip, cwd, driver = path.join(playerFixtures, 'key-driver.js')) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [driver, cli, zip],
            { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '', count = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 45000);
        const collect = data => {
            if (exceeded) return;
            count += data.length;
            if (count > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => {
            clearTimeout(timer);
            resolve({ code, output, timedOut, exceeded, startupError });
        });
    });
}

function normal(result) {
    const detail = result.output.slice(-20000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    // These inherited ContentNode fields alone are unsupported by brs-node.
    const unexpected = result.output.split(/\r?\n/).filter(line => /BRIGHTSCRIPT:\s*ERROR:/i.test(line)
        && !/^BRIGHTSCRIPT: ERROR: roSGNode.AddReplace: "TwitchContentNode\.(?:Streams|streams|StreamQualities|streamqualities)": Type mismatch! pkg:\/(?:\.\/pkg:\/)?components\/Scenes\/VideoPlayer\/(?:RokuPlayback|VideoPlayer)\.brs\(\d+\)$/.test(line));
    assert.deepEqual(unexpected, [], detail);
    assert.doesNotMatch(result.output, /EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|unhandled exception|Syntax Error/i, detail);
    return detail;
}

function positive(result, marker, minimum = 109) {
    const detail = normal(result);
    assert.doesNotMatch(result.output, /ROOT_BACK_ASSERT_FAIL:|ROOT_BACK_FAIL_SUMMARY:/, detail);
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith(`${marker}:`));
    assert.equal(lines.length, 1, `expected one fresh root Back summary\n${detail}`);
    const count = lines[0].match(/:\s*(\d+) assertions\s*$/);
    assert.ok(count && Number(count[1]) >= minimum, detail);
    return Number(count[1]);
}

test('actual Hero focus escape Back preserves Player and manager cleanup ownership', { timeout: 180000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const packageDir = path.join(dir, 'package');
    const marker = `STITCH_ROOT_BACK_PASS:${randomUUID()}`;
    const before = await snapshots();
    async function add(file, data) {
        const dest = path.join(packageDir, file);
        await fs.mkdir(path.dirname(dest), { recursive: true });
        await fs.writeFile(dest, data);
    }
    async function copy(file) { await add(file, await fs.readFile(path.join(root, file))); }
    async function tree(folder) {
        for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
            const file = `${folder}/${entry.name}`;
            if (entry.isDirectory()) await tree(file);
            else await copy(file);
        }
    }
    async function component(folder, name, probe) {
        const original = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
        const source = await fs.readFile(path.join(fixtures, `${probe}.brs`), 'utf8');
        const exports = [...source.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)].map(match => `<function name="${match[1]}" />`).join('');
        const xml = original.replace('</interface>', `${exports}</interface>`)
            .replace('</component>', `<script uri="pkg:/components/${probe}.brs" /></component>`);
        await add(`${folder}/${name}.xml`, xml);
        await add(`components/${probe}.brs`, source);
        await copy(`${folder}/${name}.brs`);
    }
    try {
        for (const file of ['source/constants.brs', 'source/changelog.brs', 'source/utils/misc.brs',
            'source/utils/taskFactory.brs', 'source/utils/lifecycle.brs', 'source/utils/analytics.brs',
            'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs',
            'source/utils/sceneFactory.brs', 'source/utils/contentBuilder.brs', 'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircGifs.brs', 'source/utils/chatAnimationGif.brs',
            'source/utils/rokuDemuxDescriptor.brs', 'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs',
            'source/utils/rokuVodRuntime.brs', 'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs']) await copy(file);
        for (const folder of ['fonts', 'images', 'components/SceneManager/Scene', 'components/SceneManager/Group',
            'components/Modules/CirclePoster', 'components/Modules/MenuBar', 'components/Modules/StatusPanel',
            'components/Modules/RecentlyWatchedBar', 'components/Modules/TwitchContentNode', 'components/Modules/VideoErrorHandler',
            'components/Modules/StitchVideo', 'components/Modules/CustomVideo', 'components/Modules/AdCountdown', 'components/Modules/EmojiLabel',
            'components/Scenes/Following']) await tree(folder);
        for (const asset of ['ChatAnimationAsset.xml', 'ChatAnimationAsset.brs', 'ChatGifAtlas.brs']) await add(`components/Modules/Chat/ChatAnimationAsset/${asset}`, await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimationAsset', asset)));
        await add('source/utils/chatAnimationWebp.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
        for (const file of ['Chat.xml', 'Chat.brs', 'ChatAnimations.brs']) await copy(`components/Modules/Chat/${file}`);
        await component('components', 'heroScene', 'HeroProbe');
        await component('components/Scenes/VideoPlayer', 'VideoPlayer', 'PlayerProbe');
        await component('components/Modules/StitchVideo', 'StitchVideo', 'StitchVideoProbe');
        await copy('components/Scenes/VideoPlayer/RokuPlayback.brs');
        await copy('components/Scenes/VideoPlayer/ChatLayout.brs');
        await copy('components/Scenes/VideoPlayer/LowLatencyPlayback.brs');
        await copy('components/Scenes/VideoPlayer/ChannelFollow.brs');
        await copy('components/Scenes/VideoPlayer/ContentAdvisory.brs');
        await component('components/Modules/RokuDemuxSession', 'RokuDemuxSession', 'ManagerProbe');
        const worker = 'CreateObject("roSGNode", "RokuDemuxServer")';
        const managerPath = 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs';
        const actualManager = await fs.readFile(path.join(root, managerPath), 'utf8');
        assert.equal(actualManager.split(worker).length, 2);
        await add(managerPath, actualManager.replace(worker, 'CreateObject("roSGNode", "RootWorkerBoundary")'));
        await add('components/RootWorkerBoundary.xml', `<component name="RootWorkerBoundary" extends="Group"><interface>
          <field id="sessionId" type="string" /><field id="inputDescriptor" type="assocarray" />
          <field id="experimentalMode" type="boolean" /><field id="cacheBudgetBytes" type="integer" />
          <field id="listenPort" type="integer" /><field id="functionName" type="string" />
          <field id="control" type="string" onChange="onControl" /><field id="state" type="string" alwaysNotify="true" />
          <field id="ready" type="assocarray" alwaysNotify="true" /><field id="result" type="assocarray" alwaysNotify="true" />
          <field id="stopRequested" type="boolean" /></interface><script uri="RootWorkerBoundary.brs" /></component>`);
        await add('components/RootWorkerBoundary.brs', 'sub onControl()\n    if m.top.control = "run" then m.top.state = "run"\n    if m.top.control = "stop" then m.top.state = "stop"\nend sub\n');
        await add('source/utils/config.brs', await fs.readFile(path.join(startupFixtures, 'config.brs')));
        await add('source/utils/recentlyWatched.brs', await fs.readFile(path.join(startupFixtures, 'recentlyWatched.brs')));
        for (const file of ['TwitchApiTask.xml', 'RW_AddTask.xml', 'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs',
            'ChatJob.xml', 'EmoteJob.xml']) await add(`components/${file}`, await fs.readFile(path.join(playerFixtures, file)));
        await add('components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(playerFixtures, 'EmojiLabelRegex.brs')));
        const page = await fs.readFile(path.join(startupFixtures, 'PageBoundary.xml'), 'utf8');
        for (const name of ['Settings', 'LoginPage', 'Browse', 'Search', 'ChannelPage', 'GamePage']) await add(`components/${name}.xml`, page.replaceAll('__NAME__', name));
        await add('components/CardBoundary.xml', await fs.readFile(path.join(startupFixtures, 'CardBoundary.xml')));
        const followingXml = 'components/Scenes/Following/Following.xml';
        await add(followingXml, (await fs.readFile(path.join(root, followingXml), 'utf8')).replace('itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"'));
        const statusXml = 'components/Modules/StatusPanel/StatusPanel.xml';
        await add(statusXml, (await fs.readFile(path.join(root, statusXml), 'utf8'))
            .replace('<Font role="textFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', '')
            .replace('<Font role="focusedTextFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', ''));
        await add('manifest', 'title=Offline Root Back Composition\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const main = await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8');
        for (const mode of ['positive', 'assertion']) {
            await add('source/main.brs', main.replace('__PASS_MARKER__', marker)
                .replace('__NEGATIVE_CONTROL__', mode === 'assertion' ? 'yes' : 'no'));
            const zip = path.join(dir, `${mode}.zip`);
            await zipFolder(packageDir, zip);
            const result = await run(zip, dir);
            if (mode === 'positive') {
                const count = positive(result, marker);
                t.diagnostic(`${count} actual composed Hero/Player/manager assertions with real key focus dispatch; inert worker and media state`);
                assert.throws(() => positive(result, 'STALE_MARKER'), /expected one fresh root Back summary/);
                for (const control of [{ timedOut: true }, { exceeded: true }, { code: 1 }]) assert.throws(() => positive({ ...result, ...control }, marker));
            } else {
                normal(result);
                const failures = result.output.split(/\r?\n/).filter(line => line.startsWith('ROOT_BACK_ASSERT_FAIL:'));
                assert.deepEqual(failures, ['ROOT_BACK_ASSERT_FAIL: deliberate reversed assertion']);
                assert.doesNotMatch(result.output, new RegExp(marker));
                assert.throws(() => positive(result, marker), /ROOT_BACK_ASSERT_FAIL/);
            }
        }
        assert.deepEqual(await snapshots(), before, 'production sources must remain frozen throughout runs');
        t.diagnostic('complete ownership scenarios pass; reversed assertion, stale-marker, timeout and output-limit controls rejected');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolved), { code: 'ENOENT' });
    }
});
