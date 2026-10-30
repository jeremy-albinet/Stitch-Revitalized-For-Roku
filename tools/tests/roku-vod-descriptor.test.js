'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixture, positive, normal, run } = require('./fixtures/roku-vod-descriptor/support');
const os = require('node:os');
const { randomUUID } = require('node:crypto');

const origin = 'https://dfixture123.cloudfront.net';
const source = `${origin}/archive/index.m3u8?sig=fixture%2B%25`;
const usher = 'https://usher.ttvnw.net/vod/v2/123456.m3u8?token=fixture%2B%25';
const attrs = 'BANDWIDTH=6000000,CODECS="avc1.4D402A,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=60.000,VIDEO="chunked"';
const master = `#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-STREAM-INF:${attrs}\n${source}\n`;
const base = { origin, source, usher, master };
const commentedMaster = master
    .replace('#EXTM3U\n', '#EXTM3U\n#ID3-EQUIV-TDTG:2026-10-09T12:00:00.000Z\n#repeat\n#repeat\n')
    .replace(source, `#\n#ext-X-SESSION-KEY:METHOD=AES-128\n#foreign text https://foreign.example.test/not-authority\n${source}`);
const comments = [commentedMaster, commentedMaster.replaceAll('\n', '\r\n'), master + '#c\n'.repeat(2043)];
const sessionLine = attributes => `#EXT-X-SESSION-DATA:${attributes}\n`;
const sessionMaster = attributes => master.replace('#EXT-X-STREAM-INF:', `${sessionLine(attributes)}#EXT-X-STREAM-INF:`);
const mediaLine = attributes => `#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60",${attributes}\n`;
const mediaMaster = attributes => master.replace('#EXT-X-STREAM-INF:', `${mediaLine(attributes)}#EXT-X-STREAM-INF:`);
const acceptedMetadata = [
    sessionMaster('DATA-ID="com.example.label",VALUE="safe metadata"'),
    sessionMaster('DATA-ID="com.example.label",VALUE=""'),
    sessionMaster('DATA-ID="com.example.label",VALUE="comma,equals=retained",LANGUAGE="en"'),
    sessionMaster('DATA-ID="com.example.label",URI="https://foreign.example.test/inert.json"'),
    sessionMaster('DATA-ID="com.example.label",URI="relative.json?sig=fixture%2B%25"').replaceAll('\n', '\r\n'),
    sessionMaster(`DATA-ID="${'d'.repeat(256)}",VALUE="${'v'.repeat(4096)}",LANGUAGE="${'l'.repeat(64)}"`),
    sessionMaster(`DATA-ID="com.example.uri",URI="${'u'.repeat(4096)}"`),
    master.replace('#EXT-X-STREAM-INF:', sessionLine('DATA-ID="com.example.label",VALUE="en",LANGUAGE="en"') + sessionLine('DATA-ID="com.example.label",VALUE="es",LANGUAGE="es"') + '#EXT-X-STREAM-INF:'),
    master.replace('#EXT-X-STREAM-INF:', Array.from({ length: 64 }, (_, i) => sessionLine(`DATA-ID="com.example.${i}",VALUE=""`)).join('') + '#EXT-X-STREAM-INF:'),
    mediaMaster('IVS-NAME="captured-shape-label"'),
    mediaMaster(`IVS-NAME="${'i'.repeat(128)}"`).replaceAll('\n', '\r\n'),
    master.replace('#EXT-X-STREAM-INF:', '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="A",IVS-NAME="muxed-audio-label"\n#EXT-X-STREAM-INF:AUDIO="audio",'),
    mediaMaster('IVS-NAME="https://foreign.example.test/not-an-origin"'),
    master.replace('BANDWIDTH=', 'IVS-NAME="captured-stream-label-shape",BANDWIDTH='),
    master.replace('BANDWIDTH=', `IVS-NAME="${'s'.repeat(128)}",BANDWIDTH=`).replaceAll('\n', '\r\n'),
    sessionMaster('DATA-ID="com.example.label",VALUE="safe metadata"').replace('BANDWIDTH=', 'IVS-NAME="1080p60 display only",BANDWIDTH=')
];
const rejectedMetadata = [];
const acceptedVariantSources = ['source', 'transcode'].flatMap(value => [
    master.replace('BANDWIDTH=', `IVS-VARIANT-SOURCE="${value}",BANDWIDTH=`),
    sessionMaster('DATA-ID="com.example.label",VALUE="inert"').replace('BANDWIDTH=', `IVS-NAME="label",IVS-VARIANT-SOURCE="${value}",BANDWIDTH=`).replaceAll('\n', '\r\n')
]);
const rejectedVariantSources = [];
const rejectVariant = (name, changes) => rejectedVariantSources.push({ name, master, usher, source, id: '123456', quality: '1080p60 (Source)', ...changes });
for (const [name, value] of [
    ['unquoted source', 'source'], ['unquoted transcode', 'transcode'], ['empty enum', '""'],
    ['uppercase enum', '"SOURCE"'], ['mixed-case enum', '"Transcode"'], ['unknown enum', '"other"'],
    ['leading enum whitespace', '" source"'], ['trailing enum whitespace', '"transcode "'],
    ['URL enum', '"https://foreign.example.test/not-authority"'], ['unclosed enum quote', '"source']
]) rejectVariant(name, { master: master.replace('BANDWIDTH=', `IVS-VARIANT-SOURCE=${value},BANDWIDTH=`) });
rejectVariant('duplicate source attribute', { master: master.replace('BANDWIDTH=', 'IVS-VARIANT-SOURCE="source",IVS-VARIANT-SOURCE="transcode",BANDWIDTH=') });
rejectVariant('source enum on MEDIA', { master: mediaMaster('IVS-VARIANT-SOURCE="source"') });
rejectVariant('source enum does not admit unknown STREAM attr', { master: master.replace('BANDWIDTH=', 'IVS-VARIANT-SOURCE="source",UNKNOWN="ignored",BANDWIDTH=') });
rejectVariant('source enum does not corroborate absent rendition', { master: acceptedVariantSources[0].replace(source + '\n', origin + '/other.m3u8\n') });
rejectVariant('source enum does not authorize foreign origin', { source: 'https://foreign.example.test/a.m3u8', master: acceptedVariantSources[0].replace(source + '\n', 'https://foreign.example.test/a.m3u8\n') });
rejectVariant('source enum does not authorize unsupported codec', { master: acceptedVariantSources[0].replace('avc1.4D402A', 'hvc1.1.6.L120') });
rejectVariant('source enum does not authorize unsupported audio', { master: acceptedVariantSources[0].replace('mp4a.40.2', 'opus') });
const rejectMetadata = (name, changes) => rejectedMetadata.push({ name, master, usher, source, id: '123456', quality: '1080p60 (Source)', ...changes });
for (const [name, attributes] of [
    ['missing DATA-ID', 'VALUE="value"'], ['empty DATA-ID', 'DATA-ID="",VALUE="value"'],
    ['unquoted DATA-ID', 'DATA-ID=identifier,VALUE="value"'], ['long DATA-ID', `DATA-ID="${'d'.repeat(257)}",VALUE="value"`],
    ['missing VALUE and URI', 'DATA-ID="id"'], ['both VALUE and URI', 'DATA-ID="id",VALUE="value",URI="uri"'],
    ['unquoted VALUE', 'DATA-ID="id",VALUE=plain'], ['long VALUE', `DATA-ID="id",VALUE="${'v'.repeat(4097)}"`],
    ['empty URI', 'DATA-ID="id",URI=""'], ['unquoted URI', 'DATA-ID="id",URI=relative.json'],
    ['long URI', `DATA-ID="id",URI="${'u'.repeat(4097)}"`], ['empty LANGUAGE', 'DATA-ID="id",VALUE="value",LANGUAGE=""'],
    ['unquoted LANGUAGE', 'DATA-ID="id",VALUE="value",LANGUAGE=en'], ['long LANGUAGE', `DATA-ID="id",VALUE="value",LANGUAGE="${'l'.repeat(65)}"`],
    ['unknown session attribute', 'DATA-ID="id",VALUE="value",FOREIGN="ignored"'],
    ['duplicate session attribute', 'DATA-ID="id",VALUE="one",VALUE="two"'],
    ['malformed session quote', 'DATA-ID="id",VALUE="unterminated'], ['embedded quote', 'DATA-ID="id",VALUE="one""two"'],
    ['trailing session comma', 'DATA-ID="id",VALUE="value",'], ['session control byte', 'DATA-ID="id",VALUE="bad\u0001"']
]) rejectMetadata(name, { master: sessionMaster(attributes) });
const repeated = sessionLine('DATA-ID="duplicate",VALUE="first"') + sessionLine('DATA-ID="duplicate",URI="second.json"');
rejectMetadata('duplicate DATA-ID LANGUAGE pair', { master: master.replace('#EXT-X-STREAM-INF:', repeated + '#EXT-X-STREAM-INF:') });
rejectMetadata('duplicate localized pair', { master: master.replace('#EXT-X-STREAM-INF:', sessionLine('DATA-ID="duplicate",VALUE="first",LANGUAGE="en"').repeat(2) + '#EXT-X-STREAM-INF:') });
rejectMetadata('65 session records', { master: master.replace('#EXT-X-STREAM-INF:', Array.from({ length: 65 }, (_, i) => sessionLine(`DATA-ID="com.example.${i}",VALUE=""`)).join('') + '#EXT-X-STREAM-INF:') });
rejectMetadata('session while rendition URI pending', { master: master.replace(source, sessionLine('DATA-ID="id",VALUE="value"') + source) });
rejectMetadata('session URI is not rendition corroboration', { master: sessionMaster(`DATA-ID="sourceUrl",URI="${source}"`).replace(source + '\n', origin + '/other.m3u8\n') });
rejectMetadata('session URI cannot authorize selected foreign origin', { source: 'https://foreign.example.test/a.m3u8', master: sessionMaster(`DATA-ID="sourceUrl",URI="https://foreign.example.test/a.m3u8"`).replace(source + '\n', 'https://foreign.example.test/a.m3u8\n') });
rejectMetadata('session VALUE cannot authorize unsupported codec', { master: sessionMaster('DATA-ID="CODECS",VALUE="avc1.4D402A,mp4a.40.2"').replace(`CODECS="avc1.4D402A,mp4a.40.2"`, 'CODECS="hvc1.1.6.L120,mp4a.40.2"') });
rejectMetadata('empty IVS-NAME', { master: mediaMaster('IVS-NAME=""') });
rejectMetadata('long IVS-NAME', { master: mediaMaster(`IVS-NAME="${'i'.repeat(129)}"`) });
rejectMetadata('unknown MEDIA attribute still refuses', { master: mediaMaster('IVS-NAME="valid",UNKNOWN="ignored"') });
rejectMetadata('duplicate IVS-NAME', { master: mediaMaster('IVS-NAME="first",IVS-NAME="second"') });
rejectMetadata('empty STREAM IVS-NAME', { master: master.replace('BANDWIDTH=', 'IVS-NAME="",BANDWIDTH=') });
rejectMetadata('long STREAM IVS-NAME', { master: master.replace('BANDWIDTH=', `IVS-NAME="${'s'.repeat(129)}",BANDWIDTH=`) });
rejectMetadata('duplicate STREAM IVS-NAME', { master: master.replace('BANDWIDTH=', 'IVS-NAME="first",IVS-NAME="second",BANDWIDTH=') });
rejectMetadata('unknown STREAM attribute with valid IVS-NAME', { master: master.replace('BANDWIDTH=', 'IVS-NAME="label",UNKNOWN="ignored",BANDWIDTH=') });
rejectMetadata('IVS-NAME cannot authorize separate audio URI', { master: master.replace('#EXT-X-STREAM-INF:', '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="A",IVS-NAME="label",URI="https://foreign.example.test/a.m3u8"\n#EXT-X-STREAM-INF:AUDIO="audio",') });
rejectMetadata('SESSION-DATA does not admit SESSION-KEY', { master: sessionMaster('DATA-ID="id",VALUE="valid"') + '#EXT-X-SESSION-KEY:METHOD=AES-128\n' });
const bad = [];
const add = (name, changes) => bad.push({ name, master, usher, source, id: '123456', quality: '1080p60 (Source)', ...changes });
add('wrong Usher host', { usher: usher.replace('usher.ttvnw.net', 'foreign.ttvnw.net') });
add('wrong VOD path', { usher: usher.replace('123456.m3u8', '123457.m3u8') });
add('encoded Usher path', { usher: usher.replace('/vod/', '/%76od/') });
add('wrong source query bytes', { source: source.replace('%2B', '%2b') });
add('source absent from master', { master: master.replace(source, `${origin}/other.m3u8`) });
add('duplicate matching rendition', { master: master + `#EXT-X-STREAM-INF:${attrs}\n${source}\n` });
add('wrong display quality', { quality: '720p' });
add('automatic is not fixed rendition', { quality: 'Automatic' });
add('zero identifier', { id: '0' });
add('leading zero identifier', { id: '0123456' });
add('numeric identifier type', { id: 123456 });
add('unknown stream attribute', { master: master.replace('BANDWIDTH=', 'FOREIGN=1,BANDWIDTH=') });
add('duplicate stream attribute', { master: master.replace('BANDWIDTH=', 'BANDWIDTH=2,BANDWIDTH=') });
add('unfinished rendition', { master: master.replace(source + '\n', '') });
add('unknown required tag', { master: master + '#EXT-X-SESSION-KEY:METHOD=AES-128\n' });
add('bare EXT tag', { master: master + '#EXT\n' });
add('comment before header', { master: '#comment\n' + master });
add('comment with leading whitespace', { master: master + ' #comment\n' });
add('comment with trailing whitespace', { master: master + '#comment \n' });
add('comment with embedded CR', { master: master + '#comment\rbroken\n' });
add('comment with control byte', { master: master + '#comment\u0001\n' });
add('comment not ASCII', { master: master + '#comment\u0080\n' });
add('overlong ignored comment', { master: master + '#' + 'c'.repeat(8192) + '\n' });
add('too many ignored comment lines', { master: master + '#c\n'.repeat(2044) });
add('source only in comment cannot corroborate', { master: master.replace(source, `${origin}/other.m3u8`) + `#${source}\n` });
add('comment does not authorize foreign variant', { source: 'https://foreign.example.test/a.m3u8', master: master.replace(source, '#approved https://dfixture123.cloudfront.net\nhttps://foreign.example.test/a.m3u8') });
add('comment does not authorize unsupported codec', { master: commentedMaster.replace('avc1.4D402A', 'hvc1.1.6.L120') });
add('bad first line', { master: master.replace('#EXTM3U', '#EXTM3X') });
add('non ASCII master', { master: master + '\u0080' });
add('oversized master', { master: 'x'.repeat(262145) });
add('excess master lines', { master: master + '\n'.repeat(2048) });
add('overlong line', { master: master + '#'.repeat(8193) });
add('unsupported HEVC', { master: master.replace('avc1.4D402A', 'hvc1.1.6.L120') });
add('above 1080p', { master: master.replace('1920x1080', '2560x1440') });
add('above finite FPS', { master: master.replace('60.000', '60.011') });
add('unsupported audio', { master: master.replace('mp4a.40.2', 'opus') });
add('separate audio', { master: master.replace('#EXT-X-STREAM-INF:', '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="A",URI="https://foreign.example.test/a.m3u8"\n#EXT-X-STREAM-INF:AUDIO="audio",') });
for (const [name, url] of [
    ['foreign CDN', 'https://foreign.example.test/a.m3u8'], ['wild CloudFront', 'https://arbitrary.cloudfront.net/a.m3u8'],
    ['encoded origin', 'https://d%66ixture123.cloudfront.net/a.m3u8'], ['userinfo', 'https://user@dfixture123.cloudfront.net/a.m3u8'],
    ['port', 'https://dfixture123.cloudfront.net:443/a.m3u8'], ['IP', 'https://127.0.0.1/a.m3u8'],
    ['uppercase', 'https://DFIXTURE123.cloudfront.net/a.m3u8'], ['traversal', `${origin}/../a.m3u8`],
    ['fragment', `${source}#a`], ['backslash', `${origin}/a\\b.m3u8`]
]) add(name, { source: url, master: master.replace(source, url) });
const inputs = () => ({ 'data.json': JSON.stringify({ ...base, comments, bad, acceptedMetadata, rejectedMetadata, acceptedVariantSources, rejectedVariantSources }) });

