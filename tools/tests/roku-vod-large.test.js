'use strict';
const {test} = require('node:test');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const sdk = require('brs-node');
const {fs,path,assert,execution,positive,packageFixture} = require('./fixtures/roku-vod-large/runner');
const {inputs} = require('./fixtures/roku-vod-large/corpus');
const names=['rokuDemuxBulk','rokuDemuxInitMetadata','rokuVodChunks'];
async function setup() {
    const seed=JSON.parse(await fs.readFile(path.join(__dirname,'fixtures/roku-vod-chunks/init-seed.json'),'utf8'));
    assert.equal(seed.synthetic,true);
    return {extras:inputs(Buffer.from(seed.hex,'hex')),harness:await fs.readFile(path.join(__dirname,'fixtures/roku-vod-large/main.brs'),'utf8')};
}
test('actual VOD caller splits 9,418,736 bytes of synthetic fragmented input with independent complete byte/time/flag goldens', async t=>{
    const {extras,harness}=await setup();
    const result=await packageFixture(names,harness.replace('__MODE__','golden'),undefined,extras);
    t.diagnostic(`large golden actual assertions=${positive(result,'STITCH_VOD_LARGE',result.marker)}; logical bounds only, native memory/playback pending`);
});
test('actual finite whole/span limits and cancellation after larger video/audio phases retain unchanged Bulk bounds', async t=>{
    const {extras,harness}=await setup();
    const result=await packageFixture(names,harness.replace('__MODE__','planning'),undefined,extras);
    t.diagnostic(`large boundaries actual assertions=${positive(result,'STITCH_VOD_LARGE',result.marker)};128-span check is structural, not a fabricated canonical plan`);
});
test('old span/input profile and widened whole cap mutants fail actual large assertions with normal exit', async t=>{
    const {extras,harness}=await setup();
    for(const [label,before,after,mode,expected] of [
        ['old-input','data.Count() <= 12582912','data.Count() <= 4194304','golden','actual greater4MiB complete input is admitted'],
        ['old-span','atom.finish - chunkStart <= 4194304','atom.finish - chunkStart <= 524288','golden','actual greater4MiB complete input is admitted'],
        ['widened-whole','data.Count() <= 12582912','data.Count() <= 16777216','planning','complete whole input above12MiB refused'],
        ['old-span-count','plan.spans.Count() <= 128','plan.spans.Count() <= 7','planning','actual structural validator accepts128 finite contiguous spans'],
        ['aggregate-pair','rvdcCheck(state.video.Count() + state.audio.Count() <= 16777216)','rvdcCheck(true)','planning','combined outputs above16MiB refuse despite each track below16MiB']
    ]) {
        const result=await packageFixture(names,harness.replace('__MODE__',mode),(name,source)=>{
            if(name==='rokuVodChunks') {assert.equal(source.split(before).length,2,label);source=source.replace(before,after);}return source;
        },extras);
        execution(result);assert.ok(result.output.includes('vod-large-fixture:'+expected),result.output.slice(-6000));
        assert.throws(()=>positive(result,'STITCH_VOD_LARGE',result.marker));t.diagnostic(`${label}: actual normal-exit mutant rejected`);
    }
});


test('large-only public SDK instrumentation preserves numeric and fallback reads without dependency edits', async () => {
    const bundle = require.resolve('brs-node');
    const hash = async () => createHash('sha256').update(await fs.readFile(bundle)).digest('hex');
    const beforeHash = await hash(), beforeGet = sdk.RoByteArray.prototype.get;
    assert.doesNotMatch(beforeGet.toString(), /this\.getElements\(\)/, 'pinned engine no longer copies the buffer per read');
    const child = spawnSync(process.execPath, [path.join(__dirname,'fixtures/roku-vod-large/engine.js'),'--controls'],
        {windowsHide:true,encoding:'utf8',timeout:40000,maxBuffer:1048576});
    assert.equal(child.error,undefined); assert.equal(child.status,0,child.stderr); assert.equal(child.signal,null);
    assert.equal(child.stderr,'');
    const lines=child.stdout.trim().split(/\r?\n/);
    assert.equal(lines.length,1); assert.ok(lines[0].startsWith('VOD_LARGE_ENGINE_CONTROLS '));
    assert.deepEqual(JSON.parse(lines[0].slice('VOD_LARGE_ENGINE_CONTROLS '.length)),{assertions:308,restored:true});
    assert.equal(sdk.RoByteArray.prototype.get,beforeGet,'child cannot alter ordinary parent prototype');
    assert.equal(await hash(),beforeHash,'installed engine bundle is untouched');
    const ordinary=spawnSync(process.execPath,['-e',"const s=require('brs-node');if(/this\\.getElements\\(\\)/.test(s.RoByteArray.prototype.get.toString()))process.exit(1);console.log('ORDINARY_ENGINE_UNCHANGED');"],
        {windowsHide:true,encoding:'utf8',timeout:40000,maxBuffer:1048576});
    assert.equal(ordinary.error,undefined); assert.equal(ordinary.status,0,ordinary.stderr);
    assert.equal(ordinary.stdout.trim(),'ORDINARY_ENGINE_UNCHANGED'); assert.equal(ordinary.stderr,'');
});

