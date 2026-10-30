'use strict';

// Synthetic BMFF only. The output golden is built directly from the declared
// samples, independently of the production demux or chunk planner.
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

const u32 = n => {const b = Buffer.alloc(4); b.writeUInt32BE(Number(BigInt(n) & 0xffffffffn)); return b;};
const i32 = n => {const b = Buffer.alloc(4); b.writeInt32BE(n); return b;};
const u64 = n => {const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b;};
const box = (kind, ...parts) => {const body = Buffer.concat(parts); return Buffer.concat([u32(body.length + 8), Buffer.from(kind), body]);};
const full = (kind, version, flags, ...parts) => box(kind, u32(version * 0x1000000 + flags), ...parts);
const identity = bytes => ({hex: bytes.toString('hex'), count: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex')});

function boxes(data, start = 0, end = data.length) {
    const out = [];
    while (start < end) {
        assert.ok(start <= end - 8);
        const size = data.readUInt32BE(start);
        assert.ok(size >= 8 && size <= end - start);
        out.push({kind: data.toString('ascii', start + 4, start + 8), start, body: start + 8, end: start + size});
        start += size;
    }
    assert.equal(start, end);
    return out;
}

function makeInit(seed) {
    const roots = boxes(seed);
    const moov = roots.find(b => b.kind === 'moov');
    const traks = boxes(seed, moov.body, moov.end).filter(b => b.kind === 'trak');
    const result = traks.map(trak => {
        const children = boxes(seed, trak.body, trak.end);
        const tkhd = children.find(b => b.kind === 'tkhd');
        const id = seed.readUInt32BE(tkhd.body + 12);
        const mdia = children.find(b => b.kind === 'mdia');
        const scale = id === 7 ? 1000000 : 48000;
        const mdhd = full('mdhd', 0, 0, u32(0), u32(0), u32(scale), u32(0), u32(0));
        return box('trak', ...children.map(child => child.kind === 'mdia'
            ? box('mdia', mdhd, seed.subarray(child.body, child.end))
            : seed.subarray(child.start, child.end)));
    });
    const trex = id => full('trex', 0, 0, u32(id), u32(1), u32(id === 7 ? 1000 : 96), u32(1), u32(0));
    return Buffer.concat(roots.map(root => root.kind === 'moov'
        ? box('moov', ...result, box('mvex', trex(7), trex(8)))
        : seed.subarray(root.start, root.end)));
}

function samples(index, kind) {
    const count = kind === 'video' ? 2 : 1;
    const duration = kind === 'video' ? 1000 : 96;
    const first = kind === 'video' ? 62033000n + BigInt(index * 2000) : 2976816n + BigInt(index * 96);
    return Array.from({length: count}, (_, n) => ({dts: first + BigInt(n * duration), duration,
        flags: kind === 'video' ? (n ? 0x1010000 : 0x2000000) : 0x2000000,
        composition: kind === 'video' ? (index % 2 ? -7 : 11) : 0,
        bytes: Buffer.from([kind === 'video' ? 0x76 : 0x61, index & 255, n, (index * 17 + n) & 255])}));
}

function traf(id, rows, dataOffset, decode = rows[0].dts) {
    return box('traf', full('tfhd', 0, 0x20000, u32(id)),
        full('tfdt', 1, 0, u64(decode)),
        full('trun', 1, 0xf01, u32(rows.length), i32(dataOffset),
            ...rows.flatMap(s => [u32(s.duration), u32(s.bytes.length), u32(s.flags), i32(s.composition)])));
}

function pair(index, video = samples(index, 'video'), audio = samples(index, 'audio')) {
    const mfhd = full('mfhd', 0, 0, u32(index + 100));
    const header = box('moof', mfhd, traf(7, video, 0), traf(8, audio, 0));
    const offset = header.length + 8;
    const vBytes = Buffer.concat(video.map(s => s.bytes));
    const aBytes = Buffer.concat(audio.map(s => s.bytes));
    return Buffer.concat([box('moof', mfhd, traf(7, video, offset), traf(8, audio, offset + vBytes.length)), box('mdat', vBytes, aBytes)]);
}

function goldenPair(index, kind) {
    const rows = samples(index, kind);
    const mfhd = full('mfhd', 0, 0, u32(index + 100));
    const header = box('moof', mfhd, traf(1, rows, 0));
    return Buffer.concat([box('moof', mfhd, traf(1, rows, header.length + 8)), box('mdat', ...rows.map(s => s.bytes))]);
}

function makeMedia(count = 95, trailing = false) {
    const input = [], video = [], audio = [];
    for (let index = 0; index < count; index++) {
        if (index % 20 === 0 && index < 95) {
            const event = full('emsg', 1, 0, u32(1000), u64(62033n + BigInt(index * 2)), u32(1), u32(index), Buffer.from('synthetic\0event\0payload'));
            input.push(event); video.push(event);
        }
        input.push(pair(index)); video.push(goldenPair(index, 'video')); audio.push(goldenPair(index, 'audio'));
    }
    if (trailing) {
        const event = full('emsg', 0, 0, Buffer.from('synthetic\0tail\0'), u32(1000), u32(0), u32(0), u32(55));
        input.push(event); video.push(event);
    }
    return {input: Buffer.concat(input), video: Buffer.concat(video), audio: Buffer.concat(audio)};
}

function inspect(data, kindById) {
    const result = {video: [], audio: [], events: []};
    let pending;
    for (const root of boxes(data)) {
        if (root.kind === 'emsg') {result.events.push(data.subarray(root.start, root.end).toString('hex')); continue;}
        if (root.kind === 'moof') {assert.equal(pending, undefined); pending = root; continue;}
        assert.equal(root.kind, 'mdat'); assert.ok(pending);
        const ranges = [];
        for (const part of boxes(data, pending.body, pending.end).filter(b => b.kind === 'traf')) {
            const children = boxes(data, part.body, part.end);
            const tfhd = children.find(b => b.kind === 'tfhd');
            const id = data.readUInt32BE(tfhd.body + 4);
            const kind = kindById[id]; assert.ok(kind);
            const tfdt = children.find(b => b.kind === 'tfdt');
            let dts = data.readBigUInt64BE(tfdt.body + 4);
            for (const trun of children.filter(b => b.kind === 'trun')) {
                assert.equal(data.readUInt32BE(trun.body), 0x1000f01);
                const count = data.readUInt32BE(trun.body + 4);
                let p = trun.body + 12;
                let payload = pending.start + data.readInt32BE(trun.body + 8);
                const start = payload;
                for (let n = 0; n < count; n++) {
                    const duration = data.readUInt32BE(p), size = data.readUInt32BE(p + 4), flags = data.readUInt32BE(p + 8), composition = data.readInt32BE(p + 12);
                    assert.ok(payload >= root.body && payload + size <= root.end);
                    result[kind].push({dts: String(dts), pts: String(dts + BigInt(composition)), duration, flags, hex: data.subarray(payload, payload + size).toString('hex')});
                    dts += BigInt(duration); payload += size; p += 16;
                }
                assert.equal(p, trun.end);
                ranges.push([start, payload]);
            }
        }
        ranges.sort((a, b) => a[0] - b[0]);
        for (let n = 1; n < ranges.length; n++) assert.ok(ranges[n - 1][1] <= ranges[n][0]);
        pending = undefined;
    }
    assert.equal(pending, undefined);
    return result;
}

function corpus(seed) {
    const init = makeInit(seed), media = makeMedia(), tail = makeMedia(2, true), cancel = makeMedia(21), negatives = [], initNegative = [];
    const badInit = (name, change) => {const data = Buffer.from(init); change(data); initNegative.push({name, input: identity(data)});};
    initNegative.push({name: 'truncated-init', input: identity(init.subarray(0, -1))});
    initNegative.push({name: 'encrypted-init', input: identity(Buffer.concat([init, box('pssh', u32(0))]))});
    const mdhd = init.indexOf(Buffer.from('mdhd')), trex = init.indexOf(Buffer.from('trex'));
    badInit('zero-timescale', data => data.writeUInt32BE(0, mdhd + 16));
    badInit('nonintegral-description', data => data.writeUInt32BE(2, trex + 12));
    badInit('missing-trex', data => Buffer.from('free').copy(data, trex));
    badInit('unknown-mdhd-version', data => {data[mdhd + 4] = 2;});
    badInit('foreign-trex', data => data.writeUInt32BE(9, trex + 8));
    const mutate = (name, change) => {const data = Buffer.from(media.input); change(data); negatives.push({name, input: identity(data)});};
    negatives.push({name: 'truncated-tail', input: identity(media.input.subarray(0, -1))});
    negatives.push({name: 'unsupported-trailing-root', input: identity(Buffer.concat([media.input, box('sidx', Buffer.alloc(16))]))});
    negatives.push({name: 'unpaired-tail', input: identity(Buffer.concat([media.input, box('moof', full('mfhd', 0, 0, u32(1)))]))});
    negatives.push({name: 'too-many-pairs', input: identity(makeMedia(129).input)});
    const first = media.input.indexOf(Buffer.from('tfhd'));
    mutate('absolute-base-offset', data => {data[first + 7] |= 1;});
    mutate('unknown-track', data => data.writeUInt32BE(9, first + 8));
    const run = media.input.indexOf(Buffer.from('trun'));
    mutate('negative-sample-offset', data => data.writeInt32BE(-1, run + 12));
    const audioRun = media.input.indexOf(Buffer.from('trun'), run + 4);
    mutate('cross-track-overlap', data => data.writeInt32BE(data.readInt32BE(run + 12), audioRun + 12));
    const nextTfdt = media.input.indexOf(Buffer.from('tfdt'), media.input.indexOf(Buffer.from('tfdt'), 0) + 4);
    const thirdTfdt = media.input.indexOf(Buffer.from('tfdt'), nextTfdt + 4);
    mutate('noncontinuous-decode', data => data.writeBigUInt64BE(62033001n + 2000n, thirdTfdt + 8));
    mutate('reserved-tfdt-flags', data => {data[media.input.indexOf(Buffer.from('tfdt')) + 7] = 1;});
    mutate('duration-empty', data => {data[first + 5] |= 1;});
    mutate('zero-duration', data => data.writeUInt32BE(0, run + 16));
    mutate('encryption', data => Buffer.from('senc').copy(data, run));
    const event = full('emsg', 1, 0, u32(1000), u64(62033n), u32(1), u32(1), Buffer.from('synthetic\0event\0'));
    negatives.push({name: 'metadata-count', input: identity(Buffer.concat([...Array.from({length: 17}, () => event), pair(0)]))});
    for (const [name, bytes] of [['metadata-empty', box('emsg', u32(0))],
        ['metadata-flags', full('emsg', 1, 1, event.subarray(12))],
        ['metadata-zero-timescale', full('emsg', 1, 0, u32(0), event.subarray(16))],
        ['metadata-no-terminator', full('emsg', 1, 0, u32(1000), u64(1n), u32(0), u32(0), Buffer.from('none'))]]) {
        negatives.push({name, input: identity(Buffer.concat([bytes, pair(0)]))});
    }
    const manyRows = Array.from({length: 8193}, (_, n) => ({dts: 62033000n + BigInt(n), duration: 1, flags: 0, composition: 0, bytes: Buffer.from([n & 255])}));
    negatives.push({name: 'one-pair-sample-work', input: identity(pair(0, manyRows, samples(0, 'audio')))});
    const huge = samples(0, 'video'); huge[0].bytes = Buffer.alloc(4194304, 1);
    negatives.push({name: 'one-pair-byte-work', input: identity(pair(0, huge, samples(0, 'audio')))});
    const original = inspect(media.input, {7: 'video', 8: 'audio'});
    for (const kind of ['video', 'audio']) {
        const golden = inspect(media[kind], {[1]: kind});
        assert.deepEqual(golden[kind], original[kind]);
        assert.deepEqual(golden.events, kind === 'video' ? original.events : []);
    }
    return {version: 1, init: identity(init), media: {input: identity(media.input), video: identity(media.video), audio: identity(media.audio)},
        tail: {input: identity(tail.input), video: identity(tail.video), audio: identity(tail.audio)}, cancel: {input: identity(cancel.input)}, negatives, initNegative,
        original, policy: {pairs: 95, emsg: 5, videoSamples: 190, audioSamples: 95}};
}

module.exports = {corpus, identity, inspect, boxes, makeMedia, box};
