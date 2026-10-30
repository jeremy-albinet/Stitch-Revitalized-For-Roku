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
const fixtures = path.join(__dirname, 'fixtures/ui-phase2-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
// The tracked engine key driver shared with the phase-one player fixture.
const keyDriver = path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js');
const timeoutMs = 60000;
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

// Copies a production component unchanged except for read-only inspection
// exports appended to its interface. The probe only reads state or calls the
// component's own handlers; it never replaces production code.
async function addComponent(dir, folder, name, probe = '', xmlName = name) {
    let xml = await fs.readFile(path.join(root, folder, `${xmlName}.xml`), 'utf8');
    if (probe) {
        const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
            .map(match => `<function name="${match[1]}" />`).join('');
        assert.ok(exports, `${name} probe has no fixture exports`);
        xml = xml.replace('</interface>', `${exports}</interface>`)
            .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
        await addFile(dir, `components/${name}Fixture.brs`, probe);
    }
    await addFile(dir, `${folder}/${xmlName}.xml`, xml);
    await copyFile(dir, `${folder}/${xmlName}.brs`);
}

async function addCommon(dir, title, marker, main) {
    await addFile(dir, 'manifest', `title=${title}\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n`);
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircGifs.brs', 'source/utils/chatAnimationGif.brs',
        'components/Modules/Chat/ChatAnimations.brs',
        'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster', 'components/Modules/AdCountdown']) await copyTree(dir, folder);
    for (const asset of ['ChatAnimationAsset.xml', 'ChatAnimationAsset.brs', 'ChatGifAtlas.brs']) await addFile(dir, `components/Modules/Chat/ChatAnimationAsset/${asset}`, await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimationAsset', asset)));
    await addFile(dir, 'source/utils/chatAnimationWebp.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
    // Explicit I/O boundary: an in-memory registry on the global node.
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    await addFile(dir, 'components/PhaseTwoHost.xml', await fixture('PhaseTwoHost.xml'));
    await addFile(dir, 'source/support.brs', (await fixture('support.brs')).replaceAll('__PASS_MARKER__', marker));
    await addFile(dir, 'source/main.brs', await fixture(main));
}

// EmojiLabel runs unchanged; only its pattern source is the engine boundary.
async function addEmojiLabel(dir, probe = '') {
    await addComponent(dir, 'components/Modules/EmojiLabel', 'EmojiLabel', probe);
    await copyFile(dir, 'components/Modules/EmojiLabel/EmojiLabelUtil.brs');
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fixture('EmojiLabelRegex.brs'));
}

// brs-engine implements JS regex rather than Roku PCRE. Convert the actual
// versioned pattern to equivalent UTF-16 alternatives; no subset emoji stub.
// Native Rooibos separately compiles the production PCRE without this adapter.
function engineEmojiPattern(source) {
    const native = source.match(/return "([^"\r\n]+)"/)[1];
    const escape = point => {
        const text = String.fromCodePoint(point);
        return Array.from({ length: text.length }, (_, i) => `\\u${text.charCodeAt(i).toString(16).padStart(4, '0')}`).join('');
    };
    let converted = native.replace(/\[([^\]]*\\x\{[^\]]*)\]/g, (_, body) => {
        const tokens = body.match(/\\x\{[\da-f]+\}|\\.|./gi);
        const point = token => token.startsWith('\\x{') ? parseInt(token.slice(3, -1), 16) : token.replace(/^\\/, '').codePointAt(0);
        const alternatives = [];
        for (let i = 0; i < tokens.length; i++) {
            const start = point(tokens[i]);
            const end = tokens[i + 1] === '-' ? point(tokens[i += 2]) : start;
            for (let cp = start; cp <= end; cp++) alternatives.push(escape(cp));
        }
        return `(?:${alternatives.join('|')})`;
    });
    converted = converted.replace(/\\x\{([\da-f]+)\}/gi, (_, point) => escape(parseInt(point, 16)));
    // Compare the adapter against the actual scalar PCRE escapes in JS Unicode
    // mode before handing it to the engine's non-Unicode regex implementation.
    const unicode = native.replace(/\\x\{([\da-f]+)\}/gi, '\\u{$1}');
    for (const sample of ['hello\u{1f600}world', '\u2764\ufe0f', '\u{1f44d}\u{1f3fd}',
        '\u{1f468}\u200d\u{1f469}\u200d\u{1f467}\u200d\u{1f466}', '\u{1f1fa}\u{1f1f8}',
        '1\ufe0f\u20e3', '\u{1f600}\u{1f600}', '\u{1f3f3}\ufe0f\u200d\u{1f308}',
        '\u{1fae8}\u{1fa77}', 'abc 123 #* caf\u00e9 \u4f60\u597d']) {
        assert.deepEqual([...sample.matchAll(new RegExp(converted, 'g'))].map(m => m[0]),
            [...sample.matchAll(new RegExp(unicode, 'gu'))].map(m => m[0]), `UTF-16 adapter differs for ${sample}`);
    }
    return `' Actual production pattern adapted to the simulator's UTF-16 JS regex engine.\nfunction emojiRegexSource() as string\n    if m.fixtureBuilds = invalid then m.fixtureBuilds = 0\n    m.fixtureBuilds += 1\n    return "${converted}"\nend function\n`;
}

