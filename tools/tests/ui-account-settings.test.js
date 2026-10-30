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
const fixtures = path.join(__dirname, 'fixtures/ui-account-settings');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const timeoutMs = 25000;
const outputLimit = 1024 * 1024;
const tempPrefix = 'stitch-ui-account-settings-';
const proxySource = 'components/Tasks/ProxyHealthCheck/ProxyHealthCheck.brs';

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

function functionPattern(name) {
    return new RegExp(`^(?:sub|function)\\s+${name}\\b[^\\n]*\\n[\\s\\S]*?^end (?:sub|function)\\s*$`, 'im');
}

async function selectFunctions(file, names) {
    const source = await fs.readFile(path.join(root, file), 'utf8');
    return names.map(name => {
        const match = source.match(functionPattern(name));
        assert.ok(match, `production function missing: ${name}`);
        return match[0];
    }).join('\n\n');
}

// Actual component bodies remain unchanged. XML substitutes are asserted I/O
// or unsupported profile/card boundaries; appended exports inspect native state
// or invoke the actual handler, never duplicate its implementation.
async function addComponent(dir, folder, name, probe, replacements = []) {
    let xml = (await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8')).replace(/\r\n/g, '\n');
    for (const [from, to] of replacements) {
        assert.ok(xml.includes(from), `${name} fixture boundary no longer matches ${from}`);
        xml = xml.replaceAll(from, to);
    }
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    assert.ok(xml.includes('</interface>') && xml.includes('</component>'), `${name} interface missing`);
    xml = xml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
    await addFile(dir, `${folder}/${name}.xml`, xml);
    await copyFile(dir, `${folder}/${name}.brs`);
    await addFile(dir, `components/${name}Fixture.brs`, probe);
}

async function buildPackage(dir, marker, negative) {
    await addFile(dir, 'manifest', 'title=Offline Account and Settings Regression Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of [
        'source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/sceneFactory.brs', 'source/utils/lifecycle.brs', 'source/utils/contentBuilder.brs', 'source/utils/recentlyWatched.brs',
        'source/utils/playbackHls.brs',
        'settings/settings.json', 'components/SceneManager/Group/SceneManagerGroup.xml',
        'components/SceneManager/Group/SceneManagerGroup.brs', proxySource,
    ]) await copyFile(dir, file);
    for (const folder of [
        'fonts', 'images', 'components/Modules/CirclePoster', 'components/Modules/TwitchContentNode',
        'components/Modules/StatusPanel', 'components/Modules/MenuBar/ButtonGroupHoriz',
    ]) await copyTree(dir, folder);

    // Only registry storage I/O is replaced. Real get_setting/get_user_setting,
    // defaults, findConfigTreeKey and signOutAccount execute against a shared
    // native global node, avoiding brs-engine's AA copy-on-read limitation.
    let config = await fs.readFile(path.join(root, 'source/utils/config.brs'), 'utf8');
    for (const name of ['registry_read', 'registry_write', 'registry_delete']) {
        assert.ok(functionPattern(name).test(config), `registry boundary missing: ${name}`);
        config = config.replace(functionPattern(name), '');
    }
    await addFile(dir, 'source/utils/config.brs', `${config}\n${await fixture('registry.brs')}`);
    for (const file of [
        'FixtureScene.xml', 'scene.brs', 'TwitchApiTask.xml', 'ProxyHealthCheck.xml',
        'proxy-task-probe.brs', 'http-boundary.brs', 'QrBoundary.xml', 'CardBoundary.xml', 'InfoBoundary.xml',
    ]) await addFile(dir, `components/${file}`, await fixture(file));
    for (const file of ['KeyboardBoundary.xml', 'keyboard.brs']) {
        await addFile(dir, `components/${file}`, await fs.readFile(path.join(fixtures, '../ui', file)));
    }
    await addFile(dir, 'source/main.brs', (await fixture('main.brs'))
        .replaceAll('__PASS_MARKER__', marker).replace('__NEGATIVE_CONTROL__', negative ? 'true' : 'false'));

    const keys = `function fixtureKey(key as string, press = true as boolean) as boolean
    return onKeyEvent(key, press)
end function
`;
    await addComponent(dir, 'components/Scenes/LoginPage', 'LoginPage', (await fixture('login-probe.brs')) + keys,
        [['<Poster\n                id="qrCode"', '<QrBoundary\n                id="qrCode"']]);
    await addComponent(dir, 'components/Scenes/Settings', 'settings', (await fixture('settings-probe.brs')) + keys);
    await addComponent(dir, 'components/Scenes/Settings', 'SettingsListItem', `function fixtureRead() as object
    return { disposed: m.disposed, name: m.name, value: m.value, plate: m.plate }
end function
`);
    await addComponent(dir, 'components/Modules/MenuBar', 'MenuBar', `function fixtureRead() as object
    return { icons: m.iconOptions, caption: m.iconCaption, label: m.iconCaptionLabel }
end function
`);
    const detail = `function fixtureRead() as object
    return { task: m.GetContentTask, shell: m.GetShellTask, rowlist: m.rowlist, disposed: m.disposed }
end function
`;
    await addComponent(dir, 'components/Scenes/Following', 'Following', detail,
        [['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"']]);
    await addComponent(dir, 'components/Scenes/Browse', 'Browse', detail,
        [['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"']]);
    await addComponent(dir, 'components/Scenes/GamePage', 'GamePage', detail,
        [['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"']]);
    await addComponent(dir, 'components/Scenes/Search', 'Search', detail, [
        ['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"'],
        ['<DynamicMiniKeyboard', '<KeyboardBoundary'],
    ]);
    await addComponent(dir, 'components/Scenes/ChannelPage', 'ChannelPage', detail, [
        ['itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"'],
        ['<SimpleLabel', '<Label'], ['<InfoPane', '<InfoBoundary'], ['fontSize="32"', ''], ['fontSize="20"', ''],
        ['fontUri="pkg:/fonts/Archivo-Bold.otf"', ''], ['fontUri="pkg:/fonts/Archivo-Regular.otf"', ''],
    ]);
    // Startup and the menu-id resolver are separate tracked fixtures. Whole
    // current navigation functions execute here with actual sceneFactory and
    // lifecycle helpers, without copying their implementations.
    await addFile(dir, 'components/HeroActual.brs', await selectFunctions('components/heroScene.brs', [
        'buildNode', 'discardScene', 'teardownAllScenes', 'openPage', 'onContentSelected',
        'onLogoutFinished', 'onLoginFinished', 'onBackPressed', 'isContentTab', 'hideStartupStatus',
        'showChangelogDialog', 'focusedMenuItem', 'onMenuSelection',
    ]));
    await addFile(dir, 'source/utils/analytics.brs', 'sub trackEvent(name as string, props = invalid)\nend sub\n');
}

