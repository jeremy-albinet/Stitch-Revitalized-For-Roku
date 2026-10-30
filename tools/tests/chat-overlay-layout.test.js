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
const shared = path.join(__dirname, 'fixtures/ui-phase2-player');
const fixtures = path.join(__dirname, 'fixtures/chat-overlay-layout');
const prefix = 'stitch-chat-overlay-';

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

async function probe(dir, file, body) {
    const xml = await fs.readFile(path.join(root, file), 'utf8');
    const name = path.basename(file, '.xml');
    const exports = [...body.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    assert.ok(exports && xml.includes('</interface>') && xml.includes('</component>'));
    await add(dir, file, xml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', `<script uri="pkg:/components/${name}Probe.brs" /></component>`));
    await add(dir, `components/${name}Probe.brs`, body);
}

async function build(dir, marker) {
    await add(dir, 'manifest', 'title=Offline Chat Layout and UI Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const folder of ['source/utils', 'settings', 'fonts', 'images', 'locale',
        'components/SceneManager/Group', 'components/Modules/CirclePoster',
        'components/Modules/AdCountdown', 'components/Modules/EmojiLabel',
        'components/Modules/StitchVideo', 'components/Modules/CustomVideo',
        'components/Modules/TwitchContentNode', 'components/Modules/VideoErrorHandler',
        'components/Modules/Chat', 'components/Scenes/Settings', 'components/Scenes/VideoPlayer']) await tree(dir, folder);
    await copy(dir, 'source/constants.brs');
    // Only storage I/O is replaced; schema defaults and actual Settings saves run.
    let config = await fs.readFile(path.join(root, 'source/utils/config.brs'), 'utf8');
    for (const name of ['registry_read', 'registry_write', 'registry_delete']) {
        const pattern = new RegExp(`^(?:sub|function) ${name}\\b[^]*?^end (?:sub|function)\\r?$`, 'm');
        assert.match(config, pattern);
        config = config.replace(pattern, '');
    }
    await add(dir, 'source/utils/config.brs', `${config}\n${await fs.readFile(path.join(__dirname, 'fixtures/ui-account-settings/registry.brs'), 'utf8')}`);
    // No sockets, HTTP tasks or media decoder are started by these boundaries.
    for (const file of ['PhaseTwoHost.xml', 'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs',
        'TwitchApiTask.xml', 'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml', 'TwitchEngagementTask.xml']) {
        await add(dir, `components/${file}`, await fs.readFile(path.join(shared, file)));
    }
    await add(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(shared, 'EmojiLabelRegex.brs')));
    await add(dir, 'source/support.brs', (await fs.readFile(path.join(shared, 'support.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));
    await add(dir, 'source/main.brs', await fs.readFile(path.join(fixtures, 'main.brs')));
    await probe(dir, 'components/Scenes/VideoPlayer/VideoPlayer.xml', `function fixtureRead() as object
    return { task: m.PlayVideo, video: m.video, chat: m.chatWindow, worker: m.engagementTask }
end function
sub fixtureLayout()
    onChatVisibilityChange()
end sub
sub fixtureReplace()
    playContent()
end sub
function fixtureGeometry(mode as dynamic, position as dynamic, width as dynamic, height as dynamic) as object
    return chatLayoutGeometry(mode, position, true, width, height)
end function
function fixtureKey(key as string) as boolean
    return onKeyEvent(key, true)
end function
`);
    await probe(dir, 'components/Modules/Chat/Chat.xml', `function fixtureRead() as object
    return { job: m.chat, emote: m.EmoteJob, seq: m.moderationSeq, colors: m.nameColorCache.count() }
end function
`);
    const keys = `function fixtureKey(key as string) as boolean
    return onKeyEvent(key, true)
end function
`;
    for (const name of ['StitchVideo', 'CustomVideo']) {
        const preview = name === 'CustomVideo' ? 'sub fixturePreview()\n    beginSeekPreview()\nend sub\n' : '';
        await probe(dir, `components/Modules/${name}/${name}.xml`, keys + preview);
    }
    await probe(dir, 'components/Scenes/Settings/settings.xml', `${keys}
sub fixtureFocus(index as integer)
    m.settingsMenu.jumpToItem = index
    settingFocused()
end sub
sub fixtureChoose(key as string, value as string)
    item = findConfigTreeKey(key, m.configTree)
    if item = invalid then return
    LoadMenu({ title: "Fixture", children: [item] })
    settingSelected()
    for j = 0 to item.options.count() - 1
        if item.options[j].id = value
            m.optionList.checkedItem = j
            optionChanged()
            return
        end if
    end for
end sub
sub fixtureSection(section as object)
    LoadMenu(section)
end sub
`);
}

function run(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'),
            path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
        { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '';
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 45000);
        const collect = data => {
            if (exceeded) return;
            output += data.toString();
            if (Buffer.byteLength(output) > 1024 * 1024) { exceeded = true; child.kill(); }
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, output, exceeded, timedOut }); });
    });
}

