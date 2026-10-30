'use strict';

// Independent tiny ISO-BMFF metadata corpus; no downloaded media or private path.
const u32 = value => {const b = Buffer.alloc(4); b.writeUInt32BE(value); return b;};
const u16 = value => {const b = Buffer.alloc(2); b.writeUInt16BE(value); return b;};
const atom = (kind, ...parts) => {
    const body = Buffer.concat(parts);
    return Buffer.concat([u32(body.length + 8), Buffer.from(kind), body]);
};

function sps(width, height, profile, level) {
    let bits = '';
    const ue = value => {const word = (value + 1).toString(2); bits += '0'.repeat(word.length - 1) + word;};
    ue(0); ue(0); ue(0); ue(0); ue(1); bits += '0';
    ue(Math.ceil(width / 16) - 1); ue(Math.ceil(height / 16) - 1); bits += '11';
    const crop = (Math.ceil(height / 16) * 16 - height) / 2;
    bits += crop ? '1' : '0';
    if (crop) {ue(0); ue(0); ue(0); ue(crop);}
    bits += '01';
    while (bits.length % 8) bits += '0';
    const raw = Buffer.from(bits.match(/.{8}/g).map(byte => parseInt(byte, 2)));
    const escaped = [];
    let zeros = 0;
    for (const byte of raw) {
        if (zeros >= 2 && byte <= 3) {escaped.push(3); zeros = 0;}
        escaped.push(byte); zeros = byte === 0 ? zeros + 1 : 0;
    }
    return Buffer.from([0x67, profile, 0x40, level, ...escaped]);
}

function init(options = {}) {
    const config = {width: 1920, height: 1080, profile: 77, level: 42, videoId: 7, audioId: 8,
        videoScale: 90000, audioScale: 48000, channels: 2, rateIndex: 3, version: 0, ...options};
    const rate = [96000, 88200, 64000, 48000, 44100][config.rateIndex];
    const asc = u16((2 << 11) | (config.rateIndex << 7) | (config.channels << 3));
    const descriptor = (tag, ...parts) => {const body = Buffer.concat(parts); return Buffer.concat([Buffer.from([tag, body.length]), body]);};
    const decoder = descriptor(4, Buffer.from([0x40, 0x15]), Buffer.alloc(11), descriptor(5, asc));
    const esds = atom('esds', u32(0), descriptor(3, u16(config.audioId), Buffer.from([0]), decoder, descriptor(6, Buffer.from([2]))));
    const avc = sps(config.width, config.height, config.profile, config.level);
    const pps = Buffer.from('68ce3c80', 'hex');
    const avcC = atom('avcC', Buffer.from([1, config.profile, 0x40, config.level, 0xff, 0xe1]), u16(avc.length), avc, Buffer.from([1]), u16(pps.length), pps);
    const videoFields = Buffer.alloc(78);
    videoFields.writeUInt16BE(1, 6); videoFields.writeUInt16BE(config.width, 24); videoFields.writeUInt16BE(config.height, 26);
    videoFields.writeUInt16BE(1, 40); videoFields.writeUInt16BE(24, 74); videoFields.writeUInt16BE(0xffff, 76);
    const audioFields = Buffer.alloc(28);
    audioFields.writeUInt16BE(1, 6); audioFields.writeUInt16BE(config.channels, 16); audioFields.writeUInt16BE(16, 18);
    audioFields.writeUInt32BE(rate * 65536, 24);
    const track = (kind, id, scale, entry) => {
        const tkhd = Buffer.alloc(84); tkhd.writeUInt32BE(id, 12);
        const hdlr = Buffer.alloc(24); hdlr.write(kind === 'video' ? 'vide' : 'soun', 8);
        const mdhd = Buffer.alloc(config.version === 1 ? 36 : 24);
        mdhd[0] = config.version; mdhd[3] = config.mdhdFlags ?? 0;
        mdhd.writeUInt32BE(scale, config.version === 1 ? 20 : 12);
        mdhd.writeUInt16BE(config.reserved ?? 0, mdhd.length - 2);
        const timing = config.missingTiming === kind ? [] : [atom('mdhd', mdhd)];
        return atom('trak', atom('tkhd', tkhd), atom('mdia', ...timing, atom('hdlr', hdlr),
            atom('minf', atom('stbl', atom('stsd', u32(0), u32(1), entry)))));
    };
    return atom('moov', track('video', config.videoId, config.videoScale, atom('avc1', videoFields, avcC)),
        track('audio', config.audioId, config.audioScale, atom('mp4a', audioFields, esds))).toString('hex');
}

module.exports = {
    base: init(), changed: init({width: 1280, height: 720, videoId: 17, audioId: 18, videoScale: 45000, audioScale: 44100, version: 1}),
    profile: init({level: 31}), audio: init({channels: 1}), rate: init({rateIndex: 4}), larger: init({width: 1936}),
    zeroScale: init({videoScale: 0}), missingTiming: init({missingTiming: 'video'}), flags: init({mdhdFlags: 1}), reserved: init({reserved: 1}),
    maxScale: init({videoScale: 0xffffffff, audioScale: 0xffffffff, version: 1})
};
