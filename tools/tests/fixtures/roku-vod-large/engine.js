"use strict";
// Large-fixture child only. brs-node 2.6.2 handles byte reads without copying.
// Observe the first numeric read while delegating every read to the engine.
const assert = require('node:assert/strict');
const path = require('node:path');
const sdk = require('brs-node');
const originalGet = sdk.RoByteArray.prototype.get;
function install(firstNumericRead) {
    let observed = false;
    sdk.RoByteArray.prototype.get = function get(index) {
        const numeric = sdk.isBoxedNumber(index) ? index.unbox() : index;
        if (!observed && firstNumericRead && [sdk.ValueKind.Int32, sdk.ValueKind.Int64, sdk.ValueKind.Float, sdk.ValueKind.Double].includes(numeric.kind)) {
            observed = true;
            firstNumericRead();
        }
        return originalGet.call(this, index);
    };
    return originalGet;
}
function controls() {
    const before = sdk.RoByteArray.prototype.get;
    const data = new sdk.RoByteArray(Uint8Array.from({length: 256}, (_, i) => i));
    const indices = [new sdk.Int32(0), new sdk.Int32(127), new sdk.Int32(128), new sdk.Int32(255),
        new sdk.Int32(256), new sdk.Int32(-1), new sdk.Float(1.9), new sdk.Float(-0.9),
        new sdk.Float(-1.9), new sdk.Float(255.9), new sdk.Float(256.1),
        new sdk.Float(NaN), new sdk.Float(Infinity), new sdk.Float(-Infinity),
        new sdk.Double(1), new sdk.Int64(1), sdk.BrsInvalid.Instance,
        new sdk.RoInt(new sdk.Int32(128)), new sdk.RoFloat(new sdk.Float(127.9)),
        new sdk.RoLongInteger(new sdk.Int64(1)), new sdk.RoDouble(new sdk.Double(1)),
        new sdk.BrsString('count'), new sdk.BrsString('missing')];
    const expected = indices.map(index => before.call(data, index));
    install();
    let assertions = 0;
    try {
        indices.forEach((index, n) => {
            const actual = data.get(index), old = expected[n];
            assert.equal(actual.kind, old.kind); assertions++;
            if (actual.kind === sdk.ValueKind.Int32) {assert.equal(actual.getValue(), old.getValue()); assertions++;}
            else {assert.equal(actual, old); assertions++;}
        });
        for (let n = 0; n < 256; n++) {
            assert.equal(data.get(new sdk.Int32(n)).getValue(), before.call(data, new sdk.Int32(n)).getValue()); assertions++;
        }
        assert.equal(data.getByteArray().length, 256); assertions++;
        assert.deepEqual([...data.getByteArray()], Array.from({length:256},(_,i)=>i)); assertions++;
        const empty = new sdk.RoByteArray();
        for (const index of [new sdk.Int32(0), new sdk.Int32(-1), new sdk.Float(NaN)]) {
            assert.equal(empty.get(index), before.call(empty, index)); assertions++;
        }
    } finally {
        sdk.RoByteArray.prototype.get = before;
    }
    assert.equal(sdk.RoByteArray.prototype.get, originalGet); assertions++;
    console.log('VOD_LARGE_ENGINE_CONTROLS ' + JSON.stringify({assertions, restored:true}));
}
async function launch() {
    const args = process.argv.slice(2);
    assert.equal(args[0], '--no-sg'); assert.equal(args[1], '--root');
    const root = args[2]; assert.ok(path.isAbsolute(root));
    assert.equal(args[3], '--worker-marker');
    const marker = args[4]; assert.match(marker,/^[0-9a-f-]{36}$/);
    const files = args.slice(5);
    assert.ok(files.length > 0 && files.every(file => path.basename(file) === file && file.endsWith('.brs')));
    process.env.STITCH_VOD_LARGE_WORKER_MARKER = marker;
    const payload = await sdk.createPayloadFromFiles(files,{entryPoint:true,debugOnCrash:false},new Map(),root);
    payload.extensions = []; // The same --no-sg/no-extension fixture policy as the ordinary CLI.
    sdk.subscribeHost('vod-large-fixture',(event,value) => {
        if (event === 'stdout') process.stdout.write(value);
        else if (event === 'stderr') process.stderr.write(value);
        else if (event === 'error') {process.stderr.write(String(value)+'\n'); process.exitCode=1;}
        else if (event === 'warning') process.stderr.write(String(value)+'\n');
        else if (event === 'message' && typeof value === 'string') {
            const comma = value.indexOf(','), kind = value.slice(0,comma), text = value.slice(comma+1);
            if (kind === 'print') process.stdout.write(text);
            else if (kind === 'error') {process.stderr.write(text+'\n'); process.exitCode=1;}
            else if (kind === 'warning') process.stderr.write(text+'\n');
            else if (kind === 'end' && text.trim() !== sdk.AppExitReason.UserNav) process.exitCode=1;
        }
    });
    try {
        const result = await sdk.executeApp(payload,{workerEntry:path.join(__dirname,'engine-worker.js')});
        if (result.exitReason !== sdk.AppExitReason.UserNav) {
            process.stderr.write('VOD_LARGE_ENGINE_EXIT '+result.exitReason+'\n'); process.exitCode=1;
        }
    } finally {
        sdk.unsubscribeHost('vod-large-fixture');
    }
}
if (require.main === module) {
    if (process.argv[2] === '--controls') controls();
    else launch().catch(error => {process.stderr.write(error.stack+'\n'); process.exitCode=1;});
}
module.exports = {install, originalGet};
