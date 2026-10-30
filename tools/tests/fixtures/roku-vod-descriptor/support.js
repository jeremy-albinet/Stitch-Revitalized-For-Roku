'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const bsc = require('brighterscript');
const root = path.resolve(__dirname, '../../../..');

function run(args, cwd, timeoutMs = 60000, limit = 1024 * 1024) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, args, { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false, startup;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = chunk => {
            if (exceeded) return;
            bytes += chunk.length;
            if (bytes > limit) { exceeded = true; child.kill(); return; }
            output += chunk.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startup = error.name; });
        child.once('close', code => { clearTimeout(timer); resolve({ code, output, timedOut, exceeded, startup }); });
    });
}
function normal(result) {
    const detail = result.output.slice(-14000);
    assert.equal(result.startup, undefined, detail);
    assert.equal(result.code, 0, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}
function positive(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /VOD_P2_FAIL:/, result.output.slice(-14000));
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith('VOD_P2_RESULT: '));
    assert.equal(lines.length, 1);
    assert.ok(lines[0].startsWith(`VOD_P2_RESULT: ${marker} `), 'fresh result required');
    const summary = JSON.parse(lines[0].slice(`VOD_P2_RESULT: ${marker} `.length));
    assert.ok(Number.isInteger(summary.assertions) && summary.assertions > 0);
    assert.equal(summary.failures, 0);
    return summary.assertions;
}
async function fixture(folder, mode, input, mutation) {
    const prefix = 'stitch-vod-p2-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const snapshots = new Map();
    try {
        const marker = randomUUID();
        const names = ['rokuVodIndex', 'rokuDemuxDescriptor', 'playbackHls', 'deviceCapabilities', 'rokuDemuxCommon', 'rokuDemuxProtocol', 'rokuVodDescriptor', 'rokuVodProtocol'];
        for (const name of names) {
            const actual = await fs.readFile(path.join(root, `source/utils/${name}.brs`));
            snapshots.set(name, actual);
            let text = actual.toString();
            if (mutation && name === mutation.name) {
                assert.equal(text.split(mutation.before).length, 2, 'one exact actual mutation required');
                text = text.replace(mutation.before, mutation.after);
            }
            assert.deepEqual(bsc.Parser.parse(text, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            await fs.writeFile(path.join(dir, `${name}.brs`), text);
            if (!mutation || name !== mutation.name) assert.deepEqual(await fs.readFile(path.join(dir, `${name}.brs`)), actual);
        }
        const source = (await fs.readFile(path.join(__dirname, `../${folder}/main.brs`), 'utf8'))
            .replace('__MARKER__', marker).replace('__MODE__', mode);
        assert.deepEqual(bsc.Parser.parse(source, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
        await fs.writeFile(path.join(dir, 'main.brs'), source);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Pure Recorded P2 Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        for (const [name, value] of Object.entries(input)) await fs.writeFile(path.join(dir, name), value);
        const result = await run([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
            ...names.map(name => `${name}.brs`), 'main.brs'], dir);
        for (const [name, actual] of snapshots) assert.deepEqual(await fs.readFile(path.join(root, `source/utils/${name}.brs`)), actual);
        return { result, marker };
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}
module.exports = { fixture, normal, positive, run };
