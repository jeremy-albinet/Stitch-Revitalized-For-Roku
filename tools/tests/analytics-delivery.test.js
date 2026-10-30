'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const prefix = 'stitch-analytics-delivery-';

test('actual analytics handlers deliver startup snapshots and retry failed identification', {timeout: 30000}, async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    try {
        // This Task uses BrightScript syntax; copy the actual source without
        // instrumentation so the offline interpreter can load its .brs extension.
        await fs.copyFile(path.join(root, 'components/Tasks/Analytics/AnalyticsTask.bs'), path.join(dir, 'analytics.brs'));
        await fs.copyFile(path.join(__dirname, 'fixtures/analytics-delivery/main.brs'), path.join(dir, 'main.brs'));
        const result = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, [
                path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
                'analytics.brs', 'main.brs'
            ], {cwd: dir, windowsHide: true});
            let output = '';
            const timer = setTimeout(() => {child.kill(); reject(new Error('Analytics fixture timed out'));}, 20000);
            const collect = data => {
                output += data.toString();
                if (output.length > 1024 * 1024) child.kill();
            };
            child.stdout.on('data', collect);
            child.stderr.on('data', collect);
            child.on('error', error => {clearTimeout(timer); reject(error);});
            child.on('close', code => {clearTimeout(timer); resolve({code, output});});
        });
        assert.equal(result.code, 0, result.output);
        assert.doesNotMatch(result.output, /STITCH_TEST_FAIL:|EXIT_BRIGHTSCRIPT_CRASH/);
        assert.match(result.output, /STITCH_TEST_PASS: analytics startup and delivery/);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix) && path.basename(dir).length > prefix.length);
        await fs.rm(dir, {recursive: true, force: true});
    }
});
