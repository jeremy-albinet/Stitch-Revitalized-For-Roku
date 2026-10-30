'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const bsc = require('brighterscript');
const root = path.resolve(__dirname, '../..');
function run(zip, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true, stdio: ['ignore','pipe','pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 20000);
        const collect = data => { bytes += data.length; if (bytes > 65536) { exceeded = true; child.kill(); return; } output += data.toString(); };
        child.stdout.on('data', collect); child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => { clearTimeout(timer); resolve({ output, code, timedOut, exceeded, startupError }); });
    });
}
function normal(result) {
    assert.equal(result.startupError, undefined, result.output);
    assert.equal(result.timedOut, false, result.output); assert.equal(result.exceeded, false, result.output);
    assert.equal(result.code, 0, result.output);
    assert.match(result.output, /EXIT_USER_NAV/);
    assert.doesNotMatch(result.output, /\bERROR\b|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|unhandled exception|Syntax Error/i);
}
function positive(result, marker) {
    normal(result); assert.doesNotMatch(result.output, /AD_EXIT_FAIL:/);
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith(`${marker}:`));
    assert.equal(lines.length, 1);
    const match = lines[0].match(/:\s*(\d+) assertions, 8 cases$/);
    assert.ok(match && Number(match[1]) > 600);
    return Number(match[1]);
}
test('Main drains both playback and retained ad metadata owners within its existing deadline', { timeout: 80000 }, async t => {
    const source = await fs.readFile(path.join(root, 'source/main.brs'), 'utf8');
    const hero = await fs.readFile(path.join(root, 'components/heroScene.brs'), 'utf8');
    assert.deepEqual(bsc.Parser.parse(source, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
    assert.match(hero, /metadataOwner = m\.top\.findNode\("stitchAdMetadataOwner"\)\r?\n    if metadataOwner <> invalid then ignored = metadataOwner\.callFunc\("onDestroy"\)/);
    const helpers = [...source.matchAll(/^sub finishMainScene\([^]*?^end sub\r?$/gm)]; assert.equal(helpers.length, 1);
    const actual = helpers[0][0];
    const clock = 'clock = CreateObject("roTimeSpan")', wait = 'msg = wait(timeout, port)';
    assert.equal(actual.split(clock).length, 2); assert.equal(actual.split(wait).length, 2);
    const boundary = actual.replace(clock, 'clock = adExitClock()').replace(wait, 'msg = adExitWait(timeout, port)');
    assert.equal(boundary.replace('clock = adExitClock()', clock).replace('msg = adExitWait(timeout, port)', wait), actual);
    const fixture = await fs.readFile(path.join(__dirname, 'fixtures/ad-main-exit/main.brs'), 'utf8');
    const marker = `AD_MAIN_EXIT_${randomUUID()}`;
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-ad-main-exit-'));
    try {
        const pkg = path.join(dir, 'package'); await fs.mkdir(path.join(pkg, 'source'), { recursive: true });
        await fs.writeFile(path.join(pkg, 'manifest'), 'title=Ad Main Exit Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await fs.writeFile(path.join(pkg, 'source/main.brs'), fixture.replace('__MARKER__', marker));
        for (const mode of ['positive', 'ignore-ad-owner', 'missing-deadline']) {
            let helper = boundary;
            if (mode === 'ignore-ad-owner') helper = helper.replace('if metadataOwner <> invalid then metadataBusy = metadataOwner.busy', 'metadataBusy = false');
            if (mode === 'missing-deadline') {
                const deadline = /        remaining = 15000 - clock\.TotalMilliseconds\(\)\r?\n        if remaining <= 0 then exit while\r?\n        timeout = 100\r?\n        if remaining < timeout then timeout = remaining/;
                assert.equal(helper.match(deadline)?.length, 1);
                helper = helper.replace(deadline, '        timeout = 100');
            }
            if (mode !== 'positive') assert.notEqual(helper, boundary);
            assert.deepEqual(bsc.Parser.parse(helper, { mode: bsc.ParseMode.BrightScript }).diagnostics, []);
            await fs.writeFile(path.join(pkg, 'source/actual.brs'), helper);
            const zip = path.join(dir, `${mode}.zip`); await zipFolder(pkg, zip);
            const result = await run(zip, dir);
            if (mode === 'positive') {
                t.diagnostic(`${positive(result, marker)} actual Main assertions across eight two-owner/idle/deadline/Home cases`);
                assert.throws(() => positive(result, 'stale-marker'));
            } else {
                normal(result); assert.match(result.output, /AD_EXIT_FAIL:/); assert.throws(() => positive(result, marker));
                t.diagnostic(`${mode} actual guard-removal mutant rejected despite normal engine exit`);
            }
        }
        assert.equal(await fs.readFile(path.join(root, 'source/main.brs'), 'utf8'), source);
        assert.equal(await fs.readFile(path.join(root, 'components/heroScene.brs'), 'utf8'), hero);
    } finally {
        const target = path.resolve(dir); assert.equal(path.dirname(target), path.resolve(os.tmpdir()));
        assert.ok(path.basename(target).startsWith('stitch-ad-main-exit-')); await fs.rm(target, { recursive: true, force: true });
    }
});
