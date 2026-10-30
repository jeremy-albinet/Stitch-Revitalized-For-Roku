'use strict';

const origin = 'https://vod-cdn.example.test';
const source = `${origin}/archive/index.m3u8?master=fixture%2Bquery`;
const header = (target = 10, sequence = 17, kind = 'EVENT') =>
    '#EXTM3U\n#EXT-X-VERSION:7\n' +
    `#EXT-X-TARGETDURATION:${target}\n#EXT-X-PLAYLIST-TYPE:${kind}\n` +
    `#EXT-X-MEDIA-SEQUENCE:${sequence}\n#EXT-X-MAP:URI="init.mp4?sig=fixture%2Bbytes"\n`;
const playlist = (count, duration = '10.000000', target = 10) => header(target) +
    Array.from({ length: count }, (_, index) => `#EXTINF:${duration},\n${index}.m4s\n`).join('') + '#EXT-X-ENDLIST\n';
const small = header(30, 123, 'VOD') +
    '#EXTINF:1.000001,\nfirst.m4s?sig=fixture%2Fab%25\n' +
    '#EXTINF:0.25,\nsecond.m4s\n#EXTINF:30,\nlast.m4s\n#EXT-X-ENDLIST\n';
const single = header() + '#EXTINF:10,\n0.m4s\n#EXT-X-ENDLIST\n';
const withComments = text => text
    .replace('#EXTM3U\n', '#EXTM3U\n#ID3-EQUIV-TDTG:2026-10-09T12:00:00.000Z\n#fixture repeated\n#fixture repeated\n')
    .replace('#EXTINF:1.000001,\n', '#EXTINF:1.000001,\n#\n#ext-X-KEY:METHOD=AES-128,URI="not-a-tag"\n')
    .replace('#EXT-X-ENDLIST\n', '#foreign text https://foreign.example.test/not-a-request\n#EXT-X-ENDLIST\n');
