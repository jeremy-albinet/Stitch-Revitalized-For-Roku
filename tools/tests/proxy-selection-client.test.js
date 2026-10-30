'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const prefix = 'stitch-proxy-selection-client-';

function inspectNativeSelectionKeys(source) {
    const parser = bsc.Parser.parse(source, { mode: bsc.ParseMode.BrightScript });
    assert.deepEqual(parser.diagnostics, []);
    let fields = 0;
    parser.ast.walk(bsc.createVisitor({
        AAMemberExpression(member) {
            const quoted = member.keyToken.kind === bsc.TokenKind.StringLiteral;
            const spelling = quoted ? member.keyToken.text.slice(1, -1) : member.keyToken.text;
            if (spelling.toLowerCase() !== 'hasuri') return;
            fields++;
            // brs-engine preserves unquoted spelling; native Roku lowercases it.
            const native = quoted ? spelling : spelling.toLowerCase();
            assert.equal(native, 'hasUri', `native Roku serializes URI flag as ${native}; quote hasUri`);
        },
    }), { walkMode: bsc.WalkMode.visitAllRecursive });
    assert.ok(fields > 0, 'actual builder must emit its URI-presence field');
}

test('actual selection builder preserves native mixed-case JSON keys and rejects an unquoted negative control', async () => {
    const source = await fs.readFile(path.join(root, 'source/utils/playbackHls.brs'), 'utf8');
    inspectNativeSelectionKeys(source);
    assert.equal(source.split('"hasUri":').length, 2, 'negative control must target one actual builder field');
    assert.throws(() => inspectNativeSelectionKeys(source.replace('"hasUri":', 'hasUri:')), /native Roku serializes URI flag as hasuri/);
});

test('actual playback task admits only approved descriptors and preserves manual/native preferences', { timeout: 35000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const packageDir = path.join(dir, 'package');
    const marker = `STITCH_SELECTION_PASS:${randomUUID()}`;
    async function add(file, data) {
        const target = path.join(packageDir, file);
        await fs.mkdir(path.dirname(target), { recursive: true });
        await fs.writeFile(target, data);
    }
    try {
        // Production task and HLS helpers are copied verbatim. Only network,
        // registry and native decoder approval are controlled fixture boundaries.
        const files = ['components/Tasks/GetTwitchContent/GetTwitchContent.brs', 'source/utils/playbackHls.brs',
            'source/utils/rokuDemuxDescriptor.brs',
            'components/Modules/TwitchContentNode/TwitchContentNode.xml',
            'components/Modules/TwitchContentNode/TwitchContentNode.brs', 'source/utils/misc.brs'];
        for (const file of files) {
            const source = await fs.readFile(path.join(root, file));
            await add(file, source);
            assert.deepEqual(await fs.readFile(path.join(packageDir, file)), source, `${file} must run unchanged`);
        }
        const fixturePath = path.join(__dirname, 'fixtures/proxy-selection-client');
        await add('source/main.brs', (await fs.readFile(path.join(fixturePath, 'main.brs'), 'utf8')).replace('__PASS_MARKER__', marker));
        await add('components/boundary.brs', await fs.readFile(path.join(fixturePath, 'boundary.brs')));
        await add('manifest', 'title=Offline Proxy Selection Contract\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add('components/SelectionHost.xml', `<component name="SelectionHost" extends="Scene">
          <interface>
            <function name="loadHlsContent" />
            <field id="contentRequested" type="assocarray" /><field id="response" type="node" />
            <field id="metadata" type="array" /><field id="fixtureMaster" type="string" />
            <field id="fixtureProxy" type="string" /><field id="fixturePreference" type="string" />
            <field id="fixtureUsherUrl" type="string" /><field id="fixtureProbes" type="integer" />
            <field id="fixtureFailures" type="integer" value="0" />
            <field id="fixtureLegacyProxy" type="boolean" value="false" />
            <field id="fixtureHealthFailure" type="string" />
          </interface>
          <script uri="pkg:/components/Tasks/GetTwitchContent/GetTwitchContent.brs" />
          <script uri="pkg:/source/utils/playbackHls.brs" />
          <script uri="pkg:/source/utils/rokuDemuxDescriptor.brs" />
          <script uri="boundary.brs" />
        </component>`);
        const zip = path.join(dir, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await new Promise(resolve => {
            const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
                { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
            let output = '', bytes = 0, exceeded = false, timedOut = false, startupError;
            const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
            const collect = data => {
                if (exceeded) return;
                bytes += data.length;
                if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
                output += data.toString();
            };
            child.stdout.on('data', collect);
            child.stderr.on('data', collect);
            child.once('error', error => { startupError = error; });
            child.once('close', (code, signal) => {
                clearTimeout(timer);
                resolve({ code, signal, output, exceeded, timedOut, startupError });
            });
        });
        const detail = result.output.slice(-16000);
        assert.equal(result.startupError, undefined, detail);
        assert.equal(result.timedOut, false, detail);
        assert.equal(result.exceeded, false, detail);
        assert.equal(result.code, 0, detail);
        assert.doesNotMatch(result.output, /STITCH_SELECTION_FAIL:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception/i, detail);
        const lines = result.output.split(/\r?\n/).filter(line => line.includes(`${marker}:`));
        assert.equal(lines.length, 1, `expected one fresh fixture summary\n${detail}`);
        const count = lines[0].match(/:\s*(\d+) assertions,\s*(\d+) cases$/);
        assert.ok(count && Number(count[1]) > 0, detail);
        assert.equal(Number(count[2]), 14, detail);
        t.diagnostic(`${count[1]} assertions across ${count[2]} actual task calls; no live HTTP, native decoder or playback is exercised`);
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()), 'cleanup must stay directly inside temp directory');
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolved), { code: 'ENOENT' });
    }
});
