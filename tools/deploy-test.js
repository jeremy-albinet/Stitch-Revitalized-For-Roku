#!/usr/bin/env node
const path = require('path');
const { spawnSync, spawn } = require('child_process');

const host = process.env.ROKU_HOST || 'localhost';
const sideloadPort = process.env.ROKU_SIDELOAD_PORT || '8888';
const password = process.env.ROKU_PASSWORD || 'rokudev';

const zip = path.join(__dirname, '..', 'out', 'Stitch-Revitalized-For-Roku.zip');

console.log(`Deploying to ${host}:${sideloadPort}...`);
const deploy = spawnSync('curl', [
    '-s', '--max-time', '30', '--digest',
    '-u', `rokudev:${password}`,
    '-F', 'mysubmit=Install',
    '-F', `archive=@${zip}`,
    `http://${host}:${sideloadPort}/plugin_install`,
    '-o', '/dev/null',
], { stdio: 'inherit' });
if (deploy.status !== 0) {
    console.error('Deploy failed');
    process.exit(1);
}

console.log('Deployed. Streaming test output (Ctrl+C to stop)...\n');
const nc = spawn('nc', ['-w', '30', host, '8085'], { stdio: ['pipe', 'inherit', 'inherit'] });
nc.stdin.write('\n');

nc.on('close', () => process.exit(0));
process.on('SIGINT', () => { nc.kill(); process.exit(0); });
