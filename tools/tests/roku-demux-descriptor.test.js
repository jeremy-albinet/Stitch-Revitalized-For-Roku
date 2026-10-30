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
const prefix = 'stitch-roku-demux-descriptor-';
const fixturePath = path.join(__dirname, 'fixtures/roku-demux-descriptor');
const productionFiles = ['components/Tasks/GetTwitchContent/GetTwitchContent.brs',
    'source/utils/playbackHls.brs', 'source/utils/rokuDemuxDescriptor.brs',
    'source/utils/rokuVodIndex.brs', 'source/utils/rokuVodDescriptor.brs',
    'source/utils/rokuVodRuntime.brs',
    'components/Modules/TwitchContentNode/TwitchContentNode.xml',
    'components/Modules/TwitchContentNode/TwitchContentNode.brs', 'source/utils/misc.brs'];

function inspectNativeDescriptorKeys(source) {
    const parser = bsc.Parser.parse(source, { mode: bsc.ParseMode.BrightScript });
    assert.deepEqual(parser.diagnostics, []);
    const expected = new Set(['sourceUrl', 'qualityId', 'approvedOrigins', 'videoCodec',
        'audioCodec', 'frameRate', 'isHD']);
    const observed = new Set();
    parser.ast.walk(bsc.createVisitor({
        AAMemberExpression(member) {
            const quoted = member.keyToken.kind === bsc.TokenKind.StringLiteral;
            const spelling = quoted ? member.keyToken.text.slice(1, -1) : member.keyToken.text;
            const canonical = [...expected].find(key => key.toLowerCase() === spelling.toLowerCase());
            if (!canonical) return;
            observed.add(canonical);
            const native = quoted ? spelling : spelling.toLowerCase();
            assert.equal(native, canonical, `native Roku serializes descriptor key as ${native}; quote ${canonical}`);
        },
    }), { walkMode: bsc.WalkMode.visitAllRecursive });
    assert.deepEqual([...observed].sort(), [...expected].sort());
}

