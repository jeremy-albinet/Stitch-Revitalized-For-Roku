#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const fixtureDir = path.join(root, 'source', 'tests', 'offline');
const cli = path.join(root, 'node_modules', 'brs-node', 'bin', 'brs.cli.js');

async function runFixture(file, include, baseUrl) {
    const args = [cli, '--no-sg', '--root', root];
    if (baseUrl) args.push('--deep-link', `fixtureUrl=${baseUrl}`);
    args.push(...include, path.relative(root, path.join(fixtureDir, file)));
    await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, args, { cwd: root, windowsHide: true });
        let output = '';
        const timer = setTimeout(() => {
            child.kill();
            reject(new Error(`${file}: timed out`));
        }, 30000);
        const collect = data => {
            output += data.toString();
            if (output.length > 1024 * 1024) {
                child.kill();
                reject(new Error(`${file}: excessive output`));
            }
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', code => {
            clearTimeout(timer);
            if (code !== 0 || output.includes('STITCH_TEST_FAIL:') || !output.includes('STITCH_TEST_PASS:')) {
                reject(new Error(`${file}: failed (exit ${code})\n${output}`));
            } else {
                const markers = output.split(/\r?\n/).filter(line => line.includes('STITCH_TEST_PASS:'));
                console.log(markers.join('\n').trim());
                resolve();
            }
        });
    });
}

async function main() {
    const server = http.createServer((req, res) => {
        if (req.url === '/slow') {
            setTimeout(() => { if (!res.destroyed) res.end('{"late":true}'); }, 1000);
        } else if (req.url === '/pending') {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end('{"message":"authorization_pending"}');
        } else if (req.url === '/unavailable') {
            res.writeHead(503, { 'Content-Type': 'application/json' });
            res.end('{"message":"temporary"}');
        } else if (req.url === '/invalid-json') {
            res.end('not JSON');
        } else {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end('{"ok":true,"values":[1,2,3]}');
        }
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    try {
        const fixtures = fs.readdirSync(fixtureDir).filter(file => file.endsWith('.brs')).sort();
        let suites = 0;
        for (const file of fixtures) {
            const content = fs.readFileSync(path.join(fixtureDir, file), 'utf8');
            if (!/\bsub\s+main\s*\(/i.test(content)) continue;
            suites++;
            const include = [...content.matchAll(/^'\s*@include\s+(.+)$/gm)].map(match => match[1].trim());
            if (include.length === 0) throw new Error(`${file}: declare helper paths using '@include`);
            await runFixture(file, include, file.startsWith('http-') ? baseUrl : undefined);
        }
        if (suites === 0) throw new Error('No offline fixture entry points were found');
        console.log(`${suites} offline fixture suites passed`);
    } finally {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
    }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
