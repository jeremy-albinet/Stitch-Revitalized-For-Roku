#!/usr/bin/env node
const path = require('path');
const { execSync, spawn } = require('child_process');

const host = process.env.ROKU_HOST || 'localhost';
const password = process.env.ROKU_PASSWORD || 'rokudev';

const zip = path.join(__dirname, '..', 'out', 'Stitch-Revitalized-For-Roku.zip');

console.log(`Deploying to ${host}...`);
try {
    execSync(
        `curl -s --max-time 30 --digest -u rokudev:${password} ` +
        `-F 'mysubmit=Install' -F 'archive=@${zip}' ` +
        `http://${host}/plugin_install -o /dev/null`,
        { stdio: 'inherit' }
    );
} catch (e) {
    console.error('Deploy failed:', e.message);
    process.exit(1);
}

console.log('Deployed. Streaming test output (Ctrl+C to stop)...\n');
const nc = spawn('nc', ['-w', '30', host, '8085'], { stdio: ['pipe', 'inherit', 'inherit'] });
nc.stdin.write('\n');

nc.on('close', () => process.exit(0));
process.on('SIGINT', () => { nc.kill(); process.exit(0); });
