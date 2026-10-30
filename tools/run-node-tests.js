'use strict';

const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

// Bound engine contention without increasing any fixture deadline or the
// smaller default pool on constrained hosts.
const concurrency = Math.min(2, Math.max(1, os.availableParallelism() - 1));
const cwd = path.resolve(__dirname, '..');
const files = fs.readdirSync(path.join(cwd, 'tools/tests'))
    .filter(file => file.endsWith('.test.js')).sort();
const core = 'roku-demux-core.test.js';
if (!files.includes(core)) throw new Error('Core binary regression is missing');
if (!files.includes('roku-vod-chunks.test.js')) throw new Error('Recorded chunk regression is missing');

// Complete binary matrices and long VOD playlist scans approach their child
// deadlines on Windows when competing with another engine. Run them alone.
const isolated = [core, 'roku-vod-chunks.test.js', 'roku-vod-index.test.js',
    'roku-vod-preflight.test.js', 'roku-vod-protocol.test.js'].filter(file => files.includes(file));
for (const [limit, batch] of [[1, isolated], [concurrency, files.filter(file => !isolated.includes(file))]]) {
    if (batch.length === 0) continue;
    const result = spawnSync(process.execPath, [
        '--test', `--test-concurrency=${limit}`, ...batch.map(file => `tools/tests/${file}`)
    ], {cwd, stdio: 'inherit', windowsHide: true});
    if (result.error) process.stderr.write('Node regression runner could not start\n');
    const code = Number.isInteger(result.status) ? result.status : 1;
    if (code !== 0) {
        process.exitCode = code;
        break;
    }
}