test('actual VOD descriptor derives exact bounded hints and corroborates one trusted rendition', { timeout: 90000 }, async t => {
    const { result, marker } = await fixture('roku-vod-descriptor', 'normal', inputs());
    t.diagnostic(`${positive(result, marker)} actual pure descriptor assertions; no remote provenance/transport claim`);
});
test('actual descriptor wrong-provenance and ambiguous-rendition mutants cannot pass', { timeout: 210000 }, async t => {
    for (const [before, after, label] of [
        ['if matches > 1 then return invalid', 'if matches > 1 then matches = 1', 'refuse duplicate matching rendition'],
        ['return parsed.origin = "https://usher.ttvnw.net" and parsed.path = "/vod/v2/" + vodId + ".m3u8"', 'return true', 'refuse wrong Usher host'],
        ['if descriptor.metadata[key] <> rebuilt.metadata[key] then return false', "' Deliberately trust claimed hints", 'valid syntax alone cannot establish master provenance'],
        ['else if line.Left(4) = "#EXT"\n                    return invalid', 'else\n                    return invalid', 'non-EXT master comments accept'],
        ['else if line.Left(4) = "#EXT"\n                    return invalid', 'else if false\n                    return invalid', 'refuse unknown required tag']
    ]) {
        const { result, marker } = await fixture('roku-vod-descriptor', 'normal', inputs(), { name: 'rokuVodDescriptor', before, after });
        normal(result);
        assert.ok(result.output.includes(`VOD_P2_FAIL: ${label}`), result.output);
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${label}: actual normal-exit mutation rejected`);
    }
});
test('pure P2 runner rejects stale,duplicate,zero,failure,crash and bounded transport faults', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const text = `VOD_P2_RESULT: ${marker} {"assertions":1,"failures":0}\n`;
    const shaped = output => ({ code: 0, output, timedOut: false, exceeded: false });
    positive(shaped(text), marker);
    for (const output of [text.replace(marker, randomUUID()), text + text, text.replace('"assertions":1', '"assertions":0'), text.replace('"failures":0', '"failures":1'), text + 'VOD_P2_FAIL: x\n', text + 'BRIGHTSCRIPT: ERROR: x\n']) assert.throws(() => positive(shaped(output), marker));
    const timeout = await run(['-e', 'setInterval(() => {},100);'], os.tmpdir(), 150, 1024);
    assert.ok(timeout.timedOut);
    assert.throws(() => positive(timeout, marker));
    const overflow = await run(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.ok(overflow.exceeded);
    assert.throws(() => positive(overflow, marker));
    assert.throws(() => positive({ ...shaped(text), code: 7 }, marker));
});

test('actual bounded session metadata and IVS labels preserve rendition authority and reject guard mutations', { timeout: 210000 }, async t => {
    const { result, marker } = await fixture('roku-vod-descriptor', 'metadata', inputs());
    t.diagnostic(`${positive(result, marker)} actual metadata/corroboration assertions; inert URI is never fetched`);
    for (const [before, after, label] of [
        ['if result.DoesExist("VALUE") = result.DoesExist("URI") then return invalid', "' Deliberately ignore VALUE/URI exclusivity", 'metadata refuse both VALUE and URI'],
        ['if prior.id = identity.id and prior.language = identity.language then return invalid', "' Deliberately ignore duplicate identity", 'metadata refuse duplicate DATA-ID LANGUAGE pair'],
        ['sessionData.Count() >= 64', 'sessionData.Count() >= 65', 'metadata refuse 65 session records'],
        ['rokuDemuxAscii(item["IVS-NAME"], 1, 128)', 'rokuDemuxAscii(item["IVS-NAME"], 1, 129)', 'metadata refuse long IVS-NAME'],
        ['rokuDemuxAscii(pending["IVS-NAME"], 1, 128)', 'rokuDemuxAscii(pending["IVS-NAME"], 1, 129)', 'metadata refuse long STREAM IVS-NAME']
    ]) {
        const { result, marker } = await fixture('roku-vod-descriptor', 'metadata', inputs(), { name: 'rokuVodDescriptor', before, after });
        normal(result);
        assert.ok(result.output.includes(`VOD_P2_FAIL: ${label}`), result.output.slice(-14000));
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${label}: actual normal-exit mutation rejected`);
    }
});

test('actual quoted IVS variant source enum is discarded without changing rendition authority', { timeout: 90000 }, async t => {
    const { result, marker } = await fixture('roku-vod-descriptor', 'variant', inputs());
    t.diagnostic(`${positive(result, marker)} actual enum/authority/canonical-output assertions; no provider-source inference`);
    for (const [before, after, label] of [
        ['if value <> Chr(34) + "source" + Chr(34) and value <> Chr(34) + "transcode" + Chr(34) then return invalid', "' Deliberately admit arbitrary provider source values", 'variant refuse unquoted source'],
        ['if not known or result.DoesExist(key) then return invalid', 'if not known then return invalid', 'variant refuse duplicate source attribute']
    ]) {
        const { result, marker } = await fixture('roku-vod-descriptor', 'variant', inputs(), { name: 'rokuVodDescriptor', before, after });
        normal(result);
        assert.ok(result.output.includes(`VOD_P2_FAIL: ${label}`), result.output.slice(-14000));
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${label}: actual normal-exit mutation rejected`);
    }
});