function runPackage(zip, dir) {
    return new Promise(resolve => {
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
}

function requireExecution(result) {
    const detail = result.output.slice(-16000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception/i, detail);
    return detail;
}

function requireFreshSummary(result, marker) {
    const detail = requireExecution(result);
    assert.doesNotMatch(result.output, /STITCH_ROKU_DESCRIPTOR_FAIL:/, detail);
    const lines = result.output.split(/\r?\n/).filter(line => line.includes(`${marker}:`));
    assert.equal(lines.length, 1, `expected one fresh fixture summary\n${detail}`);
    const counts = lines[0].match(/:\s*(\d+) assertions,\s*(\d+) cases$/);
    assert.ok(counts && Number(counts[1]) >= 140, detail);
    assert.equal(Number(counts[2]), 39, detail);
    return counts;
}

test('native descriptor JSON uses exact mixed-case keys and rejects an actual unquoted mutation', async () => {
    const source = await fs.readFile(path.join(root, 'source/utils/rokuDemuxDescriptor.brs'), 'utf8');
    inspectNativeDescriptorKeys(source);
    assert.equal(source.split('"sourceUrl": sourceUrl').length, 2);
    assert.throws(() => inspectNativeDescriptorKeys(source.replace('"sourceUrl": sourceUrl', 'sourceUrl: sourceUrl')),
        /native Roku serializes descriptor key as sourceurl/);
    assert.doesNotMatch(source, /\b(?:print|HttpRequest|TwitchGraphQLRequest|get_user_setting|set_user_setting|WriteFile|ReadFile)\b/i);
    const taskXml = await fs.readFile(path.join(root, 'components/Tasks/GetTwitchContent/GetTwitchContent.xml'), 'utf8');
    assert.match(taskXml, /<field id="enableRokuDemux" type="boolean" value="false"\s*\/>/);
    assert.match(taskXml, /uri="pkg:\/source\/utils\/rokuDemuxDescriptor\.brs"/);
    const contentXml = await fs.readFile(path.join(root, 'components/Modules/TwitchContentNode/TwitchContentNode.xml'), 'utf8');
    assert.match(contentXml, /<field id="playbackTransport" type="string" value="direct"\s*\/>/);
    assert.match(contentXml, /<field id="localPlaybackDescriptor" type="assocarray"\s*\/>/);
});

test('actual guarded content task preserves fixed identity, existing transports and bounded origins', { timeout: 70000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const packageDir = path.join(dir, 'package');
    const marker = `STITCH_ROKU_DESCRIPTOR_PASS:${randomUUID()}`;
    async function add(file, data) {
        const target = path.join(packageDir, file);
        await fs.mkdir(path.dirname(target), { recursive: true });
        await fs.writeFile(target, data);
    }
    try {
        // Actual task, parser, descriptor helper and ContentNode run unchanged.
        // Only SDK/network/registry/decoder responses use controlled boundaries.
        for (const file of productionFiles) {
            const source = await fs.readFile(path.join(root, file));
            await add(file, source);
            assert.deepEqual(await fs.readFile(path.join(packageDir, file)), source, `${file} must run unchanged`);
        }
        const capabilities = await fs.readFile(path.join(root, 'source/utils/deviceCapabilities.brs'), 'utf8');
        const hex = capabilities.match(/^function playbackHexValue\([^]*?^end function\r?$/m);
        assert.ok(hex, 'codec hex validation must use the unchanged canonical helper');
        const format = capabilities.match(/^function twitchVariantVideoFormat\([^]*?^end function\r?$/m);
        assert.ok(format, 'VOD readiness format validation must use the unchanged canonical helper');
        await add('source/canonicalHex.brs', hex[0] + '\n' + format[0] + '\n');
        await add('components/boundary.brs', await fs.readFile(path.join(fixturePath, 'boundary.brs')));
        await add('manifest', 'title=Offline Roku Descriptor Contract\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add('components/DescriptorHost.xml', `<component name="DescriptorHost" extends="Scene">
          <interface>
            <function name="loadHlsContent" /><function name="loadClipContent" />
            <field id="contentRequested" type="assocarray" /><field id="response" type="node" />
            <field id="metadata" type="array" /><field id="enableRokuDemux" type="boolean" value="false" />
            <field id="fixtureMaster" type="string" /><field id="fixtureProxy" type="string" />
            <field id="fixturePreference" type="string" /><field id="fixtureBodies" type="assocarray" />
            <field id="fixtureProbes" type="integer" /><field id="fixtureApprovals" type="integer" />
            <field id="fixtureFailures" type="integer" value="0" />
            <field id="fixtureQuery" type="assocarray" /><field id="fixtureUsher" type="assocarray" />
            <field id="fixtureProbeOptions" type="assocarray" />
          </interface>
          <script uri="pkg:/components/Tasks/GetTwitchContent/GetTwitchContent.brs" />
          <script uri="pkg:/source/utils/playbackHls.brs" />
          <script uri="pkg:/source/utils/rokuDemuxDescriptor.brs" />
          <script uri="pkg:/source/utils/rokuVodIndex.brs" />
          <script uri="pkg:/source/utils/rokuVodDescriptor.brs" />
          <script uri="pkg:/source/utils/rokuVodRuntime.brs" />
          <script uri="pkg:/source/canonicalHex.brs" />
          <script uri="boundary.brs" />
        </component>`);
        await add('bsconfig.json', JSON.stringify({ rootDir: packageDir,
            files: ['source/**/*', 'components/**/*', 'manifest'], createPackage: false,
            copyToStaging: false, deploy: false, watch: false, logLevel: 'off',
            showDiagnosticsInConsole: false }));
        const main = await fs.readFile(path.join(fixturePath, 'main.brs'), 'utf8');
        for (const negative of [false, true]) {
            await add('source/main.brs', main.replace('__PASS_MARKER__', marker).replace('__NEGATIVE_CONTROL__', negative ? 'yes' : 'no'));
            if (!negative) {
                const builder = new bsc.ProgramBuilder();
                try {
                    await builder.run({ project: path.join(packageDir, 'bsconfig.json') });
                    assert.equal(path.resolve(builder.rootDir), path.resolve(packageDir));
                    assert.deepEqual(builder.getDiagnostics().map(diagnostic => ({
                        code: diagnostic.code, message: diagnostic.message,
                        file: diagnostic.file?.pkgPath, line: diagnostic.range?.start.line,
                    })), [], 'scoped actual-source fixture must compile without suppressed diagnostics');
                    t.diagnostic('scoped actual-source BrightScript/SceneGraph fixture compile: zero diagnostics');
                } finally {
                    builder.program?.dispose();
                }
            }
            const zip = path.join(dir, negative ? 'negative.zip' : 'fixture.zip');
            await zipFolder(packageDir, zip);
            const result = await runPackage(zip, dir);
            if (!negative) {
                const counts = requireFreshSummary(result, marker);
                t.diagnostic(`${counts[1]} assertions across ${counts[2]} actual task calls; canned IO/decoder boundaries only`);
                assert.throws(() => requireFreshSummary(result, 'STALE_MARKER'), /expected one fresh fixture summary/);
            } else {
                requireExecution(result);
                const failures = result.output.split(/\r?\n/).filter(line => line.includes('STITCH_ROKU_DESCRIPTOR_FAIL:'));
                assert.deepEqual(failures.map(line => line.trim()), ['STITCH_ROKU_DESCRIPTOR_FAIL: deliberate negative control']);
                assert.doesNotMatch(result.output, new RegExp(marker));
                assert.throws(() => requireFreshSummary(result, marker), /STITCH_ROKU_DESCRIPTOR_FAIL/);
                t.diagnostic('actual failed assertion and stale-marker controls rejected');
            }
        }
        const taskPath = 'components/Tasks/GetTwitchContent/GetTwitchContent.brs';
        const taskSource = await fs.readFile(path.join(root, taskPath), 'utf8');
        const retainedFilter = /    if proxyUrl = "" and nativeMetadata\.Count\(\) > 0\r?\n        retainedMetadata = \[\][^]*?        metadata = retainedMetadata\r?\n    end if/;
        const automaticPolicy = /        if proxyUrl = "" and nativeMetadata\.Count\(\) > 0\r?\n            ' Keep native Automatic[^]*?            automatic = rokuDemuxAutomaticEntry\(metadata\)\r?\n        end if/;
        assert.equal(taskSource.match(retainedFilter)?.length, 1, 'mutation must find exactly the retained manual filter');
        assert.equal(taskSource.match(automaticPolicy)?.length, 1, 'mutation must find exactly the native Automatic policy');
        for (const mutation of [
            { name: 'old-native-filter',
                source: taskSource.replace(retainedFilter,
                    '    if proxyUrl = "" and nativeMetadata.Count() > 0 then metadata = nativeMetadata'),
                failure: /STITCH_ROKU_DESCRIPTOR_FAIL: mixed ladder retains every eligible manual quality/ },
            { name: 'forced-mux-automatic',
                source: taskSource.replace(automaticPolicy,
                    '        if m.rokuDemuxEnabled then automatic = rokuDemuxAutomaticEntry(metadata)'),
                failure: /STITCH_ROKU_DESCRIPTOR_FAIL: mixed ladder Automatic retains direct native preference/ },
            { name: 'ignored-preferred-resolution',
                source: taskSource.replace('index = playbackPreferredQualityIndex(metadata, preference)',
                    'index = playbackPreferredQualityIndex(metadata, preference)\n    if preference = "1080p" then index = 0'),
                failure: /STITCH_ROKU_DESCRIPTOR_FAIL: preferred resolution selects a complete existing contract/ },
        ]) {
            assert.notEqual(mutation.source, taskSource, `${mutation.name} must change the actual task`);
            await add(taskPath, mutation.source);
            await add('source/main.brs', main.replace('__PASS_MARKER__', marker).replace('__NEGATIVE_CONTROL__', 'no'));
            const zip = path.join(dir, `${mutation.name}.zip`);
            await zipFolder(packageDir, zip);
            const result = await runPackage(zip, dir);
            requireExecution(result);
            assert.match(result.output, mutation.failure, result.output.slice(-16000));
            assert.doesNotMatch(result.output, new RegExp(marker));
            assert.throws(() => requireFreshSummary(result, marker), /STITCH_ROKU_DESCRIPTOR_FAIL/);
            t.diagnostic(`${mutation.name}: actual task mutation rejected by mixed-ladder assertions despite normal engine exit`);
        }
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()), 'cleanup must stay directly inside temp directory');
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
        await assert.rejects(fs.stat(resolved), { code: 'ENOENT' });
    }
});
