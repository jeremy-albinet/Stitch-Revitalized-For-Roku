'use strict';

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');

// Advertised 7TV 1x rendition, downloaded once for offline codec-container tests:
// https://cdn.7tv.app/emote/01FSNK0GP000038GDBZ91HT6SQ/1x.webp
const petpet = fs.readFileSync(path.join(__dirname, 'petpet.webp'));
assert.equal(createHash('sha256').update(petpet).digest('hex'), 'd79d858422f971f762b7cde51e44c62bd0e1da8b14e0e929715b3ac7021e0a1d');
// Public BTTV 1x WebP renditions, captured 2026-10-25 for offline admission tests.
// https://cdn.betterttv.net/emote/5f1b0186cf6d2144653d2970/1x.webp
// https://cdn.betterttv.net/emote/566ca38765dbbdab32ec0560/1x.webp
const catjam = fs.readFileSync(path.join(__dirname, 'catjam.webp'));
const sourpls = fs.readFileSync(path.join(__dirname, 'sourpls.webp'));
assert.equal(createHash('sha256').update(catjam).digest('hex'), '036215ce8ae125082010cfca05cfc9fd46279e72a2f6d208fc4fa7e1e4bd4b9a');
assert.equal(createHash('sha256').update(sourpls).digest('hex'), 'f0939e5effe77aff814e59f5975e3019d96509b88c3f9436ced3d5aa18eb31b4');
const u24 = value => { const b = Buffer.alloc(3); b.writeUIntLE(value, 0, 3); return b; };
const chunk = (tag, bytes) => {
    const header = Buffer.alloc(8);
    header.write(tag); header.writeUInt32LE(bytes.length, 4);
    return Buffer.concat([header, bytes, ...(bytes.length % 2 ? [Buffer.alloc(1)] : [])]);
};
const riff = chunks => {
    const body = Buffer.concat([Buffer.from('WEBP'), ...chunks]);
    const header = Buffer.alloc(8); header.write('RIFF'); header.writeUInt32LE(body.length, 4);
    return Buffer.concat([header, body]);
};
const chunks = [];
for (let pos = 12; pos < petpet.length;) {
    const length = petpet.readUInt32LE(pos + 4);
    chunks.push({tag: petpet.toString('ascii', pos, pos + 4), bytes: petpet.subarray(pos + 8, pos + 8 + length)});
    pos += 8 + length + length % 2;
}
const vp8x = chunks.find(c => c.tag === 'VP8X').bytes;
const anim = chunks.find(c => c.tag === 'ANIM').bytes;
const frame = chunks.find(c => c.tag === 'ANMF').bytes;

