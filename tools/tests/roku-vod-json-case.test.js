'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const bsc = require('brighterscript');
const {root,packageFixture,positive,execution,master} = require('./fixtures/roku-vod-fetch/runner');

// Native Roku preserves quoted AA keys, lowercases identifier keys/assignments,
// and ParseJson returns case-sensitive nested AAs by default. brs-engine alone
// preserves identifier spelling, so source projection is an essential guard.
// Bracket reads enforce our exact serialized-key contract. Current Roku docs
// describe dot lookups as case-insensitive, not a proven invalid native read.
// https://developer.roku.com/dev/docs/roassociativearray
// https://developer.roku.com/dev/docs/global-utility-functions#parsejson
// https://developer.roku.com/dev/docs/expressions-variables-types
const descriptor = ['vodId','usherUrl','sourceUrl','qualityId','approvedOrigin'];
const metadata = ['videoCodec','audioCodec','frameRate','isHD'];
const ready = ['sessionId','boundAddressText','boundPort','decoderApproved','actualInitValidated',
    'requestedDecoderFormat','totalDurationUs','masterPath'];
const scope = new Map([
    ['source/utils/rokuVodDescriptor.brs', {reads:[...descriptor,...metadata],keys:descriptor}],
    ['source/utils/rokuVodRuntime.brs', {reads:[...descriptor,...metadata,...ready],keys:[]}],
    ['source/utils/rokuVodFetch.brs', {reads:descriptor,keys:[]}],
    ['source/utils/rokuVodProtocol.brs', {functions:['rokuVodMasterManifest'],reads:metadata,keys:[]}],
    ['source/utils/rokuDemuxInitGate.brs', {functions:['validateLiveInitOutput'],reads:['frameRate'],keys:[]}],
    ['components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.brs', {reads:[...descriptor,...metadata],keys:ready,keyFunctions:['rvsReady']}],
    ['components/Modules/RokuDemuxSession/RokuDemuxSession.brs', {functions:['onSessionReady'],reads:['sessionId','totalDurationUs','masterPath'],keys:['totalDurationUs','masterPath']}],
    ['components/Scenes/VideoPlayer/RokuPlayback.brs', {functions:['onRokuSessionEvent'],reads:['qualityId','isHD'],keys:[]}],
    ['components/Tasks/GetTwitchContent/GetTwitchContent.brs', {functions:['loadHlsContent'],reads:[],keys:['sourceUrl','qualityId']}],
    ['source/utils/rokuDemuxDescriptor.brs', {functions:['rokuDemuxMetadataHints'],reads:[],keys:metadata}]
]);
const walk = {walkMode:bsc.WalkMode.visitAllRecursive};
function literal(node) {
    return bsc.isLiteralExpression(node) && node.token.kind === bsc.TokenKind.StringLiteral ?
        node.token.text.slice(1,-1).replaceAll('""','"') : undefined;
}
function inspect(source, file) {
    const policy = scope.get(file);
    assert.ok(policy, 'explicit source-boundary scope');
    const parsed = bsc.Parser.parse(source,{mode:bsc.ParseMode.BrightScript});
    assert.deepEqual(parsed.diagnostics,[],`${file}: actual source syntax`);
    const mutations = [];
    const fn = node => node.findAncestor(bsc.isFunctionExpression)?.functionStatement?.name.text;
    const included = node => !policy.functions || policy.functions.includes(fn(node));
    parsed.ast.walk(bsc.createVisitor({
        AAMemberExpression(node) {
            if (!included(node) || (policy.keyFunctions && !policy.keyFunctions.includes(fn(node)))) return;
            const quoted = node.keyToken.kind === bsc.TokenKind.StringLiteral;
            const key = quoted ? node.keyToken.text.slice(1,-1) : node.keyToken.text;
            if (!policy.keys.includes(key)) return;
            const native = quoted ? key : key.toLowerCase();
            assert.equal(native,key,`${file}:${node.range.start.line+1}: native wire key ${key} becomes ${native}`);
            mutations.push({range:node.keyToken.range,replacement:key,kind:'unquoted-key'});
        },
        DottedGetExpression(node) {
            if (!included(node) || !policy.reads.includes(node.name.text)) return;
            assert.fail(`${file}:${node.range.start.line+1}: non-exact dot ${node.name.text} violates the serialized-key access contract`);
        },
        IndexedGetExpression(node) {
            if (!included(node)) return;
            const key = literal(node.index);
            const canonical = policy.reads.find(name=>name.toLowerCase() === key?.toLowerCase());
            if (!canonical) return;
            assert.equal(key,canonical,`${file}: exact serialized lookup spelling`);
            mutations.push({range:{start:node.obj.range.end,end:node.range.end},replacement:'.'+key,kind:'non-exact-dot'});
        }
    }),walk);
    return mutations;
}
function mutate(source, change) {
    const lines=source.split(/\r?\n/);
    const offset=position=>lines.slice(0,position.line).reduce((n,line)=>n+line.length+1,0)+position.character;
    const normalized=lines.join('\n');
    return normalized.slice(0,offset(change.range.start))+change.replacement+normalized.slice(offset(change.range.end));
}

