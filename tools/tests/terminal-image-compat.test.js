'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { stripVTControlCharacters } = require('node:util');

test('simulator terminal images retain PNG decoding, resize and ANSI rendering with patched Zod', { timeout: 15000 }, async () => {
    const engineRequire = createRequire(require.resolve('brs-node/package.json'));
    const terminalPath = engineRequire.resolve('terminal-image');
    const imageRequire = createRequire(terminalPath);
    const { Jimp } = imageRequire('jimp');
    const { default: terminalImage } = await import(pathToFileURL(terminalPath).href);
    const source = await fs.readFile(path.resolve(__dirname, '../../images/default_banner.png'));
    const image = await Jimp.fromBuffer(source);
    image.resize({ w: 12, h: 8 });
    const png = await image.getBuffer('image/png');
    const decoded = await Jimp.fromBuffer(png);
    assert.equal(decoded.bitmap.width, 12);
    assert.equal(decoded.bitmap.height, 8);
    const rendered = await terminalImage.buffer(png, {
        width: 12, height: 4, preserveAspectRatio: false, preferNativeRender: false,
    });
    const lines = stripVTControlCharacters(rendered).split(/\r?\n/);
    assert.equal(lines.length, 4);
    assert.ok(lines.every(line => line.length === 12 && line.includes('\u2584')));
});