function animation({width = 32, height = 32, frames = 5, delay = 60, extra = []} = {}) {
    const canvas = Buffer.from(vp8x);
    u24(width - 1).copy(canvas, 4); u24(height - 1).copy(canvas, 7);
    const image = Buffer.from(frame); u24(delay).copy(image, 12);
    return riff([chunk('VP8X', canvas), chunk('ANIM', anim), ...extra,
        ...Array.from({length: frames}, () => chunk('ANMF', image))]);
}
const cases = [
    { name: 'real-petpet', bytes: petpet, valid: true, width: 32, height: 32, frames: 5, duration: 300 },
    { name: 'limit-512-frames', bytes: animation({frames: 512, delay: 10}), valid: true, frames: 512 },
    { name: 'limit-128-canvas', bytes: animation({width: 128, height: 128}), valid: true, loadWidth: 64, loadHeight: 64 },
    { name: '20-second-cycle', bytes: animation({frames: 2, delay: 10000}), valid: true },
    { name: 'pixel-budget', bytes: animation({width: 128, height: 128, frames: 64}), valid: true },
    { name: 'pixel-budget-exceeded', bytes: animation({width: 128, height: 128, frames: 65}), valid: false },
    { name: 'too-wide', bytes: animation({width: 129}), valid: false },
    { name: 'too-tall', bytes: animation({height: 129}), valid: false },
    { name: 'canvas-smaller-than-frame', bytes: animation({width: 1}), valid: false },
    { name: 'too-many-frames', bytes: animation({frames: 513, delay: 10}), valid: false },
    { name: 'too-long-cycle', bytes: animation({frames: 2, delay: 10001}), valid: false },
    { name: 'zero-duration', bytes: animation({delay: 0}), valid: false },
    { name: 'one-frame', bytes: animation({frames: 1}), valid: false },
    { name: 'empty', bytes: Buffer.alloc(0), valid: false },
    { name: 'non-webp', bytes: Buffer.alloc(100), valid: false },
    { name: 'truncated-header', bytes: petpet.subarray(0, 11), valid: false },
    { name: 'truncated-payload', bytes: petpet.subarray(0, petpet.length - 1), valid: false },
    { name: 'trailing-data', bytes: Buffer.concat([petpet, Buffer.alloc(2)]), valid: false },
    { name: 'too-many-chunks', bytes: animation({extra: Array.from({length: 1024}, () => chunk('JUNK', Buffer.alloc(0)))}), valid: false },
    { name: 'odd-padding', bytes: animation({extra: [chunk('JUNK', Buffer.from([1]))]}), valid: true },
    { name: 'duplicate-anim', bytes: animation({extra: [chunk('ANIM', anim)]}), valid: false },
    { name: 'duplicate-vp8x', bytes: animation({extra: [chunk('VP8X', vp8x)]}), valid: false },
    { name: 'missing-anim', bytes: riff([chunk('VP8X', vp8x), chunk('ANMF', frame), chunk('ANMF', frame)]), valid: false },
];
// Independent image-header fixtures cover lossless dimensions and the native
// decoder boundary; these contain no claim that a complete bitstream decodes.
function headerAnimation(width, height, {codec = 'VP8L', imageWidth = width, imageHeight = height, version = 0, nested = null} = {}) {
    const canvas = Buffer.from(vp8x); u24(width - 1).copy(canvas, 4); u24(height - 1).copy(canvas, 7);
    const frameHeader = Buffer.alloc(16); u24(width - 1).copy(frameHeader, 6); u24(height - 1).copy(frameHeader, 9); frameHeader[12] = 60;
    let image;
    if (codec === 'VP8L') {
        image = Buffer.alloc(5); image[0] = 0x2f;
        image.writeUInt32LE(imageWidth - 1 + (imageHeight - 1) * 16384 + version * 536870912, 1);
    } else {
        image = Buffer.from([0,0,0,0x9d,1,0x2a,0,0,0,0]); image.writeUInt16LE(imageWidth, 6); image.writeUInt16LE(imageHeight, 8);
    }
    const body = Buffer.concat([frameHeader, ...(nested || [chunk(codec, image)])]);
    return riff([chunk('VP8X', canvas), chunk('ANIM', anim), chunk('ANMF', body), chunk('ANMF', body)]);
}
cases.push(
    {name: 'lossless-header', bytes: headerAnimation(1,1), valid: true, width: 1, height: 1},
    {name: 'skinny-source', bytes: headerAnimation(1,128), valid: true, loadWidth: 1, loadHeight: 64},
    {name: 'wide-source', bytes: headerAnimation(128,1), valid: true, loadWidth: 64, loadHeight: 1},
    {name: 'lossless-mismatched-width', bytes: headerAnimation(32,32,{imageWidth:128}), valid: false},
    {name: 'lossless-mismatched-height', bytes: headerAnimation(32,32,{imageHeight:128}), valid: false},
    {name: 'lossless-version', bytes: headerAnimation(32,32,{version:1}), valid: false},
    {name: 'lossy-mismatched-width', bytes: headerAnimation(32,32,{codec:'VP8 ',imageWidth:128}), valid: false},
    {name: 'lossy-header', bytes: headerAnimation(32,32,{codec:'VP8 '}), valid: true},
    {name: 'missing-image-payload', bytes: headerAnimation(32,32,{nested:[]}), valid: false},
    {name: 'unknown-image-chunk', bytes: headerAnimation(32,32,{nested:[chunk('JUNK', Buffer.alloc(2))]}), valid: false},
);
for (const [name, change] of [
    ['riff-overflow', b => b.writeUInt32LE(0xffffffff, 4)],
    ['chunk-overflow', b => b.writeUInt32LE(0xffffffff, 16)],
    ['reserved-vp8x-bits', b => {b[20] |= 0x80;}],
    ['missing-animation-flag', b => {b[20] &= ~2;}],
    ['reserved-vp8x-bytes', b => {b[21] = 1;}],
]) { const bytes = Buffer.from(petpet); change(bytes); cases.push({name, bytes, valid: false}); }
for (const [name, offset, value] of [['bad-frame-x', 0, 16], ['bad-frame-y', 3, 16], ['bad-frame-flags', 15, 4]]) {
    const bad = Buffer.from(frame); bad[offset] = value;
    cases.push({name, bytes: riff([chunk('VP8X', vp8x), chunk('ANIM', anim), chunk('ANMF', bad), chunk('ANMF', frame)]), valid: false});
}
const noPadding = animation({extra: [chunk('JUNK', Buffer.from([1]))]}); noPadding[53] = 1;
cases.push({name: 'nonzero-padding', bytes: noPadding, valid: false});
const atLimit = animation({extra: [chunk('JUNK', Buffer.alloc(1048576 - animation().length - 8))]});
assert.equal(atLimit.length, 1048576);
cases.push({name: 'one-mib', bytes: atLimit, valid: true});
cases.push({name: 'over-one-mib', bytes: Buffer.concat([atLimit, Buffer.alloc(2)]), valid: false});

module.exports = {cases, petpet, catjam, sourpls, animation, chunk, riff};
