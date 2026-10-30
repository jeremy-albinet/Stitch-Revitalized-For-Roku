'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { createRequire } = require('node:module');

// source-map-resolve 0.5.3 expects a callable CommonJS export. The patched
// decoder is ESM; Node 24 can require it, but its function is the default export.
// Keep the decoder itself untouched and adapt only this known caller.
const originalHash = 'f5cc0ce0462dcb496dd9b8e9953f5bc91ff517ab80f225865099fe457a221183';
const originalImport = 'var decodeUriComponent = require("decode-uri-component")';
const adaptedImport = originalImport + '.default';
const hash = text => createHash('sha256').update(text).digest('hex');

function prepareDecoder() {
    if (Number(process.versions.node.split('.')[0]) !== 24) throw new Error('This toolchain requires Node 24');
    const lock = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../package-lock.json'), 'utf8'));
    const copies = Object.keys(lock.packages).filter(name => /(?:^|\/)node_modules\/source-map-resolve$/.test(name));
    if (copies.length !== 1 || copies[0] !== 'node_modules/source-map-resolve') {
        throw new Error('Review source-map decoder compatibility for a changed dependency layout');
    }
    const wrapper = require.resolve('source-map-resolve/lib/decode-uri-component.js');
    const caller = createRequire(wrapper);
    const parent = JSON.parse(fs.readFileSync(path.resolve(path.dirname(wrapper), '../package.json'), 'utf8'));
    const decoderFile = caller.resolve('decode-uri-component');
    const decoder = JSON.parse(fs.readFileSync(path.join(path.dirname(decoderFile), 'package.json'), 'utf8'));
    if (parent.version !== '0.5.3' || decoder.version !== '0.5.1') {
        throw new Error('Review source-map decoder compatibility before changing its pinned versions');
    }
    if (typeof caller('decode-uri-component').default !== 'function') throw new Error('Decoder default export is not callable');
    const source = fs.readFileSync(wrapper, 'utf8').replace(/\r\n/g, '\n');
    const restored = source.replace(adaptedImport, originalImport);
    if (hash(restored) !== originalHash) throw new Error('Unexpected source-map decoder wrapper; refusing to modify it');
    if (source !== restored) return false;
    fs.writeFileSync(wrapper, source.replace(originalImport, adaptedImport));
    return true;
}

module.exports = { prepareDecoder };
if (require.main === module) {
    try {
        console.log(prepareDecoder() ? 'Adapted source-map-resolve to patched decode-uri-component 0.5.1' : 'Patched source-map decoder compatibility already prepared');
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
