'use strict';

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');

// Twitch's published IRC example, fetched unchanged 2026-10-25. One public
// sample, bounded to 1 MiB / 10 seconds, no redirects, cookies or credentials.
// https://dev.twitch.tv/docs/chat/irc/#privmsg-tags
const uri = 'https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=095d7a5dzizsiwgabonagkmigggv8v1spfai91ac3x0dsiy0&ep=v1_gifs_trending&rid=giphy.gif&ct=g';
const official = fs.readFileSync(path.join(__dirname, 'twitch-official.gif'));
assert.equal(official.length, 998959);
assert.equal(createHash('sha256').update(official).digest('hex'), 'c6fb00eda3e154dd1a2be3f77ffe1fc12443a39464b63fc6cfa0748d9b5ffd42');

const u16 = n => {const b = Buffer.alloc(2); b.writeUInt16LE(n); return b;};
const palette = Buffer.from([0,0,0,255,255,255]);
const gce = delay => Buffer.from([0x21,0xf9,4,0,...u16(delay),0,0]);
const loop = Buffer.from([0x21,0xff,11,...Buffer.from('NETSCAPE2.0'),3,1,0,0,0]);
const comment = body => Buffer.concat([Buffer.from([0x21,0xfe]), body]);
const image = ({width = 1, height = 1, x = 0, y = 0, local = false} = {}) =>
    Buffer.from([0x2c,...u16(x),...u16(y),...u16(width),...u16(height),local ? 0x80 : 0,
        ...(local ? palette : []),2,2,0x44,0x01,0]);
