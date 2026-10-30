'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/lifecycle');

async function addFile(dir, dest, data) {
    const file = path.join(dir, dest);
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, data);
}

test('SceneGraph permanent disposal stops resources and preserves retained navigation', { timeout: 30000 }, async () => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-lifecycle-'));
    const packageDir = path.join(temp, 'package');
    try {
        const sources = [
            'components/heroScene.brs',
            'components/SceneManager/Group/SceneManagerGroup.brs',
            'components/SceneManager/Group/SceneManagerGroup.xml',
            'source/utils/lifecycle.brs', 'source/utils/taskFactory.brs',
            'source/utils/sceneFactory.brs', 'source/utils/misc.brs', 'source/utils/analytics.brs',
            'components/Modules/EmojiLabel/EmojiLabel.xml',
            'components/Modules/EmojiLabel/EmojiLabel.brs',
            'components/Modules/EmojiLabel/EmojiLabelRegex.brs',
            'components/Modules/EmojiLabel/EmojiLabelUtil.brs',
        ];
        for (const file of sources) {
            let source = await fs.readFile(path.join(root, file), 'utf8');
            if (file === 'components/heroScene.brs') {
                // Base init runs before derived init. Exclude network/account
                // startup only; exercise the actual navigation/disposal bodies.
                source = source.replace(/^sub init\(\)[\s\S]*?^end sub/m, 'sub init()\nend sub');
            }
            await addFile(packageDir, file, source);
        }
        for (const file of ['main.brs', 'owner.brs', 'screen.brs', 'config.brs']) {
            await addFile(packageDir, file === 'main.brs' ? 'source/main.brs' : `components/${file}`, await fs.readFile(path.join(fixtures, file)));
        }
        await addFile(packageDir, 'manifest', 'title=Offline Lifecycle Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await addFile(packageDir, 'components/OwnerBase.xml', `<component name="OwnerBase" extends="Scene">
          <interface><function name="onDestroy" /></interface>
          <script uri="pkg:/components/heroScene.brs" />
          <script uri="pkg:/source/utils/lifecycle.brs" />
          <script uri="pkg:/source/utils/taskFactory.brs" />
          <script uri="pkg:/source/utils/sceneFactory.brs" />
          <script uri="pkg:/source/utils/misc.brs" />
          <script uri="pkg:/source/utils/analytics.brs" />
          <script uri="config.brs" />
        </component>`);
        await addFile(packageDir, 'components/Owner.xml', `<component name="Owner" extends="OwnerBase">
          <interface>
            <field id="active" type="node" /><field id="saved" type="node" /><field id="sidebarResource" type="node" />
            <field id="exitApp" type="boolean" value="false" />
            <function name="begin" /><function name="retain" /><function name="goBack" />
            <function name="switchTab" /><function name="login" /><function name="logout" /><function name="disposeAgain" />
            <function name="rootBack" />
          </interface><script uri="owner.brs" />
        </component>`);
        for (const name of ['Following', 'ChannelPage', 'Settings', 'InheritedFollowing']) {
            // Check the explicit public contract on actual concrete scenes.
            if (name !== 'InheritedFollowing') {
                const sceneXml = await fs.readFile(path.join(root, `components/Scenes/${name}/${name === 'Settings' ? 'settings' : name}.xml`), 'utf8');
                assert.match(sceneXml, /<function\s+name="onDestroy"\s*\/>/);
            }
            await addFile(packageDir, `components/${name}.xml`, `<component name="${name}" extends="SceneManagerGroup">
              <interface>
                ${name === 'InheritedFollowing' ? '' : '<function name="onDestroy" />'}
                <field id="ticks" type="integer" value="0" /><field id="cleanupCalls" type="integer" value="0" />
                <field id="touches" type="integer" value="0" /><field id="contentRequested" type="node" />
                <function name="touch" />
              </interface>
              <children><Timer id="timer" repeat="true" duration="0.025" /><EmojiLabel id="label" /></children>
              <script uri="screen.brs" />
            </component>`);
        }
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const output = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd: temp, windowsHide: true });
            let output = '';
            let outputExceeded = false;
            const timer = setTimeout(() => { child.kill(); reject(new Error('SceneGraph fixture timed out')); }, 25000);
            const collect = data => {
                if (outputExceeded) return;
                output += data.toString();
                if (output.length > 1024 * 1024) {
                    outputExceeded = true;
                    child.kill();
                }
            };
            child.stdout.on('data', collect);
            child.stderr.on('data', collect);
            child.on('error', error => { clearTimeout(timer); reject(error); });
            child.on('close', code => {
                clearTimeout(timer);
                if (outputExceeded) reject(new Error('SceneGraph fixture exceeded output limit'));
                else if (code !== 0) reject(new Error(`SceneGraph fixture exited ${code}\n${output}`));
                else resolve(output);
            });
        });
        assert.ok(!output.includes('STITCH_TEST_FAIL:'), output);
        assert.ok(output.includes('STITCH_TEST_PASS: SceneGraph lifecycle'), output);
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith('stitch-lifecycle-'), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
});
