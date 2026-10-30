'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { fixture, positive, normal } = require('./fixtures/roku-vod-descriptor/support');
const { header, playlist, withComments } = require('./fixtures/roku-vod-index/corpus');
const sessionId = '0123456789abcdef0123456789abcdef';
const otherSession = '1123456789abcdef0123456789abcdef';
const metadata = { videoCodec: 'avc1.4D402A', audioCodec: 'mp4a.40.2', width: 1920, height: 1080, frameRate: '60.000', bandwidth: 6000000, isHD: true };
const duration = micros => {
    const whole = micros / 1000000n, remainder = micros % 1000000n;
    return String(whole) + (remainder ? `.${String(remainder).padStart(6, '0').replace(/0+$/, '')}` : '');
};
function golden(track, durations, sequence) {
    const short = track === 'video' ? 'v' : 'a';
    const target = Number((durations.reduce((a, b) => a > b ? a : b) + 999999n) / 1000000n);
    return `#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:${target}\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MEDIA-SEQUENCE:${sequence}\n#EXT-X-MAP:URI="/vod/${sessionId}/init/${short}.mp4"\n` +
        durations.map((item, index) => `#EXTINF:${duration(item)},\n/vod/${sessionId}/${short}/${index}.m4s\n`).join('') + '#EXT-X-ENDLIST\n';
}
const small = header(30, 123, 'VOD') + '#EXTINF:1.000001,\n0.m4s?sig=fixture%2B%25\n#EXTINF:0.25,\n1.m4s\n#EXTINF:30,\n2.m4s\n#EXT-X-ENDLIST\n';
const smallGoldens = Object.fromEntries(['video', 'audio'].map(track => [track, golden(track, [1000001n, 250000n, 30000000n], 123)]));
const defaultPlaylist = (header(30, 0, 'EVENT').replace('#EXT-X-MEDIA-SEQUENCE:0\n', '') + '#EXTINF:10,\n0.m4s\n#EXT-X-ENDLIST\n').replaceAll('\n', '\r\n');
const largeGoldens = Object.fromEntries(['video', 'audio'].map(track => [track, golden(track, Array(7376).fill(10000000n), 17)]));
const masterGolden = `#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,URI="/vod/${sessionId}/audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60.000,CODECS="avc1.4D402A,mp4a.40.2",AUDIO="audio"\n/vod/${sessionId}/video.m3u8\n`;
const route = `/vod/${sessionId}/v/0.m4s`;
const basic = `GET ${route} HTTP/1.1\r\nHost: 127.0.0.1:55000\r\n\r\n`;
const responseGolden = (mime, partial) => `HTTP/1.1 ${partial ? '206 Partial Content' : '200 OK'}\r\nContent-Type: ${mime}\r\nContent-Length: ${partial ? 10 : 100}\r\nAccept-Ranges: bytes\r\nConnection: close\r\nCache-Control: no-store\r\n${partial ? 'Content-Range: bytes 0-9/100\r\n' : ''}\r\n`;
const rangeGolden = responseGolden('video/mp4', true);
const fullGoldens = { 'video.m3u8': responseGolden('application/vnd.apple.mpegurl', false), 'init/a.mp4': responseGolden('audio/mp4', false) };
const badHeaders = [basic.replace('GET ', 'POST '), basic.replace('HTTP/1.1', 'HTTP/1.0'), basic.replace('127.0.0.1', 'localhost'),
    basic.replace(':55000', ':55001'), basic.replace('Host: 127.0.0.1:55000\r\n', ''), basic.replaceAll('\r\n', '\n'), basic + 'x',
    basic.replace('\r\n\r\n', '\r\nContent-Length: 0\r\n\r\n'), basic.replace('\r\n\r\n', '\r\nTransfer-Encoding: chunked\r\n\r\n'),
    basic.replace('\r\n\r\n', '\r\nExpect: 100-continue\r\n\r\n'), basic.replace('\r\n\r\n', '\r\nhost: 127.0.0.1:55000\r\n\r\n'),
    basic.replace('\r\n\r\n', '\r\nRange: bytes=0-9\r\nrange: bytes=10-20\r\n\r\n'), basic.replace('\r\n\r\n', '\r\n folded\r\n\r\n'),
    basic.replace('\r\n\r\n', '\r\nBad Name: x\r\n\r\n'), basic.replace('\r\n\r\n', '\r\nX: \u0080\r\n\r\n'),
    basic.replace('\r\n\r\n', '\r\nRange: bytes=0-1,3-4\r\n\r\n'), basic.replace('\r\n\r\n', '\r\nX: ' + 'x'.repeat(8192) + '\r\n\r\n')];