// Authored structural containers; declared large canvases are not decoder tests.
function gif({width = 1, height = 1, frames = 2, delay = 6, global = true, local = false, extra = [], frame = null} = {}) {
    return Buffer.concat([Buffer.from('GIF89a'), u16(width), u16(height), Buffer.from([global ? 0x80 : 0,0,0]),
        ...(global ? [palette] : []), ...extra,
        ...Array.from({length: frames}, () => Buffer.concat([gce(delay), frame || image({width,height,local})])), Buffer.from([0x3b])]);
}
const tiny = gif();
const cases = [
    {name: 'official-twitch', bytes: official, valid: true, width: 480, height: 480, frames: 15, duration: 990, loadWidth: 64, loadHeight: 64},
    {name: 'tiny', bytes: tiny, valid: true, width: 1, height: 1, frames: 2, duration: 120, loadWidth: 1, loadHeight: 1},
    {name: 'local-table', bytes: gif({global:false,local:true}), valid: true},
    {name: 'local-overrides-global', bytes: gif({local:true}), valid: true},
    {name: 'loop-extension', bytes: gif({extra:[loop]}), valid: true},
    {name: 'comments', bytes: gif({extra:[comment(Buffer.from([3,1,2,3,0]))]}), valid: true},
    {name: 'minimum-delay-cycle', bytes: gif({frames:5,delay:2}), valid: true},
    {name: 'short-cycle', bytes: gif({frames:4,delay:2}), valid: false},
    {name: '20-second-cycle', bytes: gif({delay:1000}), valid: true},
    {name: 'too-long-cycle', bytes: gif({delay:1001}), valid: false},
    {name: '128-frames', bytes: gif({frames:128}), valid: true, frames:128},
    {name: '129-frames', bytes: gif({frames:129}), valid: false},
    {name: 'source-pixel-limit', bytes: gif({width:512,height:512,frames:16}), valid:true},
    {name: 'source-pixel-overflow', bytes: gif({width:512,height:512,frames:17}), valid:false},
    {name: 'too-wide', bytes: gif({width:513}), valid:false},
    {name: 'too-tall', bytes: gif({height:513}), valid:false},
    {name: 'skinny', bytes: gif({width:1,height:512}), valid:true, loadWidth:1,loadHeight:64},
    {name: 'wide', bytes: gif({width:512,height:1}), valid:true, loadWidth:64,loadHeight:1},
    {name: 'no-palette', bytes: gif({global:false}), valid:false},
    {name: 'empty-width', bytes: gif({width:0}), valid:false},
    {name: 'empty-height', bytes: gif({height:0}), valid:false},
    {name: 'out-of-canvas', bytes: gif({frame:image({x:1})}), valid:false},
    {name: 'rectangle-overflow', bytes: gif({frame:image({x:65535,width:65535})}), valid:false},
    {name: 'empty-rectangle', bytes: gif({frame:image({width:0})}), valid:false},
    {name: 'one-frame', bytes:gif({frames:1}),valid:false},
    {name: 'zero-frames', bytes:gif({frames:0}),valid:false},
    {name: 'zero-delay', bytes:gif({delay:0}),valid:false},
    {name: 'busy-delay', bytes:gif({delay:1}),valid:false},
    {name: 'duplicate-loop', bytes:gif({extra:[loop,loop]}),valid:false},
    {name: 'plain-text-extension', bytes:gif({extra:[Buffer.from([0x21,1,12,...Buffer.alloc(12),0])]}),valid:false},
    {name: 'unknown-extension', bytes:gif({extra:[Buffer.from([0x21,0xee,0])]}),valid:false},
    {name: 'dangling-control', bytes:Buffer.concat([tiny.subarray(0,-1),gce(6),Buffer.from([0x3b])]),valid:false},
    {name: 'duplicate-control', bytes:gif({extra:[gce(6)]}),valid:false},
    {name: 'missing-control', bytes:Buffer.concat([tiny.subarray(0,19),image(),image(),Buffer.from([0x3b])]),valid:false},
    {name: 'empty-image-data', bytes:gif({frame:Buffer.from([0x2c,0,0,0,0,1,0,1,0,0,2,0])}),valid:false},
    {name: 'subblock-overrun', bytes:gif({frame:Buffer.from([0x2c,0,0,0,0,1,0,1,0,0,2,255,1])}),valid:false},
    {name: 'subblock-scan-limit', bytes:gif({extra:[comment(Buffer.concat([Buffer.from(Array.from({length:8193},()=>[1,0]).flat()),Buffer.from([0])]))]}),valid:false},
    {name: 'block-scan-limit', bytes:gif({extra:Array.from({length:1025},()=>comment(Buffer.from([0])))}),valid:false},
    {name: 'too-large', bytes:Buffer.concat([official,Buffer.alloc(1048577-official.length)]),valid:false},
    {name: 'trailing-data', bytes:Buffer.concat([tiny,Buffer.from([0])]),valid:false},
];
for (const [name, change, valid = false] of [
    ['bad-signature', b=>b[0]=0], ['bad-version',b=>b[3]=0],
    ['87a-with-extensions', b=>b.write('87a',3)], ['bad-background',b=>b[11]=2],
    ['truncated-global-palette',b=>b[10]=0x87], ['truncated-local-palette',b=>b[36]=0x87],
    ['bad-gce-size',b=>b[21]=3], ['bad-gce-terminator',b=>b[26]=1],
    ['reserved-gce-bits',b=>b[22]=0x80], ['undefined-disposal',b=>b[22]=0x10],
    ['input-wait',b=>b[22]=2], ['bad-transparent-index',b=>{b[22]=1;b[25]=2;}],
    ['valid-transparency',b=>{b[22]=1;b[25]=1;},true],
    ['valid-disposal',b=>b[22]=12,true], ['reserved-image-bits',b=>b[36]=8],
    ['interlaced-header',b=>b[36]=0x40,true], ['lzw-min-one',b=>b[37]=1], ['lzw-min-nine',b=>b[37]=9],
    ['invalid-marker',b=>b[27]=0],
]) {const bytes=Buffer.from(tiny); change(bytes); cases.push({name,bytes,valid});}
for (const [name, change] of [
    ['app-header-size',b=>b[21]=10],['app-identifier',b=>b[22]=0],
    ['app-subblock-size',b=>b[33]=4],['app-subblock-id',b=>b[34]=2],['app-terminator',b=>b[37]=1],
]) {const bytes=gif({extra:[loop]});change(bytes);cases.push({name,bytes,valid:false});}
for (const length of [0,5,6,12,13,18,19,20,21,22,25,26,27,28,35,36,37,38,39,40,41,tiny.length-1]) {
    cases.push({name:`truncated-${length}`,bytes:tiny.subarray(0,length),valid:false});
}
// Near-byte-limit admission with bounded comment sub-blocks, not decoded data.
const padding = 1048576 - tiny.length - 2;
const blocks=[];let remaining=padding;
while (remaining > 256) {blocks.push(Buffer.from([255]),Buffer.alloc(255));remaining-=256;}
if (remaining > 1) blocks.push(Buffer.from([remaining-2]),Buffer.alloc(remaining-2));
blocks.push(Buffer.from([0]));
const oneMib=gif({extra:[comment(Buffer.concat(blocks))]});
assert.equal(oneMib.length,1048576);
cases.push({name:'one-mib',bytes:oneMib,valid:true});

module.exports={uri,official,tiny,cases,gif};