test('actual player and wrappers keep full video under overlay chat; Settings saves and scroll cues follow focus', { timeout: 60000 }, async t => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const dir = path.join(temp, 'package');
        await build(dir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await run(zip, temp);
        const failure = result.output.slice(-18000);
        assert.equal(result.timedOut, false, failure);
        assert.equal(result.exceeded, false, failure);
        assert.equal(result.code, 0, `${result.signal}\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|\bERROR\b/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, failure);
        const summaries = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
        assert.equal(summaries.length, 1, failure);
        assert.ok(result.output.includes(marker) && Number(summaries[0][1]) > 0, failure);
        t.diagnostic(`${summaries[0][1]} assertions against actual callbacks; inert Task/storage boundaries; no media, pixels or hardware tested`);
    } finally {
        const absolute = path.resolve(temp);
        assert.equal(path.dirname(absolute), path.resolve(os.tmpdir()));
        assert.ok(path.basename(absolute).startsWith(prefix));
        await fs.rm(absolute, { recursive: true, force: true });
    }
});

test('all overlay settings and UI hints have complete UTF-8 translations in every supported locale', async () => {
    const tree = JSON.parse(await fs.readFile(path.join(root, 'settings/settings.json'), 'utf8'));
    const leaves = items => items.flatMap(item => item.children ? leaves(item.children) : [item]);
    const schema = leaves(tree);
    const settings = schema.filter(item => ['chat.layout', 'chat.overlayPosition', 'chat.overlayOpacity', 'ChatOption'].includes(item.settingName));
    assert.equal(settings.length, 4);
    assert.equal(settings.find(item => item.settingName === 'chat.layout').default, 'side');
    assert.equal(settings.find(item => item.settingName === 'chat.overlayPosition').default, 'bottom-right');
    assert.equal(settings.find(item => item.settingName === 'chat.overlayOpacity').default, '0.5');
    const keys = ['{0} of {1}', 'Press Down or Back to hide controls',
        'Open', ...tree.filter(item => item.children).flatMap(item => [item.title, item.description]),
        ...settings.flatMap(item => [item.title, item.description, ...(item.options || []).map(option => option.title)])];
    for (const locale of ['en_US', 'es_MX', 'pt_BR']) {
        const xml = new TextDecoder('utf-8', { fatal: true }).decode(await fs.readFile(path.join(root, 'locale', locale, 'translations.ts')));
        for (const key of keys) {
            const messages = [...xml.matchAll(/<message>\s*<source>([^]*?)<\/source>\s*<translation[^>]*>([^]*?)<\/translation>\s*<\/message>/g)]
                .filter(match => match[1] === key);
            assert.equal(messages.length, 1, `${locale}: exactly one ${key}`);
            assert.ok(messages[0][2].trim(), `${locale}: translated ${key}`);
        }
        assert.ok(!xml.includes('\ufffd'), `${locale}: no replacement characters`);
    }
});