test('actual ReadFile,Slice,Append,Count,digests and numeric bytes are identical in ordinary and instrumented CLI children', async t => {
    const bytes=Buffer.from(Array.from({length:256},(_,i)=>i));
    const expected={sha:createHash('sha256').update(bytes).digest('hex'),hex:bytes.toString('hex'),slice:bytes.subarray(127,131).toString('hex'),
        appended:Buffer.concat([bytes.subarray(127,131),bytes.subarray(127,131)]).toString('hex')};
    const harness=`sub checked(ok as boolean, label as string)
    m.assertions++
    if not ok then throw "adapter-control:" + label
end sub
sub main()
    m.assertions = 0
    failures = 0
    try
        data = CreateObject("roByteArray")
        checked(data.ReadFile("pkg:/bytes.bin"), "actual ReadFile")
        expected = ParseJson(ReadAsciiFile("pkg:/expected.json"))
        checked(data.Count() = 256, "actual Count")
        checked(nbBulkDigest(data) = expected.sha, "actual complete digest")
        checked(LCase(data.ToHexString()) = expected.hex, "actual complete bytes")
        for i = 0 to 255
            checked(data[i] = i, "actual indexed byte")
        end for
        checked(data[1.9] = 1 and data[-0.9] = 0, "actual Float truncation")
        checked(data[-1] = invalid and data[256] = invalid, "actual out-of-bound invalid")
        boxedInt = CreateObject("roInt")
        boxedInt.SetInt(128)
        checked(data[boxedInt] = 128, "actual boxed Int32")
        boxedFloat = CreateObject("roFloat")
        boxedFloat.SetFloat(127.9)
        checked(data[boxedFloat] = 127, "actual boxed Float truncation")
        boxedDouble = CreateObject("roDouble")
        boxedDouble.SetDouble(1)
        checked(data[boxedDouble] = 1, "actual boxed Double numeric index")
        stringRefused = false
        try
            unused = data["count"]
        catch error
            stringRefused = error.message = "Attempt to use a non-numeric array index not allowed."
        end try
        checked(stringRefused, "actual interpreter still refuses String indexing")
        invalidRefused = false
        try
            unused = data[invalid]
        catch error
            invalidRefused = error.message = "Attempt to use a non-numeric array index not allowed."
        end try
        checked(invalidRefused, "actual interpreter still refuses Invalid indexing")
        sliced = data.Slice(127,131)
        checked(sliced.Count() = 4 and LCase(sliced.ToHexString()) = expected.slice, "actual bounded Slice")
        sliced.Append(sliced)
        checked(sliced.Count() = 8 and LCase(sliced.ToHexString()) = expected.appended, "actual Append retains bytes")
        checked(data.Count() = 256 and nbBulkDigest(data) = expected.sha, "original source immutable")
        empty = CreateObject("roByteArray")
        checked(empty[0] = invalid and empty.Count() = 0, "actual empty array")
    catch error
        failures = 1
        print "STITCH_VOD_LARGE_FAIL: __MARKER__ " + error.message
    end try
    print "STITCH_VOD_LARGE_PASS: __MARKER__ " + FormatJson({assertions:m.assertions,failures:failures})
end sub`;
    for(const ordinaryEngine of [true,false]) {
        const result=await packageFixture(['rokuDemuxBulk'],harness,undefined,{'bytes.bin':bytes,'expected.json':JSON.stringify(expected)},ordinaryEngine);
        assert.equal(positive(result,'STITCH_VOD_LARGE',result.marker),271);
        t.diagnostic(`${ordinaryEngine?'ordinary':'instrumented'} CLI:271 actual byte/file/slice/append/digest assertions; no source or native API substitution`);
    }
});


test('large-worker proof and positive guards reject missing,duplicate,stale,reordered,late,crash and nonstandard exits', () => {
    const marker='12345678-1234-1234-1234-123456789012';
    const ready='VOD_LARGE_WORKER_READY '+marker, read='VOD_LARGE_WORKER_INDEX_READ '+marker;
    const summary='STITCH_VOD_LARGE_PASS: '+marker+' {"assertions":1,"failures":0}';
    const base={marker,workerAdapter:true,code:0,output:ready+'\n'+read+'\n'+summary+'\n',bytes:200,timedOut:false,exceeded:false};
    assert.equal(positive(base,'STITCH_VOD_LARGE',marker),1);
    for(const output of [read+'\n'+summary,ready+'\n'+summary,ready+'\n'+ready+'\n'+read+'\n'+summary,
        ready+'\n'+read+'\n'+read+'\n'+summary,base.output.replace(marker,'stale'),read+'\n'+ready+'\n'+summary,
        ready+'\n'+summary+'\n'+read,base.output+'BRIGHTSCRIPT: ERROR: actual throw\n',base.output+'EXIT_BRIGHTSCRIPT_CRASH\n',
        base.output.replace('"failures":0','"failures":1'),base.output.replace('"assertions":1','"assertions":0'),base.output+summary+'\n']) {
        assert.throws(()=>positive({...base,output},'STITCH_VOD_LARGE',marker));
    }
    for(const change of [{code:1},{timedOut:true},{exceeded:true},{startupError:'Error'}]) {
        assert.throws(()=>positive({...base,...change},'STITCH_VOD_LARGE',marker));
    }
});
