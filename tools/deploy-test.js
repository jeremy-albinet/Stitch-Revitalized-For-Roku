#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');

function parseRooibosResult(output, runId) {
    const text = output.replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '').replace(/\r/g, '');
    const marker = `STITCH_TEST_START: ${runId}`;
    const start = text.lastIndexOf(marker);
    if (start < 0) return { status: 'pending' };
    const current = text.slice(start + marker.length);
    if (/\b[1-9]\d*\s+(?:failing|crashed)\b|BrightScript Debugger>|BRIGHTSCRIPT: ERROR/i.test(current)) {
        return { status: 'failed' };
    }
    const summary = current.match(/^\s*(\d+)\s+passed(?:\s+\([^\n]*\))?\s*$/m);
    if (!summary || Number(summary[1]) === 0) return { status: 'pending' };
    return { status: 'passed', count: Number(summary[1]) };
}

function watchTestOutput(socket, runId, timeoutMs) {
    let output = '';
    let settled = false;
    let quietTimer;
    let finish;
    const result = new Promise((resolve, reject) => {
        const deadline = setTimeout(() => finish(new Error('Timed out waiting for this test package')), timeoutMs);
        finish = error => {
            if (settled) return;
            settled = true;
            clearTimeout(deadline);
            clearTimeout(quietTimer);
            const state = parseRooibosResult(output, runId);
            if (error) reject(error);
            else if (state.status !== 'passed') reject(new Error('Test run did not complete successfully'));
            else resolve(state);
        };
        socket.on('data', chunk => {
            process.stdout.write(chunk);
            output += chunk.toString();
            if (output.length > 2 * 1024 * 1024) return finish(new Error('Exceeded test console output limit'));
            clearTimeout(quietTimer);
            const state = parseRooibosResult(output, runId);
            if (state.status === 'failed') finish(new Error('Rooibos reported a failure or crash'));
            else if (state.status === 'passed') quietTimer = setTimeout(() => finish(), 1000);
        });
        socket.on('error', () => finish(new Error('Test console connection failed')));
        socket.on('close', () => finish());
    });
    result.catch(() => {});
    return { result, stop: () => finish(new Error('Test run interrupted')) };
}

async function deploy(zip, host, port, password) {
    await new Promise((resolve, reject) => {
        const child = spawn('curl', [
            '--silent', '--show-error', '--fail-with-body', '--max-time', '30', '--digest',
            '-u', `rokudev:${password}`, '-F', 'mysubmit=Install', '-F', `archive=@${zip}`,
            `http://${host}:${port}/plugin_install`,
        ], { windowsHide: true });
        let response = '';
        child.stdout.on('data', chunk => { response += chunk.toString(); });
        child.stderr.on('data', () => {});
        child.on('error', () => reject(new Error('Could not start curl for sideloading')));
        child.on('close', code => {
            if (code !== 0 || !/Install Success|Application Installed Successfully/i.test(response)
                || /Install Failure|Compilation Failed|Syntax Error/i.test(response)) {
                reject(new Error('Device rejected the test package or sideloading failed'));
            } else resolve();
        });
    });
}

async function main() {
    const host = process.env.ROKU_HOST || 'localhost';
    const local = ['localhost', '127.0.0.1', '::1'].includes(host);
    const password = process.env.ROKU_PASSWORD || (local ? 'rokudev' : undefined);
    if (!password) throw new Error('Set ROKU_PASSWORD for the selected device');
    const sideloadPort = process.env.ROKU_SIDELOAD_PORT || (local ? '8888' : '80');
    const consolePort = Number(process.env.ROKU_CONSOLE_PORT || '8085');
    const timeoutMs = Number(process.env.ROKU_TEST_TIMEOUT_MS || '120000');
    if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 600000) throw new Error('Invalid test timeout');
    if (!Number.isInteger(consolePort) || consolePort < 1 || consolePort > 65535) throw new Error('Invalid console port');
    if (!/^\d+$/.test(sideloadPort) || Number(sideloadPort) < 1 || Number(sideloadPort) > 65535) throw new Error('Invalid sideload port');
    const zip = path.join(__dirname, '..', 'out', 'Stitch-Revitalized-For-Roku-tests.zip');
    const identityPath = path.join(__dirname, '..', 'out', 'test-run-id');
    if (!fs.existsSync(zip) || !fs.existsSync(identityPath)) throw new Error('Run npm run test:compile first');
    const runId = fs.readFileSync(identityPath, 'utf8').trim();
    const socket = net.createConnection({ host, port: consolePort });
    const watcher = watchTestOutput(socket, runId, timeoutMs);
    const onInterrupt = () => { watcher.stop(); socket.destroy(); };
    process.once('SIGINT', onInterrupt);
    try {
        await new Promise((resolve, reject) => {
            const connectTimeout = setTimeout(() => { socket.destroy(); reject(new Error('Test console connection timed out')); }, 5000);
            socket.once('connect', () => { clearTimeout(connectTimeout); resolve(); });
            socket.once('error', () => { clearTimeout(connectTimeout); reject(new Error('Test console is unavailable')); });
        });
        socket.write('\r\n');
        console.log(`Deploying test package to ${host}:${sideloadPort}...`);
        await deploy(zip, host, sideloadPort, password);
        const state = await watcher.result;
        console.log(`Fresh package: ${state.count} Rooibos tests passed`);
    } finally {
        watcher.stop();
        socket.destroy();
        process.removeListener('SIGINT', onInterrupt);
    }
}

module.exports = { parseRooibosResult };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