function runChild(args, cwd, limitMs = timeoutMs) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, args, { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, limitMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        // Own children are closed before any package/temp cleanup occurs.
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

function escapeRegex(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function expectedParseDiagnostic() {
    const source = await fs.readFile(path.join(root, proxySource), 'utf8');
    const lines = source.split(/\r?\n/);
    const calls = lines.map((line, index) => /\bparsed\s*=\s*ParseJson\(body\)/i.test(line) ? index + 1 : 0).filter(Boolean);
    assert.equal(calls.length, 1, 'expected exactly one actual proxy ParseJSON call');
    return `BRIGHTSCRIPT: ERROR: ParseJSON: Unexpected token 'o', "not JSON" is not valid JSON: pkg:/${proxySource}(${calls[0]})`;
}

function withoutExpectedDiagnostic(output, parseDiagnostic) {
    const lines = output.split(/\r?\n/);
    const markers = lines.filter(line => line.includes('EXPECTED_PARSEJSON_'));
    const diagnosticCount = lines.filter(line => line === parseDiagnostic).length;
    if (markers.length === 0 && diagnosticCount === 0) return output;
    assert.deepEqual(markers, ['EXPECTED_PARSEJSON_BEGIN', 'EXPECTED_PARSEJSON_END'], 'one ordered expected ParseJSON marker pair required');
    assert.equal(diagnosticCount, 1, 'one exact expected ParseJSON diagnostic required');
    return lines.map(line => line === parseDiagnostic ? 'EXPECTED_CAUGHT_JSON_DIAGNOSTIC' : line).join('\n');
}

function validate(result, marker, parseDiagnostic) {
    const failure = result.output.slice(-16000);
    assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
    // The actual caught malformed-JSON case emits an engine diagnostic. Permit
    // only one exact current production source line/message with one ordered
    // case marker pair. Independently collected stdout/stderr can reorder that
    // diagnostic relative to the markers; all other ERRORs still fail.
    const output = withoutExpectedDiagnostic(result.output, parseDiagnostic);
    assert.doesNotMatch(output, /STITCH_UI_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|\bERROR\b/i, failure);
    assert.match(output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
    const summaries = [...output.matchAll(new RegExp(`^${escapeRegex(marker)}:\\s*(\\d+) assertions\\s*$`, 'gm'))];
    assert.equal(summaries.length, 1, `one fresh fixture success marker required\n${failure}`);
    assert.ok(Number(summaries[0][1]) > 0, `fixture executed zero assertions\n${failure}`);
    return Number(summaries[0][1]);
}

async function runFixture(negative = false) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), tempPrefix));
    const marker = `STITCH_ACCOUNT_SETTINGS_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker, negative);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runChild([path.join(fixtures, 'key-driver.js'), cli, zip], temp);
        return { result, marker, parseDiagnostic: await expectedParseDiagnostic() };
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith(tempPrefix), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
}

test('Settings preserves retained storage contracts and upstream support in grouped panels', async () => {
    // Explicit stable schema contract, independent of Git or a second copy of
    // the current schema. Copy and ordering can evolve without changing ids.
    const before = JSON.parse(await fixture('original-setting-contracts.json'));
    const schema = JSON.parse(await fs.readFile(path.join(root, 'settings/settings.json'), 'utf8'));
    const leaves = items => items.flatMap(item => item.children ? leaves(item.children) : [item]);
    const after = leaves(schema);
    assert.deepEqual(schema.filter(item => item.children).map(item => item.id), ['playback', 'chat', 'emotes', 'browsing', 'advanced']);
    assert.equal(schema[0].settingName, 'logout');
    const map = new Map(after.map(setting => [setting.settingName, setting]));
    assert.equal(before.length, 13, 'historical schema snapshot remains intact');
    const retained = before;
    assert.equal(retained.length, 13);
    const additions = ['playback.watchCredit', 'chat.hypeTrain', 'chat.pinnedMessages', 'proxy.builtin', 'chat.timing', 'chat.animatedEmotes', 'chat.layout', 'chat.overlayPosition', 'chat.overlayOpacity', 'ui.gridDensity', 'chat.enabled', 'ui.floatingFocus'];
    assert.equal(after.length, retained.length + additions.length);
    assert.equal(map.size, after.length, 'setting keys must be unique');
    assert.equal(map.get('support').action, 'support_stitch', 'upstream donation action remains available');
    for (const setting of retained) {
        const current = map.get(setting.settingName);
        assert.ok(current, setting.settingName);
        assert.equal(current.type, setting.type, setting.settingName);
        assert.equal(current.action, setting.action, setting.settingName);
        const optionIds = current.options?.map(option => option.id);
        if (setting.settingName === 'playback.video.quality') {
            assert.deepEqual(optionIds.slice(0, setting.optionIds.length), setting.optionIds, 'legacy quality IDs retain their order');
            assert.deepEqual(optionIds.slice(setting.optionIds.length), ['2160p', '1440p', '1080p', '720p', '480p', '360p', '160p']);
        } else {
            assert.deepEqual(optionIds, setting.optionIds, setting.settingName);
        }
        assert.equal(current.default, setting.settingName === 'ChatFontSize' ? '16' : setting.default, setting.settingName);
    }
    assert.equal(map.get('analytics.enabled').default, 'false');
    assert.equal(map.get('playback.lowLatency').default, 'false');
    assert.equal(map.get('playback.lowLatency').experimental, true);
    assert.equal(map.get('proxy.builtin').type, 'bool');
    assert.equal(map.get('proxy.builtin').default, 'true');
    assert.equal(map.get('chat.animatedEmotes').type, 'bool');
    assert.equal(map.get('chat.animatedEmotes').default, 'true');
    assert.equal(map.get('chat.timing').type, 'radio');
    assert.equal(map.get('chat.timing').default, 'sync');
    assert.deepEqual(map.get('chat.timing').options.map(option => option.id), ['sync', 'live']);
    for (const key of ['playback.watchCredit', 'chat.hypeTrain', 'chat.pinnedMessages']) {
        assert.equal(map.get(key).type, 'bool', key);
        assert.equal(map.get(key).default, 'false', key);
        assert.equal(map.get(key).experimental, true, key);
    }
});

test('Account, Login, Settings, dialogs, health checks and late-failure focus run actual native handlers', { timeout: 40000 }, async t => {
    const { result, marker, parseDiagnostic } = await runFixture();
    const count = validate(result, marker, parseDiagnostic);
    t.diagnostic(`${count} current-source assertions; fresh marker ${marker}; registry I/O, Task workers, HTTP transport, QR fetch and card/profile views are inert; native widgets/dialogs/remote focus execute; pixels/network/media/hardware are not tested`);
});

test('a normally exiting actual package with a deliberate assertion failure is rejected', { timeout: 40000 }, async t => {
    const { result, marker, parseDiagnostic } = await runFixture(true);
    assert.equal(result.timedOut, false, result.output.slice(-16000));
    assert.equal(result.exceeded, false);
    assert.equal(result.code, 0, result.output.slice(-16000));
    assert.match(result.output, /EXIT_USER_NAV/);
    const summary = result.output.match(/STITCH_UI_FAIL:\s*1 failures;\s*(\d+) assertions/);
    assert.ok(summary, result.output.slice(-16000));
    assert.doesNotMatch(withoutExpectedDiagnostic(result.output, parseDiagnostic), /FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|\bERROR\b/i);
    assert.throws(() => validate(result, marker, parseDiagnostic), /STITCH_UI_FAIL/);
    t.diagnostic(`${summary[1]} actual assertions execute; fresh marker ${marker}; exactly one deliberate failure is rejected despite exit 0 and normal close`);
});

test('output guards reject stale/zero markers, failures, errors, crashes and abnormal exits', async () => {
    const marker = `STITCH_ACCOUNT_SETTINGS_PASS:${randomUUID()}`;
    const parseDiagnostic = await expectedParseDiagnostic();
    const valid = { code: 0, timedOut: false, exceeded: false, output: `EXIT_USER_NAV\n${marker}: 1 assertions\n` };
    assert.equal(validate(valid, marker, parseDiagnostic), 1);
    assert.equal(validate({ ...valid, output: valid.output.replace(/\n/g, '\r\n') }, marker, parseDiagnostic), 1);
    const expected = `EXPECTED_PARSEJSON_BEGIN\n${parseDiagnostic}\nEXPECTED_PARSEJSON_END\n`;
    const markerPair = 'EXPECTED_PARSEJSON_BEGIN\nEXPECTED_PARSEJSON_END\n';
    for (const output of [expected, `${parseDiagnostic}\n${markerPair}`, `${markerPair}${parseDiagnostic}\n`]) {
        for (const newline of ['\n', '\r\n']) {
            assert.equal(validate({ ...valid, output: (output + valid.output).replace(/\n/g, newline) }, marker, parseDiagnostic), 1);
        }
    }
    // Actual Ubuntu ordering: stdout markers and assertions preceded the stderr
    // diagnostic; app lines used CRLF while the diagnostic used LF.
    const ciOrdered = 'EXPECTED_PARSEJSON_BEGIN\r\nEXPECTED_PARSEJSON_END\r\n'
        + 'PASS  128: actual ProxyHealthCheck parses inert HTTP bad_body result\r\n'
        + 'PASS  129: actual health worker retains URL/finite HTTP contract\r\n'
        + `${parseDiagnostic}\n${valid.output}`;
    assert.equal(validate({ ...valid, output: ciOrdered }, marker, parseDiagnostic), 1);
    const controls = [
        { ...valid, output: 'EXIT_USER_NAV' },
        { ...valid, output: `EXIT_USER_NAV\n${marker}: 0 assertions` },
        { ...valid, output: 'EXIT_USER_NAV\nSTITCH_ACCOUNT_SETTINGS_PASS:stale: 3 assertions' },
        { ...valid, output: valid.output + 'STITCH_UI_FAIL: bad' },
        { ...valid, output: valid.output + 'EXIT_BRIGHTSCRIPT_CRASH' },
        { ...valid, timedOut: true }, { ...valid, exceeded: true }, { ...valid, code: 1 },
        { ...valid, output: `${marker}: 1 assertions` },
        { ...valid, output: valid.output + 'BRIGHTSCRIPT: ERROR: unexpected' },
        { ...valid, output: `${parseDiagnostic}\n${valid.output}` },
        { ...valid, output: markerPair + valid.output },
        { ...valid, output: `EXPECTED_PARSEJSON_BEGIN\n${parseDiagnostic}\n${valid.output}` },
        { ...valid, output: `${parseDiagnostic}\nEXPECTED_PARSEJSON_END\n${valid.output}` },
        { ...valid, output: `EXPECTED_PARSEJSON_END\n${parseDiagnostic}\nEXPECTED_PARSEJSON_BEGIN\n${valid.output}` },
        { ...valid, output: expected + expected + valid.output },
        { ...valid, output: expected + 'EXPECTED_PARSEJSON_BEGIN\n' + valid.output },
        { ...valid, output: expected + 'EXPECTED_PARSEJSON_END\n' + valid.output },
        { ...valid, output: expected + `${parseDiagnostic}\n${valid.output}` },
        { ...valid, output: expected.replace('EXPECTED_PARSEJSON_BEGIN', 'EXPECTED_PARSEJSON_BEGIN-extra') + valid.output },
        { ...valid, output: expected.replace('EXPECTED_PARSEJSON_END', 'EXPECTED_PARSEJSON_END-extra') + valid.output },
        { ...valid, output: expected.replace(parseDiagnostic, parseDiagnostic.replace('not JSON', 'wrong body')) + valid.output },
        { ...valid, output: expected.replace(parseDiagnostic, parseDiagnostic.replace(proxySource, 'components/Other.brs')) + valid.output },
        { ...valid, output: expected.replace(parseDiagnostic, parseDiagnostic.replace(/\(\d+\)$/, '(9999)')) + valid.output },
        { ...valid, output: expected + 'EXPECTED_PARSEJSON_BEGIN-extra\n' + valid.output },
        { ...valid, output: valid.output + 'EXPECTED_PARSEJSON_BEGIN\nBRIGHTSCRIPT: ERROR: runtime failure\nEXPECTED_PARSEJSON_END' },
        { ...valid, output: 'BRIGHTSCRIPT: ERROR: unexpected before caught diagnostic\n' + expected + valid.output },
        { ...valid, output: expected + valid.output + 'BRIGHTSCRIPT: ERROR: unexpected after caught diagnostic' },
        { ...valid, output: `EXPECTED_PARSEJSON_BEGIN\n${parseDiagnostic}\nBRIGHTSCRIPT: ERROR: unexpected\nEXPECTED_PARSEJSON_END\n${valid.output}` },
        { ...valid, output: valid.output + 'BrightScript Debugger' },
        { ...valid, output: valid.output + 'FIXTURE_DRIVER_ERROR: unknown key' },
        { ...valid, output: valid.output + valid.output },
    ];
    for (const control of controls) assert.throws(() => validate(control, marker, parseDiagnostic));
});

test('owned child execution enforces timeout, output bound and nonzero exit', { timeout: 10000 }, async () => {
    const marker = `STITCH_ACCOUNT_SETTINGS_PASS:${randomUUID()}`;
    const parseDiagnostic = await expectedParseDiagnostic();
    const timedOut = await runChild(['-e', 'setInterval(() => {}, 1000)'], root, 250);
    assert.equal(timedOut.timedOut, true);
    assert.throws(() => validate(timedOut, marker, parseDiagnostic), /timed out/);
    const exceeded = await runChild(['-e', 'process.stdout.write("x".repeat(2 * 1024 * 1024))'], root, 3000);
    assert.equal(exceeded.exceeded, true);
    assert.throws(() => validate(exceeded, marker, parseDiagnostic), /output limit/);
    const nonzero = await runChild(['-e', 'process.exit(7)'], root, 3000);
    assert.equal(nonzero.code, 7);
    assert.throws(() => validate(nonzero, marker, parseDiagnostic), /exited 7/);
});