const badPaths = ['v/7376.m4s', 'v/8192.m4s', 'v/01.m4s', 'v/-1.m4s', 'v/1.0.m4s', 'v/%31.m4s', 'v/../0.m4s', 'v/0.m4s?source=https://foreign', 'init/x.mp4', 'video.m3u8#x', 'a/0.m4s/extra', '/v/0.m4s'].map(tail => `/vod/${sessionId}/${tail}`);
const ranges = [
    { header: '', size: 100, ok: true, start: 0, length: 100, status: 200 },
    { header: 'bytes=0-9', size: 100, ok: true, start: 0, length: 10, status: 206 },
    { header: 'bytes=90-', size: 100, ok: true, start: 90, length: 10, status: 206 },
    { header: 'bytes=-10', size: 100, ok: true, start: 90, length: 10, status: 206 },
    { header: 'bytes=0-999', size: 100, ok: true, start: 0, length: 100, status: 206 },
    ...['bytes=100-', 'bytes=9-1', 'bytes=-0', 'bytes=0-1,3-4', 'bytes=1e1-20', 'bytes=0-9\r\nX:x', 'Bytes=0-9', 'bytes=4194305-'].map(header => ({ header, size: 100, ok: false })),
    { header: '', size: 4194305, ok: true, start: 0, length: 4194305, status: 200 },
    { header: '', size: 16777216, ok: true, start: 0, length: 16777216, status: 200 },
    { header: 'bytes=4194304-4194313', size: 16777216, ok: true, start: 4194304, length: 10, status: 206 },
    { header: 'bytes=4194304-', size: 16777216, ok: true, start: 4194304, length: 12582912, status: 206 },
    { header: 'bytes=-4194305', size: 16777216, ok: true, start: 12582911, length: 4194305, status: 206 },
    { header: 'bytes=0-16777216', size: 4194305, ok: true, start: 0, length: 4194305, status: 206 },
    ...['bytes=16777216-', 'bytes=-16777217', 'bytes=0-16777217', 'bytes=4294967296-', 'bytes=9999999999-'].map(header => ({ header, size: 16777216, ok: false })),
    { header: '', size: 16777217, ok: false }, { header: '', size: 1.5, ok: false }, { header: '', size: 0, ok: false }
];
function inputs() {
    return { 'large.bin': playlist(7376), 'data.json': JSON.stringify({ sessionId, otherSession, metadata, small, commentedSmall: withComments(small), smallGoldens, masterGolden, defaultPlaylist, defaultGolden: golden('video', [10000000n], 0), rangeGolden, fullGoldens,
        largeDigests: Object.fromEntries(Object.entries(largeGoldens).map(([key, value]) => [key, createHash('sha256').update(value).digest('hex')])),
        largeLengths: Object.fromEntries(Object.entries(largeGoldens).map(([key, value]) => [key, value.length])), badPaths, badHeaders, ranges }) };
}
test('actual finite VOD manifests stream every7376 entry with bounded cursors and exact local framing', { timeout: 150000 }, async t => {
    for (const track of ['video', 'audio']) {
        const { result, marker } = await fixture('roku-vod-protocol', track, inputs());
        t.diagnostic(`${track}: ${positive(result, marker)} actual finite manifest/route/framing assertions; no socket/native playback claim`);
    }
});
test('actual ENDLIST,duration,session and send-scratch mutants fail normally', { timeout: 270000 }, async t => {
    for (const [before, after, label] of [
        ['line = "#EXT-X-ENDLIST" + Chr(10)', 'line = ""', 'complete finite span returns'],
        ['whole = value \\ 1000000&', 'whole = 0&', 'finite manifest matches all full timeline bytes'],
        ['if path.Left(prefix.Len()) <> prefix then return invalid', "' Deliberately bypass session route binding", 'route refuses wrong session'],
        ['if not nviInteger(maxBytes) or maxBytes < 1 or maxBytes > 16384 then return invalid', 'if not nviInteger(maxBytes) or maxBytes < 1 then return invalid', 'scratch cap refuses oversize'],
        ['"Content-Length: " + slice.length.ToStr()', '"Content-Length: " + size.ToStr()', 'truthful range response header exact golden']
    ]) {
        const { result, marker } = await fixture('roku-vod-protocol', 'small', inputs(), { name: 'rokuVodProtocol', before, after });
        normal(result);
        assert.ok(result.output.includes(`VOD_P2_FAIL: ${label}`), result.output.slice(-14000));
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${label}: normal-exit actual mutation rejected`);
    }
});
