'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { spawnSync } = require('node:child_process');
const { prepareDecoder } = require('../prepare-source-map-decoder');

const wrapper = require.resolve('source-map-resolve/lib/decode-uri-component.js');
const caller = createRequire(wrapper);
const resolver = require('source-map-resolve');
const sourceMap = JSON.stringify({ version: 3, sources: ['snowman-%E2%98%83+%25.js'], names: [], mappings: '' });
const code = '//# sourceMappingURL=map%20name+%25.json';
const base = 'https://fixture.invalid/build/output.js';
function read(url) {
    if (url === 'https://fixture.invalid/build/map name+%.json') return sourceMap;
    if (url === 'https://fixture.invalid/build/snowman-☃+%.js') return 'fixture source';
    throw new Error('Unexpected source-map read: ' + url);
}

test('patched installed decoder preserves synchronous and asynchronous source-map reads', async () => {
    const decoderFile = caller.resolve('decode-uri-component');
    assert.equal(JSON.parse(fs.readFileSync(path.join(path.dirname(decoderFile), 'package.json'))).version, '0.5.1');
    const sync = resolver.resolveSync(code, base, read);
    assert.deepEqual(sync.sourcesContent, ['fixture source']);
    const asyncResult = await new Promise((resolve, reject) => resolver.resolve(code, base, (url, callback) => {
        try { callback(null, read(url)); } catch (error) { callback(error); }
    }, (error, result) => error ? reject(error) : resolve(result)));
    assert.deepEqual(asyncResult.sourcesContent, sync.sourcesContent);
    const decode = caller('./decode-uri-component');
    assert.equal(decode('literal+%2B%2525'), 'literal++%25');
    assert.equal(decode('%ZZ%41'), '%ZZA');
});

test('installation adapter is idempotent and the old callable-import path is rejected', () => {
    const before = fs.readFileSync(wrapper, 'utf8');
    assert.equal(prepareDecoder(), false);
    assert.equal(fs.readFileSync(wrapper, 'utf8'), before);
    const original = before.replace('require("decode-uri-component").default', 'require("decode-uri-component")');
    assert.notEqual(original, before);
    const module = { exports: {} };
    vm.runInNewContext(original, { require: caller, module });
    assert.throws(() => module.exports('encoded%20path'), /decodeUriComponent is not a function/);
});

test('malformed percent input completes in a bounded child using the patched real wrapper', { timeout: 15000 }, () => {
    const script = 'const decode=require(process.argv[1]); const input="%ab".repeat(8192); if(decode(input)!==input)process.exit(2); console.log("DECODE_BOUNDED_PASS");';
    const result = spawnSync(process.execPath, ['-e', script, wrapper], {
        encoding: 'utf8', timeout: 10000, maxBuffer: 1024, windowsHide: true,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), 'DECODE_BOUNDED_PASS');
});
