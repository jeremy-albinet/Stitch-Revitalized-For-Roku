'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const production = path.join(root, 'components/Modules/Chat/ChatJob/ChatJob.brs');
const fixture = path.join(__dirname, 'fixtures/chat-transport/main.brs');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const prefix = 'stitch-chat-transport-';

function extractTransport(source) {
    assert.equal([...source.matchAll(/^function\s+openChatTransport\b/gim)].length, 1);
    const matches = [...source.matchAll(/^function openChatTransport\(\) as dynamic\r?\n[\s\S]*?^end function(?=\r?$)/gm)];
    assert.equal(matches.length, 1, 'expected one complete production transport function');
    const body = matches[0][0];
    assert.equal([...body.matchAll(/^(?:sub|function)\b/gim)].length, 1, 'extraction crossed a function boundary');
    return body;
}

function extractConnection(source) {
    const matches = [...source.matchAll(/^(?:sub (?:runChatConnection\(transport as object\)|publishModeration\(queue as object, event as object\)|updateDeliveryState\(state as string\))|function queuedChatAge\(entry as object, nowSeconds as integer\) as float)\r?\n[\s\S]*?^end (?:sub|function)(?=\r?$)/gm)];
    assert.equal(matches.length, 4, 'expected complete production connection, age, moderation and delivery state functions');
    for (const match of matches) assert.equal([...match[0].matchAll(/^(?:sub|function)\b/gim)].length, 1);
    return matches.map(match => match[0]).join('\n');
}

function extractSendLogin(source) {
    const matches = [...source.matchAll(/^function (?:sendChatLine|loginToChat)\([^\r\n]*\) as boolean\r?\n[\s\S]*?^end function(?=\r?$)/gm)];
    assert.equal(matches.length, 2, 'expected complete production send and login functions');
    for (const match of matches) assert.equal([...match[0].matchAll(/^(?:sub|function)\b/gim)].length, 1);
    return matches.map(match => match[0]).join('\n');
}

function extractJob(source) {
    const matches = [...source.matchAll(/^sub main\(\)\r?\n[\s\S]*?^end sub(?=\r?$)/gm)];
    assert.equal(matches.length, 1, 'expected one complete production job function');
    assert.equal([...matches[0][0].matchAll(/^(?:sub|function)\b/gim)].length, 1);
    return matches[0][0].replace(/^sub main\(\)/, 'sub runChatJob()');
}