async function buildEmojiRenderPackage(dir, marker) {
    await addCommon(dir, 'Chat Emoji Renderer Fixture', marker, 'chat-main.brs');
    const folder = path.join(__dirname, 'fixtures/chat-emotes');
    await addFile(dir, 'source/main.brs', await fs.readFile(path.join(folder, 'main.brs')));
    await copyFile(dir, 'source/utils/ircParser.brs');
    for (const file of ['ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    await addEmojiLabel(dir, await fs.readFile(path.join(folder, 'EmojiProbe.brs'), 'utf8'));
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs',
        engineEmojiPattern(await fs.readFile(path.join(root, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs'), 'utf8')));
    await addComponent(dir, 'components/Modules/Chat', 'Chat', await fs.readFile(path.join(folder, 'ChatProbe.brs'), 'utf8'));
}

const wrapperProbes = {
    StitchVideo: `function fixtureRead() as object
    return { overlay: m.isOverlayVisible, focused: m.currentFocusedButton, caption: m.captionLabel.text, captionVisible: m.caption.visible, controlsX: m.controls.translation[0], scrimWidth: m.scrim.width, tagVisible: m.latencyTag.visible, tagText: m.latencyTag.text, live: m.top.findNode("liveLabel").text, dialogVisible: m.qualityDialog.visible, dialogTitle: m.qualityDialog.title, dialogMessage: m.qualityDialog.message, dialogButtons: m.qualityDialog.buttons, dialog: m.qualityDialog, ownsDialog: m.top.getScene().dialog <> invalid, fade: m.fadeAwayTimer.control, focusedChild: m.top.focusedChild }
end function
`,
    CustomVideo: `function fixtureRead() as object
    return { overlay: m.isOverlayVisible, seekMode: m.isSeekMode = true, held: m.buttonHeld, preview: m.currentPositionSeconds, focused: m.currentFocusedButton, hint: m.seekHint.text, hintVisible: m.seekHint.visible, infoVisible: m.infoRow.visible, caption: m.captionLabel.text, captionVisible: m.caption.visible, knob: m.progressDot.color, position: m.timeProgress.text, controlsX: m.controls.translation[0], timeTravelOpen: m.isTimeTravelDialogOpen, lengthText: m.timeTravelLength.text }
end function

sub fixtureObserveHold()
    m.fixtureHoldProgress = []
    m.timeProgress.observeField("text", "fixtureOnHoldProgress")
end sub
sub fixtureOnHoldProgress()
    events = m.fixtureHoldProgress
    events.push({ data: m.timeProgress.text, duration: m.buttonHoldTimer.duration })
    m.fixtureHoldProgress = events
end sub
function fixtureFinishHold() as object
    m.timeProgress.unobserveField("text")
    return m.fixtureHoldProgress
end function
`,
};

async function addWrappers(dir, probes) {
    for (const name of ['StitchVideo', 'CustomVideo']) {
        await addComponent(dir, `components/Modules/${name}`, name, probes ? wrapperProbes[name] : '');
    }
}

async function buildWrappersPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Player Fixture', marker, 'wrappers-main.brs');
    await addEmojiLabel(dir);
    await addWrappers(dir, true);
}

async function buildRetryPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Retry Fixture', marker, 'retry-main.brs');
    await addEmojiLabel(dir);
    await addWrappers(dir, false);
    for (const folder of ['components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler']) await copyTree(dir, folder);
    await copyFile(dir, 'components/Modules/Chat/Chat.xml');
    await copyFile(dir, 'components/Modules/Chat/Chat.brs');
    // Inert task boundaries with the production interfaces: no worker,
    // network, socket or registry writes.
    for (const file of ['GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml', 'TwitchEngagementTask.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    await addComponent(dir, 'components/Scenes/VideoPlayer', 'VideoPlayer', `function fixtureRead() as object
    return { task: m.PlayVideo, video: m.video, pending: m.manualRetryPending <> invalid and m.manualRetryPending, dialog: m.errorDialog, recovery: m.recoveryAttempts, reconnect: m.reconnectAttempts, retryTimer: m.retryTimer, reconnectTask: m.reconnectTask, bookmarksTask: m.bookmarksTask, bookmarkPending: m.bookmarkPlayPending = true, bookmarkTimer: m.bookmarkWaitTimer }
end function
sub fixtureResume(position as integer)
    m.resumePosition = position
    playContent()
end sub
sub fixtureButtonAgain()
    onErrorDialogButton()
end sub
sub fixtureRetryAgain()
    retryAfterError()
end sub
sub fixtureSpendRecovery(count as integer)
    m.recoveryAttempts = count
    m.reconnectAttempts = count
end sub
function fixtureEngagement() as object
    return { worker: m.engagementTask, owner: m.engagementOwner, generation: m.engagementGeneration, paused: m.engagementPaused, chat: m.chatWindow, autoPaused: m.chatAutoPaused }
end function
sub fixtureRecovery(reason as string)
    beginLiveReconnect(reason)
end sub
`);
    await copyFile(dir, 'components/Scenes/VideoPlayer/RokuPlayback.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ChatLayout.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/LowLatencyPlayback.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ChannelFollow.brs');
    await copyFile(dir, 'components/Scenes/VideoPlayer/ContentAdvisory.brs');
    for (const file of ['source/utils/recentlyWatched.brs', 'source/utils/rokuDemuxDescriptor.brs', 'source/utils/rokuVodIndex.brs',
        'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs',
        'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs']) await copyFile(dir, file);
}

async function buildEngagementPackage(dir, marker) {
    await buildRetryPackage(dir, marker);
    const helpers = await fixture('retry-main.brs');
    const bodies = ['request', 'playable', 'openPlayer', 'closePlayer', 'contentTask', 'waitTasks', 'waitVideo'].map(name => {
        const match = helpers.match(new RegExp(`^(?:sub|function) ${name}\\([^\\n]*\\r?\\n[\\s\\S]*?^end (?:sub|function)(?=\\r?$)`, 'm'));
        assert.ok(match, `existing player fixture helper missing: ${name}`);
        return match[0];
    });
    await addFile(dir, 'source/main.brs', [await fixture('engagement-main.brs'), ...bodies].join('\n'));
}

async function buildChatPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Chat Fixture', marker, 'chat-main.brs');
    await addComponent(dir, 'components/Modules/Chat', 'Chat', `function fixtureNameColor(color as dynamic) as dynamic
    return buildUsername("viewer", color).color
end function
function fixtureLinkColor() as dynamic
    return wordOrImage("https://example.com", true).color
end function
function fixtureCached() as integer
    return m.nameColorCache.count()
end function
function fixtureStatus(state as string) as string
    updateChatStatus(state)
    return m.chatStatus.text
end function
`);
    await addEmojiLabel(dir, `function fixtureRead() as object
    builds = 0
    if m.fixtureBuilds <> invalid then builds = m.fixtureBuilds
    return { builds: builds, compiled: m.emojiRegex <> invalid, failed: m.emojiRegexFailed = true, parts: m.components.getChildCount(), scrolling: m.animation.control = "start", pending: m.scrollStartPending = true, duration: m.animation.duration, cycleDuration: m.timer.duration }
end function
sub fixtureFailCompile()
    m.fixtureFail = true
end sub
sub fixtureScrollStart()
    onScrollStart()
end sub
function fixtureCompile() as boolean
    return emojiPattern() <> invalid
end function
function fixtureText() as string
    text = ""
    for i = 0 to m.components.getChildCount() - 1
        child = m.components.getChild(i)
        if child.subtype() = "Label" then text = text + child.text
    end for
    return text
end function
`);
}

async function buildModerationPackage(dir, marker) {
    await addCommon(dir, 'Chat Moderation Fixture', marker, 'chat-main.brs');
    await addFile(dir, 'source/support.brs', ''); // This fixture supplies its own assertion and port helpers.
    await addFile(dir, 'source/main.brs', (await fs.readFile(path.join(__dirname, 'fixtures/chat-moderation/main.brs'), 'utf8')).replace('__PASS_MARKER__', marker));
    await addFile(dir, 'components/ModerationHost.xml', '<component name="ModerationHost" extends="Scene" />');
    await copyFile(dir, 'source/utils/ircParser.brs');
    await addEmojiLabel(dir);
    for (const file of ['ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    await addComponent(dir, 'components/Modules/Chat', 'Chat', `function fixtureJob() as dynamic
    return m.chat
end function
function fixtureRead() as object
    rows = []
    for each message in m.chatPanel.getChildren(-1, 0)
        identity = message.chatIdentity
        rows.push({ id: identity.id, userId: identity.userId, login: identity.login, advance: message.chatAdvance, y: message.translation[1], text: fixtureText(message), posters: fixturePosters(message), parts: message.getChildCount() })
    end for
    age = -1
    if m.hypeAge <> invalid then age = m.hypeAge.totalMilliseconds()
    return { rows: rows, seq: m.moderationSeq, translation: m.translation, start: m.lower_bound - m.line_height, job: m.chat <> invalid, emoteJob: m.EmoteJob, emoteChannel: m.emoteChannel, presentation: m.chatPresentationState, statusVisible: m.chatStatus.visible, status: m.chatStatus.text, hypeVisible: m.hypePanel.visible, hypeTitle: m.hypeTitle.text, hypeDetail: m.hypeDetail.text, hypeProgress: m.hypeProgress.width, hypeTimer: m.hypeTimer, hypeAgeMs: age, pinVisible: m.pinPanel.visible, pinText: m.pinText.text, pinAuthor: m.pinAuthor.text, pinY: m.pinPanel.translation[1], pinTimer: m.pinTimer, pinDialog: m.pinDialog }
end function
sub fixtureStaleEvent(job as object)
    event = { node: job, getRoSGNode: fixtureEventNode }
    onNewCommentObj(event)
    onModeration(event)
    onConnectionStateChange(event)
    onDeliveryStateChange(event)
    onEmotesCompleted(event)
end sub
function fixtureEventNode() as object
    return m.node
end function
sub fixtureTryRender(comment as object)
    m.chat.nextCommentObj = comment
end sub
sub fixtureRenderCost(windowMs as integer, busyMs as integer)
    ' Only elapsed time is canned; actual comment parsing and rendering execute.
    m.renderWindowClock = { ms: windowMs, totalMilliseconds: fixtureElapsed, mark: fixtureClockMark }
    m.renderWorkClock = { ms: busyMs, totalMilliseconds: fixtureElapsed, mark: fixtureClockMark }
end sub
function fixtureElapsed() as integer
    return m.ms
end function
sub fixtureClockMark()
end sub
function fixtureText(node as object) as string
    if node.hasField("text") then return node.text
    text = ""
    for each child in node.getChildren(-1, 0)
        text += fixtureText(child)
    end for
    return text
end function
function fixturePosters(node as object) as integer
    if node.subtype() = "Poster" then return 1
    count = 0
    for each child in node.getChildren(-1, 0)
        count += fixturePosters(child)
    end for
    return count
end function
`);
}

async function buildEmoteAbsencePackage(dir, marker, mutate = source => source) {
    await addCommon(dir, 'Chat Emote Absence Fixture', marker, 'chat-main.brs');
    const folder = path.join(__dirname, 'fixtures/chat-transport');
    await addFile(dir, 'source/main.brs', await fs.readFile(path.join(folder, 'reopen.brs')));
    await addEmojiLabel(dir);
    await addFile(dir, 'components/ChatJob.xml', await fixture('ChatJob.xml'));
    await addComponent(dir, 'components/Modules/Chat', 'Chat', `function fixtureRead() as object
    return { job: m.chat, emote: m.EmoteJob, cached: m.emoteChannel }
end function
`);
    const provider = 'components/Modules/Chat/EmoteJob/';
    const xml = await fs.readFile(path.join(root, provider, 'EmoteJob.xml'), 'utf8');
    await addFile(dir, provider + 'EmoteJob.xml', xml.replace('pkg:/source/utils/http.brs', 'ProviderHttp.brs'));
    await addFile(dir, provider + 'EmoteJob.brs', mutate(await fs.readFile(path.join(root, provider, 'EmoteJob.brs'), 'utf8')));
    const http = await fs.readFile(path.join(root, 'source/utils/http.brs'), 'utf8');
    const decoders = [...http.matchAll(/^function decodeJson(?:Response|Body)\([^\r\n]*\) as dynamic\r?\n[\s\S]*?^end function(?=\r?$)/gm)];
    assert.equal(decoders.length, 2, 'complete production response and JSON body decoders');
    const decoder = decoders.map(match => match[0]).join('\n');
    assert.equal(decoder.split('type(event) <> "roUrlEvent"').length, 2);
    // Only the native event identity is adapted; status and body decoding execute unchanged.
    await addFile(dir, provider + 'ProviderHttp.brs', (await fs.readFile(path.join(folder, 'ProviderHttp.brs'), 'utf8')) + '\n' +
        decoder.replace('type(event) <> "roUrlEvent"', 'event = invalid'));
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [keyDriver, cli, zip],
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
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|STITCH_CHAT_MODERATION_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
        const summaries = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
        assert.equal(summaries.length, 1, `expected exactly one success summary\n${failure}`);
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

test('seek preview apply/cancel, initial hold delay, fade, captions and quality marker on both wrappers', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-player-', buildWrappersPackage);
    t.diagnostic(`${count} assertions; real engine keys and timers; no media is loaded, so playback state is a fixture input`);
});

test('error dialog Try again makes one fresh request and keeps position, quality and chat layout', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-retry-', buildRetryPackage);
    t.diagnostic(`${count} assertions; content/bookmark/chat tasks are inert boundaries; network and decoding are not tested`);
});

test('chat name contrast cache, EmojiLabel pattern cache and token contrast', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-chat-', buildChatPackage);
    t.diagnostic(`${count} assertions; the emoji pattern source is an engine boundary; chat transport never starts`);
});

test('chat removes displayed and in-flight moderation targets, preserves later messages and releases observers', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-chat-moderation-', buildModerationPackage);
    t.diagnostic(`${count} current Chat handler assertions; parsed IRC notices and an inert transport, no live chat or pixels`);
});

test('actual player owns opt-in watch samples independently of chat, rejects stale owners and cleans up workers', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-engagement-', buildEngagementPackage);
    t.diagnostic(`${count} actual Player/Chat assertions; engagement Task is inert, no network, media or reward credit is tested`);
});

test('actual chat and EmojiLabel render Unicode/provider images, wrap text and clean up failed images', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-chat-emotes-', buildEmojiRenderPackage);
    t.diagnostic(`${count} actual renderer assertions; full pattern adapted from PCRE to simulator UTF-16 regex; native PCRE and CDN decoding require native QA`);
});

test('actual Chat reuses completed optional emote absence after hide/show and retries malformed or transient failures', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-emote-absence-', buildEmoteAbsencePackage);
    t.diagnostic(`${count} actual Chat/EmoteJob Task/decoder assertions; only HTTP events, registry and IRC transport are offline boundaries`);
});

test('discarding optional channel 404 status fails the actual Chat hide/show fixture', { timeout: 90000 }, async () => {
    await assert.rejects(runFixture('stitch-ui-emote-absence-red-', (dir, marker) => buildEmoteAbsencePackage(dir, marker, source => {
        const gate = 'if response.getResponseCode() = 404 then return invalid';
        assert.equal(source.split(gate).length, 2, 'one optional-absence status gate');
        return source.replace(gate, 'if false then return invalid');
    })), /optional404 completes and remembers its cache/);
});
