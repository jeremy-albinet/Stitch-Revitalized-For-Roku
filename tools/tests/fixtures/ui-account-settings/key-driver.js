'use strict';

const path = require('node:path');

// Runs the brs-node CLI in this process with stdin presented as a terminal so
// the engine's own keyboard path dispatches remote keys through the SceneGraph
// focus chain. The fixture app requests each key by printing
// "FIXTURE_KEY:<key>" or "FIXTURE_HOLD:<key>:<ms>"; nothing is replayed on a
// timeline, so slow machines only make the run slower.
// Usage: node key-driver.js <brs.cli.js> <package.zip>

const [cliArg, zipArg] = process.argv.slice(2);
if (!cliArg || !zipArg) {
    console.error('usage: node key-driver.js <brs.cli.js> <package.zip>');
    process.exit(2);
}
const cli = path.resolve(cliArg);
const zip = path.resolve(zipArg);

// Terminal key names that brs-node maps to Roku remote keys.
const keys = {
    up: 'up', down: 'down', left: 'left', right: 'right', ok: 'return',
    back: 'escape', play: 'end', rewind: 'pageup', fastforward: 'pagedown',
};
const holdLimitMs = 3000;
// brs-node releases a key 150 ms after its last terminal press and treats an
// earlier repeat of that key as the same held press. A different key releases
// the previous one at once, so only back-to-back identical presses are spaced.
// Requests stay in order.
const repeatGapMs = 250;
let nextFree = 0;
let lastKey = '';

function emit(name) {
    process.stdin.emit('keypress', '', { name, ctrl: false, meta: false, shift: false, sequence: '' });
}

function press(key, holdMs) {
    const name = keys[key];
    if (!name) {
        console.error(`FIXTURE_DRIVER_ERROR: unknown key ${key}`);
        process.exit(2);
    }
    const hold = Math.min(holdMs, holdLimitMs);
    const start = Math.max(Date.now() + 20, nextFree + (key === lastKey ? repeatGapMs : 30));
    nextFree = start + hold;
    lastKey = key;
    setTimeout(() => {
        // Repeated terminal presses of one key keep it held; the engine sends
        // a single press now and the release after the repeats stop.
        const started = Date.now();
        const repeat = () => {
            emit(name);
            if (Date.now() - started < hold) setTimeout(repeat, 50);
        };
        repeat();
    }, start - Date.now());
}

process.stdin.isTTY = true;
process.stdin.setRawMode = () => process.stdin;
process.argv = [process.argv[0], cli, zip];

const write = process.stdout.write.bind(process.stdout);
let pending = '';
process.stdout.write = (chunk, ...rest) => {
    pending += chunk.toString();
    const lines = pending.split(/\r?\n/);
    pending = lines.pop();
    for (const line of lines) {
        const match = line.match(/FIXTURE_(KEY|HOLD):(\w+)(?::(\d+))?/);
        if (match) press(match[2], match[1] === 'HOLD' ? Number(match[3]) : 0);
    }
    if (pending.length > 4096) pending = pending.slice(-256);
    return write(chunk, ...rest);
};

require(cli);
