'use strict';
const {test} = require('node:test');
const {root,fs,path,assert,replaceFunction,execution,positive,packageFixture,master,playlist} = require('./fixtures/roku-vod-fetch/runner');
const names = ['rokuDemuxCommon','deviceCapabilities','rokuDemuxDescriptor','playbackHls','rokuVodIndex','rokuVodDescriptor','rokuVodProtocol','rokuVodFetch'];
const boundaries = ['rvfFileSystem','rvfTransfer','rvfConfigureTransport','rvfReadFile','rvfUrlEvent'];
const adapt = (name,source) => name === 'rokuVodFetch' ? boundaries.reduce((text,fn)=>replaceFunction(text,fn,''),source) : source;

async function fixture() {
    const harness = await fs.readFile(path.join(__dirname,'fixtures/roku-vod-fetch/main.brs'),'utf8');
    const source = await fs.readFile(path.join(root,'source/utils/rokuVodFetch.brs'),'utf8');
    const actual = source.match(/^function rvfConfigureTransport\([^]*?^end function/m);
    assert.ok(actual,'actual native configuration body');
    return harness + '\n' + actual[0].replace('function rvfConfigureTransport(', 'function vfActualConfigureTransport(');
}

test('actual finite VOD transfer source, master authority, identity, framing and verified cleanup', async () => {
    const harness = await fixture();
    const result = await packageFixture(names,harness,adapt,{'master.m3u8':master,'index.m3u8':playlist});
    console.log(`finite VOD Fetch actual assertions=${positive(result,'STITCH_VOD_FETCH',result.marker)}`);
});

test('actual Fetch guard-removal mutants fail assertions despite normal engine exit', async () => {
    const harness = await fixture();
    const mutants = [
        ['old-master-HEAD','if intent.kind = "master" then phase = "get"','if intent.kind = "master" then phase = "head"','Usher master starts one direct GET without HEAD'],
        ['master-before-CDN','if not state.trusted then return invalid','if false then return invalid','master corroboration precedes all CDN requests'],
        ['identity','if event.GetSourceIdentity() <> op.identity then return false','if false then return false','late HEAD event ignored'],
        ['delete-before-output','rvfCheck(rvfDeleteInput(state), "completed_cleanup")','state.ownFile = false','deleted staging before completed output'],
        ['native-configuration-refusal','rvfCheck(rvfConfigureTransport(transfer, intent.url), "transport_configuration")','unused = true','failed native transport configuration refuses before Async'],
        ['non-master-count-pairing','rvfCheck(count = op.headCount, "head_get_count")','unused = true','non-master HEAD GET count mismatch refuses and deletes'],
        ['non-master-sentinel','if op.intent.kind <> "master" or op.headCount <> -1','if op.headCount <> -1','only master may use absent HEAD count sentinel'],
        ['master-sentinel','if op.intent.kind <> "master" or op.headCount <> -1','if op.intent.kind <> "master"','master exception requires exact minus one sentinel'],
        ['media-cap-widened','url: item.uri, limit: 12582912','url: item.uri, limit: 16777216','only completed authorized media gets12MiB cap']
    ];
    for (const [label,before,after,expectedFailure] of mutants) {
        const result = await packageFixture(names,harness,(name,source)=>{
            source = adapt(name,source); if(name==='rokuVodFetch'){assert.equal(source.split(before).length,2,label); source=source.replace(before,after);} return source;
        },{'master.m3u8':master,'index.m3u8':playlist});
        execution(result); assert.match(result.output,/STITCH_VOD_FETCH_FAIL:/,label);
        assert.ok(result.output.includes('fetch-fixture:' + expectedFailure), `actual intended guard detects ${label}\n${result.output}`);
        assert.throws(()=>positive(result,'STITCH_VOD_FETCH',result.marker),label);
    }
});

test('native VOD transport uses documented TLS methods without authentication or cookie opt-in', async () => {
    const source = await fs.readFile(path.join(root,'source/utils/rokuVodFetch.brs'),'utf8');
    for (const method of ['SetCertificatesFile','EnablePeerVerification','EnableHostVerification','EnableEncodings','EnableResume','SetMinimumTransferRate']) assert.ok(source.includes(`transfer.${method}(`));
    assert.doesNotMatch(source, /\.EnableCookies\(|Authorization|Client-Id|Device-ID|SetUserAndPassword|SetClientCertificate/);
    assert.doesNotMatch(source,/SetMaxRedirects|SetFollowLocation|\.GetUrl\(/);
});

test('finite backend result validator rejects stale, crashed, failed and truncated children', () => {
    const marker = 'fresh-unit-marker';
    const prefix = 'STITCH_VOD_FETCH';
    const output = `${prefix}_PASS: ${marker} ${JSON.stringify({assertions: 3, failures: 0})}\n`;
    const valid = {code:0,output,bytes:output.length,timedOut:false,exceeded:false,startupError:undefined};
    assert.equal(positive(valid,prefix,marker),3);
    for(const mutation of [
        {timedOut:true}, {exceeded:true}, {code:1}, {startupError:'spawn failure'},
        {output:output.replace(marker,'stale')}, {output:output+output}, {output:''},
        {output:output.replace('"assertions":3','"assertions":0')},
        {output:output.replace('"failures":0','"failures":1')},
        {output:`${prefix}_FAIL: deliberately failed normal exit\n${output}`},
        {output:`EXIT_BRIGHTSCRIPT_CRASH\n${output}`}, {output:`BRIGHTSCRIPT: ERROR: crash\n${output}`}
    ]) assert.throws(()=>positive({...valid,...mutation},prefix,marker));
});
