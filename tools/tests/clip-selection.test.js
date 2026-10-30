'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const production = path.join(root, 'components/Tasks/GetTwitchContent/GetTwitchContent.brs');
const fixture = path.join(__dirname, 'fixtures/clip-selection/main.brs');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const tempPrefix = 'stitch-clip-selection-';
const timeoutMs = 25000;
const outputLimit = 1024 * 1024;

function extractClipFunction(source) {
    const declarations = [...source.matchAll(/^(?:sub|function)\s+getClipUrlViaGraphQL\b[^\r\n]*$/gim)];
    assert.equal(declarations.length, 1, 'expected one production getClipUrlViaGraphQL declaration');
    const matches = [...source.matchAll(/^function getClipUrlViaGraphQL\(slug as string\) as dynamic\r?\n[\s\S]*?^end function(?=\r?$)/gm)];
    assert.equal(matches.length, 1, 'complete production clip query function boundary no longer matches');
    const body = matches[0][0];
    assert.equal([...body.matchAll(/^(?:sub|function)\b/gim)].length, 1, 'clip function extraction crossed another declaration');
    return body;
}

function runScript(dir) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [cli, '--no-sg', '--root', dir, 'clip-query.brs', 'main.brs'],
            { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        let startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        // Wait for this child to close before removing its own temporary files.
        child.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded, startupError });
        });
    });
}

function assertFixtureResult(result, marker) {
    const failure = result.output.slice(-16000);
    assert.equal(result.startupError, undefined, `fixture could not start: ${result.startupError}`);
    assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
    assert.doesNotMatch(result.output, /STITCH_CLIP_FAIL:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception/i, failure);
    const summaries = result.output.split(/\r?\n/).filter(line => line.includes(`${marker}:`));
    assert.equal(summaries.length, 1, `expected exactly one fresh success summary\n${failure}`);
    const summary = summaries[0].match(new RegExp(`${marker}:\\s*(\\d+) assertions,\\s*(\\d+) cases`));
    assert.ok(summary, `fixture success summary is malformed\n${failure}`);
    assert.ok(Number(summary[1]) > 0, `fixture executed zero assertions\n${failure}`);
    assert.equal(Number(summary[2]), 16, `fixture did not complete all clip cases\n${failure}`);
    return Number(summary[1]);
}

test('clip query extraction accepts LF and CRLF and rejects ambiguous or incomplete functions', async () => {
    const source = await fs.readFile(production, 'utf8');
    const lf = source.replaceAll('\r\n', '\n');
    const body = extractClipFunction(lf);
    assert.equal(extractClipFunction(lf.replaceAll('\n', '\r\n')), body.replaceAll('\n', '\r\n'));
    assert.throws(() => extractClipFunction(`${lf}\n${body}`), /expected one production/);
    assert.throws(() => extractClipFunction(body.replace(/^end function$/m, '')), /complete production/);
    assert.throws(() => extractClipFunction(body.replace(/^end function$/m, 'function crossedBoundary()\nend function')), /crossed another declaration/);
});

test('actual clip query selects a usable ladder entry and preserves playback URL construction', { timeout: 35000 }, async t => {
    const source = await fs.readFile(production, 'utf8');
    // This Task also declares main. Extract only the unique complete production
    // function unchanged; the fixture replaces only its network-call boundary.
    const body = extractClipFunction(source);
    const main = await fs.readFile(fixture, 'utf8');
    assert.equal(main.split('__PASS_MARKER__').length - 1, 1, 'fixture must have one success marker placeholder');
    const marker = `STITCH_CLIP_PASS:${randomUUID()}`;
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), tempPrefix));
    try {
        await fs.writeFile(path.join(dir, 'clip-query.brs'), body);
        assert.equal(await fs.readFile(path.join(dir, 'clip-query.brs'), 'utf8'), body, 'production function must be copied verbatim');
        await fs.writeFile(path.join(dir, 'main.brs'), main.replace('__PASS_MARKER__', marker));
        const count = assertFixtureResult(await runScript(dir), marker);
        t.diagnostic(`${count} assertions across 16 sequential calls; canned TwitchGraphQLRequest responses; live Twitch and hardware decoding are not tested`);
    } finally {
        const resolvedDir = path.resolve(dir);
        assert.equal(path.dirname(resolvedDir), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedDir).startsWith(tempPrefix) && path.basename(resolvedDir).length > tempPrefix.length,
            'cleanup must target this fixture directory');
        await fs.rm(resolvedDir, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolvedDir), { code: 'ENOENT' }, 'fixture directory must be removed');
    }
});