test('actual VOD JSON boundaries preserve canonical native keys and exact case-sensitive lookups',async t=>{
    let sites=0;
    for (const [file] of scope) {
        const source=await fs.readFile(path.join(root,file),'utf8');
        sites+=inspect(source,file).length;
        inspect(source.replaceAll('\r\n','\n').replaceAll('\n','\r\n'),file);
        inspect("' unrelated comment sourceUrl: descriptor.sourceUrl\n"+source,file);
    }
    assert.ok(sites>30,'actual boundary coverage must remain meaningful');
    t.diagnostic(`${scope.size} actual source boundaries/${sites} quoted-key or exact-lookup sites; no native playback claim`);
});

test('each actual mixed-case wire-key or bracket-read regression is rejected',async t=>{
    let rejected=0;
    for (const [file] of scope) {
        const source=await fs.readFile(path.join(root,file),'utf8');
        for (const change of inspect(source,file)) {
            assert.throws(()=>inspect(mutate(source,change),file),/native wire key|non-exact dot/,`${file} ${change.kind}`);
            rejected++;
        }
    }
    assert.ok(rejected>30);
    t.diagnostic(`${rejected} individually applied actual-source mutations rejected; no production mutation`);
});

const names=['rokuDemuxCommon','deviceCapabilities','rokuDemuxDescriptor','playbackHls','rokuDemuxProtocol','rokuVodIndex',
    'rokuVodDescriptor','rokuVodProtocol','rokuVodRuntime','rokuVodFetch',
    'components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.brs'];
test('actual descriptor, Fetch clone, Server Ready and runtime validators retain JSON contract values',async t=>{
    const harness=await fs.readFile(path.join(__dirname,'fixtures/roku-vod-json-case/main.brs'),'utf8');
    const result=await packageFixture(names,harness,undefined,{'master.m3u8':master});
    const count=positive(result,'STITCH_VOD_JSON_CASE',result.marker);
    t.diagnostic(`${count} actual bounded assertions across JSON clones; AST controls supply native case semantics`);
});

test('failed native-case assertion still rejects a normal-exit package',async ()=>{
    const harness=await fs.readFile(path.join(__dirname,'fixtures/roku-vod-json-case/main.brs'),'utf8');
    const anchor='caseCheck(true, "negative summary anchor")';
    assert.equal(harness.split(anchor).length,2);
    const result=await packageFixture(names,harness.replace(anchor,'caseCheck(false, "deliberate case failure")'),undefined,{'master.m3u8':master});
    execution(result);
    assert.match(result.output,/STITCH_VOD_JSON_CASE_FAIL: deliberate case failure/);
    assert.throws(()=>positive(result,'STITCH_VOD_JSON_CASE',result.marker));
});