const comments = [
    { name: 'observed comment LF', text: withComments(small) },
    { name: 'observed comment CRLF', text: withComments(small).replaceAll('\n', '\r\n') },
    { name: 'comment before each segment', text: small.replaceAll(',\n', ',\n#pending duration retained\n') }
];
const replace = (name, before, after) => ({ name, text: single.replace(before, after) });
const bad = [
    { name: 'empty body', text: '' },
    { name: 'over body ceiling', text: 'x'.repeat(262145) },
    { name: 'not ASCII', text: single + '\u0080' },
    { name: 'bad first line', text: single.replace('#EXTM3U', '#NOPE') },
    { name: 'comment before first header', text: '#fixture\n' + single },
    { name: 'comment after ENDLIST', text: single + '#ID3-EQUIV-TDTG:ignored\n' },
    { name: 'duplicate header is still an unknown EXT tag', text: single.replace('#EXTINF:10,', '#EXTM3U\n#EXTINF:10,') },
    replace('bare EXT tag', '#EXTINF:10,', '#EXT\n#EXTINF:10,'),
    replace('EXT tag during pending duration', '0.m4s', '#EXT-X-VERSION:7\n0.m4s'),
    replace('comment with leading whitespace', '#EXTINF:10,', ' #comment\n#EXTINF:10,'),
    replace('comment with trailing whitespace', '#EXTINF:10,', '#comment \n#EXTINF:10,'),
    replace('comment with embedded CR', '#EXTINF:10,', '#comment\rbroken\n#EXTINF:10,'),
    replace('comment with forbidden control', '#EXTINF:10,', '#comment\u0001\n#EXTINF:10,'),
    replace('comment not ASCII', '#EXTINF:10,', '#comment\u0080\n#EXTINF:10,'),
    replace('overlong ignored comment', '#EXTINF:10,', '#' + 'x'.repeat(4096) + '\n#EXTINF:10,'),
    replace('missing ENDLIST', '#EXT-X-ENDLIST\n', ''),
    replace('missing type', '#EXT-X-PLAYLIST-TYPE:EVENT\n', ''),
    replace('unsupported type', 'PLAYLIST-TYPE:EVENT', 'PLAYLIST-TYPE:LIVE'),
    replace('missing init', '#EXT-X-MAP:URI="init.mp4?sig=fixture%2Bbytes"\n', ''),
    replace('duplicate map', '#EXTINF:10,', '#EXT-X-MAP:URI="other.mp4"\n#EXTINF:10,'),
    replace('foreign map', 'init.mp4?sig=fixture%2Bbytes', 'https://foreign.example.test/init.mp4'),
    replace('map range', 'URI="init.mp4?sig=fixture%2Bbytes"', 'URI="init.mp4",BYTERANGE="8@0"'),
    replace('encrypted tag', '#EXTINF:10,', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:10,'),
    replace('unexpected clear key', '#EXTINF:10,', '#EXT-X-KEY:METHOD=NONE\n#EXTINF:10,'),
    replace('media range', '0.m4s', '#EXT-X-BYTERANGE:8@0\n0.m4s'),
    replace('discontinuity', '#EXTINF:10,', '#EXT-X-DISCONTINUITY\n#EXTINF:10,'),
    replace('unknown required tag', '#EXTINF:10,', '#EXT-X-UNKNOWN:1\n#EXTINF:10,'),
    replace('pending duration twice', '#EXTINF:10,', '#EXTINF:10,\n#EXTINF:10,'),
    replace('no duration', '#EXTINF:10,\n', ''),
    replace('zero duration', 'EXTINF:10,', 'EXTINF:0,'),
    replace('duration >30 seconds', 'EXTINF:10,', 'EXTINF:31,'),
    replace('duration > target', 'EXTINF:10,', 'EXTINF:10.000001,'),
    replace('float exponent duration', 'EXTINF:10,', 'EXTINF:1e1,'),
    replace('overprecision duration', 'EXTINF:10,', 'EXTINF:10.0000001,'),
    replace('signed duration', 'EXTINF:10,', 'EXTINF:-10,'),
    replace('over target ceiling', 'TARGETDURATION:10', 'TARGETDURATION:31'),
    replace('fractional target', 'TARGETDURATION:10', 'TARGETDURATION:10.1'),
    replace('sequence overflow', 'MEDIA-SEQUENCE:17', 'MEDIA-SEQUENCE:4294967296'),
    replace('negative sequence', 'MEDIA-SEQUENCE:17', 'MEDIA-SEQUENCE:-1'),
    replace('unknown version', 'VERSION:7', 'VERSION:8'),
    replace('duplicate target', '#EXTINF:10,', '#EXT-X-TARGETDURATION:10\n#EXTINF:10,'),
    replace('foreign media', '0.m4s', 'https://foreign.example.test/0.m4s'),
    replace('userinfo media', '0.m4s', 'https://user@vod-cdn.example.test/0.m4s'),
    replace('port media', '0.m4s', 'https://vod-cdn.example.test:443/0.m4s'),
    replace('IP media', '0.m4s', 'https://127.0.0.1/0.m4s'),
    replace('protocol relative media', '0.m4s', '//vod-cdn.example.test/0.m4s'),
    replace('dot traversal', '0.m4s', '../0.m4s'),
    replace('encoded path traversal', '0.m4s', '%2e%2e/0.m4s'),
    replace('escaped slash path', '0.m4s', 'a%2f0.m4s'),
    replace('backslash media', '0.m4s', 'a\\0.m4s'),
    replace('fragment media', '0.m4s', '0.m4s#fragment'),
    replace('whitespace media', '0.m4s', 'a 0.m4s'),
    replace('query only media', '0.m4s', '?q=fixture'),
    replace('overlong reference', '0.m4s', 'a'.repeat(2049)),
    replace('overlong line', '0.m4s', 'a'.repeat(4097)),
    replace('body after end', '#EXT-X-ENDLIST\n', '#EXT-X-ENDLIST\n#EXTINF:1,\nlate.m4s\n'),
    replace('truncated final tag', '#EXT-X-ENDLIST', '#EXT-X-ENDLIS'),
    { name: 'pending last duration', text: single.replace('#EXT-X-ENDLIST', '#EXTINF:1,\n#EXT-X-ENDLIST') }
];

function packed(count, durationUs) {
    const text = playlist(count, String(Number(durationUs) / 1e6), Number(durationUs) / 1e6);
    const result = Buffer.alloc(count * 24);
    let cursor = 0;
    for (let index = 0; index < count; index++) {
        const ref = `${index}.m4s`;
        const at = text.indexOf(`\n${ref}\n`, cursor) + 1;
        if (at <= 0) throw new Error('reference offset missing');
        result.writeUInt32BE(at, index * 24);
        result.writeUInt32BE(ref.length, index * 24 + 4);
        result.writeBigUInt64BE(durationUs, index * 24 + 8);
        result.writeBigUInt64BE(BigInt(index) * durationUs, index * 24 + 16);
        cursor = at + ref.length;
    }
    return { text, records: result };
}

module.exports = { origin, source, header, playlist, small, single, comments, withComments, bad, packed };
