'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const http = require('node:http');

const root = path.resolve(__dirname, '../..');
const sourcePath = 'components/Tasks/TwitchEngagementTask/TwitchEngagementTask.brs';
const prefix = 'stitch-twitch-engagement-';

async function run(mutation, transportUrl) {
    let source = await fs.readFile(path.join(root, sourcePath), 'utf8');
    if (mutation) {
        assert.equal(source.split(mutation[0]).length - 1, 1, 'mutation targets one actual production guard');
        source = source.replace(mutation[0], mutation[1]);
    }
    const httpPattern = /^function engagementHttp\([^\n]*\r?\n[\s\S]*?^end function(?=\r?$)/gm;
    if (transportUrl) {
        const functions = [...source.matchAll(httpPattern)];
        assert.equal(functions.length, 1);
        const collector = source.match(/^sub collectEngagementWatch\([^\n]*\r?\n[\s\S]*?^end sub(?=\r?$)/m);
        assert.ok(collector, 'HTTP sample collector must be present');
        const authorized = source.match(/^function engagementWatchAuthorized\([^\n]*\r?\n[\s\S]*?^end function(?=\r?$)/m);
        const account = source.match(/^function engagementAccountCurrent\([^\n]*\r?\n[\s\S]*?^end function(?=\r?$)/m);
        assert.ok(authorized && account, 'HTTP sampling preserves credential guards');
        source = [functions[0][0], collector[0], authorized[0], account[0]].join('\n');
        // brs-node returns false unconditionally from these two native TLS
        // setters. Keep their refusal branch testable, then use loopback HTTP.
        for (const [call, replacement] of [
            ['transfer.enablePeerVerification(true)', 'fixtureTlsBoundary(transfer, "peer")'],
            ['transfer.enableHostVerification(true)', 'fixtureTlsBoundary(transfer, "host")'],
        ]) {
            assert.equal(source.split(call).length - 1, 1);
            source = source.replace(call, replacement);
        }
    } else {
        // Execute production decisions; replace only native time/wait and HTTP I/O.
        for (const [name, kind] of [['init', 'sub'], ['engagementHttp', 'function']]) {
            const pattern = new RegExp(`^${kind} ${name}\\([^\\n]*\\r?\\n[\\s\\S]*?^end ${kind}(?=\\r?$)`, 'gm');
            assert.equal([...source.matchAll(pattern)].length, 1);
            source = source.replace(pattern, '');
        }
        source = source.replace(/^sub main\(\)/m, 'sub runWorkerMain()')
            .replace(/\bcreateObject\(/gi, 'fixtureCreateObject(')
            .replace(/\bwait\(/gi, 'fixtureWait(')
            .replace(/\bengagementHttp\(/gi, 'fixtureHttp(');
    }
    const marker = `STITCH_ENGAGEMENT_PASS_${randomUUID()}`;
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    try {
        await fs.writeFile(path.join(dir, 'worker.brs'), source);
        await fs.writeFile(path.join(dir, 'main.brs'), (await fs.readFile(path.join(__dirname, 'fixtures/twitch-engagement', transportUrl ? 'http-main.brs' : 'main.brs'), 'utf8')).replace('__PASS_MARKER__', marker));
        await fs.copyFile(path.join(__dirname, 'fixtures/twitch-engagement/pinned-author-badges.json'), path.join(dir, 'pinned-author-badges.json'));
        for (const helper of ['twitchEngagement.brs', 'twitchAdCountdown.brs']) {
            await fs.copyFile(path.join(root, 'source/utils', helper), path.join(dir, helper));
        }
        const result = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
                ...(transportUrl ? ['--deep-link', `fixtureUrl=${transportUrl}`] : []),
                'twitchEngagement.brs', 'twitchAdCountdown.brs', 'worker.brs', 'main.brs'], { cwd: dir, windowsHide: true });
            let output = '', bytes = 0, timedOut = false, overflow = false;
            const timer = setTimeout(() => { timedOut = true; child.kill(); }, 20000);
            const collect = data => {
                bytes += data.length;
                if (bytes > 1024 * 1024) { overflow = true; child.kill(); return; }
                output += data.toString();
            };
            child.stdout.on('data', collect);
            child.stderr.on('data', collect);
            child.once('error', reject);
            child.once('close', code => { clearTimeout(timer); resolve({ output, code, timedOut, overflow, marker }); });
        });
        return result;
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, { recursive: true, force: true });
    }
}

function accept(result) {
    assert.equal(result.code, 0, result.output.slice(-8000));
    assert.equal(result.timedOut || result.overflow, false);
    assert.doesNotMatch(result.output, /STITCH_ENGAGEMENT_FAIL:|runtime error|BrightScript Debugger|EXIT_BRIGHTSCRIPT_CRASH/i, result.output.slice(-8000));
    const matches = [...result.output.matchAll(new RegExp(`${result.marker}:\\s*(\\d+) assertions`, 'g'))];
    assert.equal(matches.length, 1, result.output.slice(-8000));
    assert.ok(Number(matches[0][1]) > 0);
    return Number(matches[0][1]);
}

test('actual engagement worker credits only moving LIVE samples, isolates account/broadcast changes and keeps telemetry private', async t => {
    const result = await run();
    t.diagnostic(`${accept(result)} actual worker assertions; HTTP/time boundaries are scripted, no Twitch reward-credit claim`);
    assert.doesNotMatch(result.output, /FixturePrivateToken/);
});

test('actual engagement HTTP helper returns statuses, bounds response admission, refuses late completion and honors stop before sending', async t => {
    let requests = 0;
    const server = http.createServer((req, res) => {
        requests++;
        if (req.url === '/slow') {
            setTimeout(() => { if (!res.destroyed) res.end('late'); }, 7000).unref();
        } else if (req.url === '/post') {
            let body = '';
            req.on('data', chunk => { body += chunk; });
            req.on('end', () => { res.end(`${req.method}:${body}`); });
        } else if (req.url === '/large') res.end('x'.repeat(100));
        else if (req.url === '/refused') { res.writeHead(503); res.end('refused'); }
        else { res.writeHead(200); res.end('ok'); }
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
        const result = await run(undefined, `http://127.0.0.1:${server.address().port}`);
        t.diagnostic(`${accept(result)} actual helper assertions over loopback HTTP; native TLS setter outcomes are an explicit engine boundary, no Twitch or native TLS claim`);
        assert.equal(requests, 5, 'a stopped helper sends no request and a timed-out request is never retried');
    } finally {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
    }
});

for (const [name, before, after, expected] of [
    ['account owner guard', 'if get_setting("active_user", "$default$") <> m.account then return false', 'if false then return false', 'logout stops the old account'],
    ['broadcast accrual reset', '        m.broadcastId = snapshot.broadcastId\n        m.watch = engagementWatchState()', '        m.broadcastId = snapshot.broadcastId', 'a changed broadcast discards the pending old minute'],
    ['one-minute submission floor', 'if nowMs - m.lastAttemptMs < 60000 then return', 'if false then return', 'a caller cannot burst another submission'],
    ['pinned-message badge selection', ' senderBadges { setID version }', '', 'pin query selects message sender badge pairs'],
]) {
    test(`removing the ${name} is rejected by actual worker assertions`, async () => {
        const result = await run([before, after]);
        assert.ok(result.output.includes(`STITCH_ENGAGEMENT_FAIL: ${expected}`), result.output.slice(-8000));
        assert.throws(() => accept(result));
    });
}
