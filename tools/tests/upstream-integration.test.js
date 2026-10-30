'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const fixture = 'tools/tests/fixtures/upstream-integration';
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const original = JSON.parse(read(`${fixture}/upstream-contracts.json`));

test('actual changelog preserves every upstream release and shows updates through 3.2.1 after 2.9.0', () => {
    const result = spawnSync(process.execPath, [
        path.join(root, 'node_modules/brs-node/bin/brs.cli.js'),
        '--no-sg', '--root', root, 'source/changelog.brs', `${fixture}/changelog-main.brs`,
    ], { cwd: root, encoding: 'utf8', timeout: 20000, maxBuffer: 512 * 1024, windowsHide: true });
    assert.ifError(result.error);
    const output = `${result.stdout || ''}\n${result.stderr || ''}`;
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger/i);
    const matches = [...output.matchAll(/^UPSTREAM_CHANGELOG_JSON:\s*(\{[^\r\n]+\})/gm)];
    assert.equal(matches.length, 1, output);
    const actual = JSON.parse(matches[0][1]);
    for (const [version, notes] of Object.entries(original.changelog)) {
        assert.deepEqual(actual.entries[version], notes, `upstream ${version} history`);
    }
    assert.deepEqual(actual.versions, ['2.4.0', '2.5.0', '2.5.1', '2.6.0', '2.7.0', '2.8.0', '2.9.0', '3.1.0', '3.2.0', '3.2.1']);
    assert.deepEqual(actual.pending, ['3.1.0', '3.2.0', '3.2.1']);
    assert.match(actual.entries['3.1.0'][0], /^3\.1\.0:/);
    assert.ok(actual.entries['3.1.0'].some(line => line.includes('Support Stitch')));
});

test('upstream support action, exact QR asset and funding stay attached to the redesigned app', () => {
    const settings = JSON.parse(read('settings/settings.json'));
    assert.deepEqual(settings.find(setting => setting.settingName === 'support'), original.supportSetting);
    assert.equal(settings.filter(setting => setting.settingName === 'support').length, 1);
    assert.equal(read('.github/FUNDING.yml').replace(/\r\n/g, '\n'), original.funding.replace(/\r\n/g, '\n'));
    const qr = fs.readFileSync(path.join(root, 'images/qr_buymeacoffee.png'));
    assert.equal(createHash('sha256').update(qr).digest('hex'), original.donationQrSha256);
    const readme = read('README.md');
    for (const link of [
        'https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/latest',
        'https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues',
        'https://discord.gg/tZFrCAMxnB',
        'https://www.buymeacoffee.com/jeremyalbinet',
    ]) assert.ok(readme.includes(link), link);
    assert.ok(read('components/heroScene.brs').includes('Visit bit.ly/roku-twitch'));
    assert.match(read('manifest'), /^ui_resolutions=hd\s*$/m);
});

test('support translations are complete UTF-8 messages in all three catalogs', () => {
    for (const locale of ['en_US', 'es_MX', 'pt_BR']) {
        const xml = read(`locale/${locale}/translations.ts`);
        assert.doesNotMatch(xml, /\uFFFD/);
        for (const source of ['Support Stitch', original.supportSetting.description]) {
            const messages = [...xml.matchAll(/<message\b[^>]*>([\s\S]*?)<\/message>/g)]
                .map(match => match[1]).filter(message => message.includes(`<source>${source}</source>`));
            assert.equal(messages.length, 1, `${locale}: ${source}`);
            const translation = messages[0].match(/<translation[^>]*>([\s\S]*?)<\/translation>/)?.[1];
            assert.ok(translation, `${locale}: nonempty translation`);
            assert.doesNotMatch(translation, /\?|\uFFFD/, `${locale}: intact translation`);
        }
    }
});

test('package metadata and future publication point to the upstream owner', () => {
    const pkg = JSON.parse(read('package.json'));
    const lock = JSON.parse(read('package-lock.json'));
    assert.equal(pkg.name, '@jeremy-albinet/stitch-revitalized-for-roku');
    assert.equal(lock.name, pkg.name);
    assert.equal(lock.packages[''].name, pkg.name);
    assert.match(read('fmp4-demux-proxy/Dockerfile'), /github\.com\/jeremy-albinet\/Stitch-Revitalized-For-Roku/);
    assert.match(read('fmp4-demux-proxy/README.md'), /ghcr\.io\/jeremy-albinet\/fmp4-demux-proxy:0\.3\.2/);
    assert.match(read('.github/workflows/docker-publish.yml'), /ghcr\.io\/\$\{\{ github\.repository_owner \}\}\/fmp4-demux-proxy/);
    assert.match(read('.github/workflows/ci.yml'), /runs-on: ubuntu-latest/);
});