async function runFixture(body, connection = '', sendLogin = '', job = '', moderation = false, emote = '', fixturePath = fixture) {
    // The interpreter has no native TCP/WebSocket implementation. Replace only
    // object creation and waiting with explicit, deterministic OS boundaries.
    // All production connection/send/login decisions, deadlines and cleanup execute.
    const combined = [body, connection, sendLogin, job, emote].join('\n');
    assert.equal([...combined.matchAll(/\bcreateObject\(/gi)].length, (body ? 4 : 0) + (connection ? 8 : 0) + (sendLogin ? 2 : 0) + (job ? 2 : 0));
    assert.equal([...combined.matchAll(/\bwait\(/gi)].length, (body ? 1 : 0) + (connection ? 1 : 0) + (job ? 1 : 0));
    const bounded = combined.replace(/\bcreateObject\(/gi, 'fixtureCreateObject(').replace(/\bwait\(/gi, 'fixtureWait(')
        .replace(/\bsleep\(/gi, 'fixtureSleep(').replace(/\bircParseMessage\(/g, 'fixtureParseMessage(');
    const marker = `STITCH_CHAT_TRANSPORT_PASS_${randomUUID()}`;
    const main = (await fs.readFile(fixturePath, 'utf8')).replace('__PASS_MARKER__', marker)
        .replace('__CONNECTION_TESTS__', connection ? 'runConnectionTests()' : '')
        .replace('__SEND_TESTS__', sendLogin ? 'runSendTests()' : '')
        .replace('__JOB_TESTS__', job ? 'runJobTests()' : '')
        .replace('__MODERATION_TESTS__', moderation ? 'runModerationTests()' : '')
        .replace('__EMOTE_TESTS__', emote ? 'runEmoteTests()' : '');
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    try {
        await fs.writeFile(path.join(dir, 'transport.brs'), bounded);
        await fs.writeFile(path.join(dir, 'main.brs'), main);
        await fs.copyFile(path.join(root, 'source/utils/ircParser.brs'), path.join(dir, 'ircParser.brs'));
        await fs.copyFile(path.join(root, 'source/utils/ircEmotes.brs'), path.join(dir, 'ircEmotes.brs'));
        return await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, [cli, '--no-sg', '--root', dir, 'transport.brs', 'ircParser.brs', 'ircEmotes.brs', 'main.brs'],
                { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
            let output = '', bytes = 0, excessive = false, timedOut = false, startup;
            const timeout = setTimeout(() => { timedOut = true; child.kill(); }, 15000);
            const collect = data => {
                bytes += data.length;
                if (bytes > 1024 * 1024) { excessive = true; child.kill(); return; }
                output += data.toString();
            };
            child.stdout.on('data', collect);
            child.stderr.on('data', collect);
            child.once('error', error => { startup = error; });
            child.once('close', code => {
                clearTimeout(timeout);
                if (startup || timedOut || excessive || code !== 0) reject(Error(`Transport fixture process failed: ${startup || code}\n${output.slice(-10000)}`));
                else resolve({ output, marker });
            });
        });
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix) && path.basename(dir).length > prefix.length);
        await fs.rm(dir, { recursive: true, force: true });
    }
}

function acceptResult({ output, marker }) {
    assert.doesNotMatch(output, /STITCH_CHAT_TRANSPORT_FAIL:|\bERROR\b|runtime error|EXIT_BRIGHTSCRIPT_CRASH|BrightScript Debugger/i, output.slice(-10000));
    const summaries = output.split(/\r?\n/).filter(line => line.startsWith(`${marker}:`));
    assert.equal(summaries.length, 1, 'expected one fresh nonzero assertion summary');
    const count = summaries[0].match(/:\s*(\d+) assertions$/);
    assert.ok(count && Number(count[1]) > 0, 'zero or malformed assertion count');
    return Number(count[1]);
}

test('actual chat transport accepts writable TCP despite stale connected status and preserves failure/stop/TLS guards', async t => {
    const body = extractTransport(await fs.readFile(production, 'utf8'));
    const count = acceptResult(await runFixture(body));
    t.diagnostic(`${count} actual transport assertions with simulated socket/time boundaries; native Twitch delivery is verified separately`);
});

test('the old connected-status gate is rejected even when BrightScript exits normally', async () => {
    const body = extractTransport(await fs.readFile(production, 'utf8'));
    const gate = 'if socket.isWritable() and socket.eOK()';
    assert.equal(body.split(gate).length - 1, 1, 'mutation must target one production TCP gate');
    const result = await runFixture(body.replace(gate, 'if socket.isConnected() and socket.isWritable()'));
    assert.match(result.output, /STITCH_CHAT_TRANSPORT_FAIL: writable TCP with stale connected status must be usable/);
    assert.throws(() => acceptResult(result));
});

test('actual TCP connection survives stale read readiness and still exits on EOF/error/stop', async t => {
    const source = await fs.readFile(production, 'utf8');
    const count = acceptResult(await runFixture(extractTransport(source), extractConnection(source)));
    t.diagnostic(`${count} transport/receive assertions; real IRC parser with canned nonblocking socket results`);
});

test('the old empty-buffer disconnect rejects the pending-read case', async () => {
    const source = await fs.readFile(production, 'utf8');
    const connection = extractConnection(source);
    const read = /^            if transport\.socket\.getCountRcvBuf\(\) > 0 or transport\.socket\.isReadable\(\)\r?\n[\s\S]*?^            if not transport\.socket\.eOK\(\) then return$/m;
    assert.equal([...connection.matchAll(new RegExp(read.source, 'gm'))].length, 1);
    const old = '            if transport.socket.getCountRcvBuf() > 0\n' +
        '                chunk = transport.socket.receiveStr(4096)\n' +
        '            else if transport.socket.isReadable() or not transport.socket.eOK()\n' +
        '                return\n            end if';
    const result = await runFixture(extractTransport(source), connection.replace(read, old));
    assert.match(result.output, /STITCH_CHAT_TRANSPORT_FAIL: pending read must allow subsequent welcome and chat packet/);
    assert.throws(() => acceptResult(result));
});

test('bypassing the Sync hold is rejected with independent elapsed and server clocks', async () => {
    const source = await fs.readFile(production, 'utf8');
    const connection = extractConnection(source);
    const gate = 'delay = ircBoundedDelay(m.top.delaySeconds, m.top.forceLive)';
    assert.equal(connection.split(gate).length - 1, 1);
    const result = await runFixture(extractTransport(source), connection.replace(gate, 'delay = 0'));
    assert.match(result.output, /STITCH_CHAT_TRANSPORT_FAIL: Sync holds server-timed and tagless messages for thirteen real seconds/);
    assert.throws(() => acceptResult(result));
});

test('actual send and login reject invalid sends, preserve complete TCP writes and never read plaintext credentials', async t => {
    const source = await fs.readFile(production, 'utf8');
    const count = acceptResult(await runFixture(extractTransport(source), extractConnection(source), extractSendLogin(source), extractJob(source)));
    t.diagnostic(`${count} transport/receive/send/login/retry assertions; native Send result-object fields remain undocumented and OS16 acceptance remains separate`);
});

test('ignoring a failed login send is rejected by the actual send/login/retry fixture', async () => {
    const source = await fs.readFile(production, 'utf8');
    const functions = extractSendLogin(source);
    const gate = 'if not sendChatLine(transport, line) then return false';
    assert.equal(functions.split(gate).length - 1, 1);
    const result = await runFixture(extractTransport(source), extractConnection(source),
        functions.replace(gate, 'sendChatLine(transport, line)'), extractJob(source));
    assert.match(result.output, /STITCH_CHAT_TRANSPORT_FAIL: invalid secure send must fail login before credentials are sent/);
    assert.throws(() => acceptResult(result));
});

test('actual connection removes deleted and purged queued messages before delayed delivery and publishes moderation promptly', async t => {
    const source = await fs.readFile(production, 'utf8');
    const result = await runFixture(extractTransport(source), extractConnection(source), '', '', true);
    const count = acceptResult(result);
    assert.doesNotMatch(result.output, /FixtureDeletedText|after timeout/, 'moderation and chat text must not be logged');
    t.diagnostic(`${count} transport/parser assertions; scripted IRC lines on the canned socket, the wait boundary acknowledges deliveries`);
});

test('actual emote lifecycle stops between providers, suppresses canceled publication and keeps partial caches retryable', async t => {
    const source = await fs.readFile(path.join(root, 'components/Modules/Chat/EmoteJob/EmoteJob.brs'), 'utf8');
    const matches = [...source.matchAll(/^sub (?:main\(\)|publishEmoteCache\(fetched as object\))\r?\n[\s\S]*?^end sub(?=\r?$)/gm)];
    assert.equal(matches.length, 2, 'expected complete production emote main and publisher');
    const emote = matches.map(match => match[0]).join('\n').replace(/^sub main\(\)/m, 'sub runEmoteJob()');
    const body = extractTransport(await fs.readFile(production, 'utf8'));
    const count = acceptResult(await runFixture(body, '', '', '', false, emote));
    t.diagnostic(`${count} transport/emote lifecycle assertions; provider fetch functions are explicit offline boundaries`);
});

test('actual emote providers complete optional channel 404s while malformed 200s and transient failures stay retryable', async t => {
    const source = await fs.readFile(path.join(root, 'components/Modules/Chat/EmoteJob/EmoteJob.brs'), 'utf8');
    assert.equal([...source.matchAll(/^sub main\(\)/gm)].length, 1);
    const http = await fs.readFile(path.join(root, 'source/utils/http.brs'), 'utf8');
    const decoders = [...http.matchAll(/^function decodeJsonBody\([^\r\n]*\) as dynamic\r?\n[\s\S]*?^end function(?=\r?$)/gm)];
    assert.equal(decoders.length, 1, 'expected the complete production HTTP body decoder');
    const emote = source.replace(/^sub main\(\)/m, 'sub runEmoteJob()') + '\n' + decoders[0][0];
    const result = await runFixture('', '', '', '', false, emote,
        path.join(__dirname, 'fixtures/chat-transport/providers.brs'));
    // Caught provider failures and the deliberately invalid JSON are expected inputs.
    // Retain every other error guard, including parser errors for any other input.
    result.output = result.output.replace(/^Error grabbing global7tv badges\r?$/gm, '')
        .replace(/^BRIGHTSCRIPT: ERROR: ParseJSON: [^\r\n]*"not JSON"[^\r\n]*pkg:\/source\/transport\.brs\(\d+\)\r?$/gm, '');
    const count = acceptResult(result);
    t.diagnostic(`${count} actual provider/lifecycle/JSON decoder assertions; only HTTP and registry boundaries are canned`);
});

for (const [name, gate, replacement, expected] of [
    ['ignoring CLEARMSG and CLEARCHAT', /^ {16}else if command = "CLEARMSG" or command = "CLEARCHAT"\r?\n[^\r\n]*\r?\n[^\r\n]*\r?\n/m, '',
        /STITCH_CHAT_TRANSPORT_FAIL: deleted queued message must never be delivered/],
    ['publishing moderation only when the renderer is ready', 'if moderation <> invalid then publishModeration(queue, moderation)',
        'if moderation <> invalid and m.top.readyForNextComment then publishModeration(queue, moderation)',
        /STITCH_CHAT_TRANSPORT_FAIL: moderation publishes while the renderer is busy/],
    ['omitting the in-flight moderation stamp', 'nextComment.comment.moderationSeq = m.moderationSeq', 'nextComment.comment.moderationSeq = 0',
        /STITCH_CHAT_TRANSPORT_FAIL: delivered comments carry the moderation they survived/],
    ['an unbounded moderation window', 'if m.moderationLog.count() > 32 then m.moderationLog.shift()', '',
        /STITCH_CHAT_TRANSPORT_FAIL: the moderation window holds the latest 32 events/],
]) {
    test(`${name} is rejected by the actual moderation fixture`, async () => {
        const source = await fs.readFile(production, 'utf8');
        const connection = extractConnection(source);
        const occurrences = typeof gate === 'string' ? connection.split(gate).length - 1
            : [...connection.matchAll(new RegExp(gate.source, 'gm'))].length;
        assert.equal(occurrences, 1, 'mutation must target one production statement');
        const result = await runFixture(extractTransport(source), connection.replace(gate, replacement), '', '', true);
        assert.match(result.output, expected);
        assert.throws(() => acceptResult(result));
    });
}
