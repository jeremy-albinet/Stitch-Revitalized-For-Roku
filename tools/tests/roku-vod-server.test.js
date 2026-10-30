'use strict';
const {test} = require('node:test');
const bsc = require('brighterscript');
const {root,fs,path,assert,replaceFunction,execution,positive,packageFixture,master,playlist} = require('./fixtures/roku-vod-fetch/runner');
const {corpus,makeMedia} = require('./fixtures/roku-vod-chunks/corpus');
const names = ['rokuDemuxCommon','deviceCapabilities','rokuDemuxDescriptor','playbackHls','rokuDemuxBulk','rokuDemuxInitMetadata','rokuDemuxInitGate',
    'rokuDemuxProtocol','rokuDemuxServerPolicy','rokuVodIndex','rokuVodDescriptor','rokuVodProtocol','rokuVodChunks','rokuVodCache','rokuVodFetch',
    'components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.brs'];
function adapt(name,source) {
    if (name === 'deviceCapabilities') source = replaceFunction(source,'isTwitchVariantSupported','');
    if (name === 'rokuVodFetch') for(const fn of ['rvfFileSystem','rvfTransfer','rvfConfigureTransport','rvfReadFile','rvfUrlEvent']) source=replaceFunction(source,fn,'');
    if (name.includes('RokuVodDemuxServer.brs')) {
        source = replaceFunction(source,'rvsPump','');
        assert.equal(source.split('CreateObject("roSocketAddress")').length,2);
        source = source.replace('CreateObject("roSocketAddress")','rsAddress()');
        assert.equal(source.split('CreateObject("roStreamSocket")').length,2);
        source = source.replace('CreateObject("roStreamSocket")','rsListener()');
    }
    return source;
}
async function setup() {
    const server = await fs.readFile(path.join(__dirname,'fixtures/roku-vod-server/main.brs'),'utf8');
    const fetch = await fs.readFile(path.join(__dirname,'fixtures/roku-vod-fetch/main.brs'),'utf8');
    const seed = JSON.parse(await fs.readFile(path.join(__dirname,'fixtures/roku-vod-chunks/init-seed.json'),'utf8'));
    assert.equal(seed.synthetic,true);
    const init = Buffer.from(corpus(Buffer.from(seed.hex,'hex')).init.hex,'hex');
    const media = makeMedia(2);
    const source = await fs.readFile(path.join(root,'source/utils/rokuVodFetch.brs'),'utf8');
    const actual = source.match(/^function rvfConfigureTransport\([^]*?^end function/m);
    assert.ok(actual,'actual native configuration body');
    const harness = replaceFunction(fetch,'main','') + '\n' + server + '\n' + actual[0].replace('function rvfConfigureTransport(', 'function vfActualConfigureTransport(');
    return {harness,extras:{'master.m3u8':master,'index.m3u8':playlist,'init.bin':init,'media.bin':media.input,
        'expected.json':JSON.stringify({video:media.video.toString('hex'),audio:media.audio.toString('hex')})}};
}

test('actual separate VOD Task demand conversion, full manifests, leases, stop and cleanup', async () => {
    const {harness,extras} = await setup();
    const result = await packageFixture(names,harness,adapt,extras);
    console.log(`finite VOD Server actual assertions=${positive(result,'STITCH_VOD_SERVER',result.marker)}`);
});

test('actual VOD Server lease, reservation and init-order mutants fail with normal exit', async () => {
    const {harness,extras} = await setup();
    const mutants = [
        ['lease-close-order','if clean and m.activeLease <> invalid','if m.activeLease <> invalid','failed socket close cannot release lease'],
        ['real-init-gate','validateLiveInitOutput(m.input)','m.result.actualInitValidated = true : m.result.decoderApproved = true','exact master GET and two HEAD/GET transactions before actual decoder approval'],
        ['reserve-before-fetch','m.reservation = rokuVodReserve(m.cache, entryNo, m.sessionId)','m.reservation = { id: "forged" }','full work reserved BEFORE native input allocation'],
        ['head-body','if response.head then return true','if false then return true','HEAD sends truthful range header without body'],
        ['fresh-deadline','return rvsActive() and rvsNow() < deadline','return true','header pump consuming deadline forbids native Receive'],
        ['header-final-deadline',/if not rvsWithin\(deadline\) then return invalid\r?\n +return raw/,'return raw','final complete-header parsing cannot return after deadline']
    ];
    for (const [label,before,after,expectedFailure] of mutants) {
        const result = await packageFixture(names,harness,(name,source)=>{
            source=adapt(name,source);
            if(name.includes('RokuVodDemuxServer.brs')) {assert.equal(source.split(before).length,2,label);source=source.replace(before,after);}
            return source;
        },extras);
        execution(result); assert.match(result.output,/STITCH_VOD_SERVER_FAIL:/,label);
        assert.ok(result.output.includes('fetch-fixture:' + expectedFailure), `actual intended guard detects ${label}\n${result.output}`);
        assert.throws(()=>positive(result,'STITCH_VOD_SERVER',result.marker),label);
    }
});

test('Task dependencies and publication contract remain separate from LIVE state', async () => {
    const xml = await fs.readFile(path.join(root,'components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.xml'),'utf8');
    assert.doesNotMatch(xml,/rokuDemuxCore\.brs|rokuDemuxFetch\.brs|sourceTransitions|trustedTransport|disableRedirect/);
    for(const helper of ['rokuVodIndex','rokuVodChunks','rokuVodDescriptor','rokuVodProtocol','rokuVodCache','rokuVodFetch','rokuDemuxInitGate']) assert.ok(xml.includes(`${helper}.brs`));
    assert.match(xml,/<field id="experimentalMode" type="boolean" value="false"/);
    const source = await fs.readFile(path.join(root,'components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.brs'),'utf8');
    const ready = source.match(/^function rvsReady\([^]*?^end function/m);
    assert.ok(ready,'one actual Ready handler');
    const parsed = bsc.Parser.parse(ready[0],{mode:bsc.ParseMode.BrightScript});
    assert.deepEqual(parsed.diagnostics,[]);
    const keys = parsed.statements[0].func.body.statements[0].value.elements.map(member=>member.keyToken);
    assert.ok(keys.every(key=>key.kind===bsc.TokenKind.StringLiteral),'native cross-Task keys are explicit string literals');
    assert.deepEqual(keys.map(key=>key.text),['sessionId','boundAddressText','boundPort','metadata','decoderApproved','actualInitValidated','requestedDecoderFormat','mode','totalDurationUs','masterPath'].map(key=>'"'+key+'"'));
});
