'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const {zipFolder} = require('roku-deploy');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/ad-live-session-integration');
const manager = 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs';
const server = 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs';
const prefix = 'stitch-ad-live-session-';
const helpers = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch', 'rokuDemuxCommon',
    'rokuDemuxProtocol', 'rokuDemuxInitMetadata', 'rokuDemuxServerPolicy', 'rokuDemuxInitGate',
    'rokuDemuxDescriptor', 'playbackHls', 'twitchAdCountdown', 'twitchAdClock', 'twitchAdProtocol']
    .map(name => `source/utils/${name}.brs`);

function child(args, cwd) {
    return new Promise(resolve => {
        const start = performance.now();
        const proc = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), ...args],
            {cwd, windowsHide:true, stdio:['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => {timedOut = true; proc.kill();}, 30000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 65536) {exceeded = true; proc.kill(); return;}
            output += data.toString();
        };
        proc.stdout.on('data', collect); proc.stderr.on('data', collect);
        proc.once('error', error => {startupError = error.name;});
        proc.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({code, signal, output, bytes, timedOut, exceeded, startupError, elapsedMs:Math.round(performance.now()-start)});
        });
    });
}

function normal(result) {
    const detail = result.output.slice(-10000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail); assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail); assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception|failed to set up component/i, detail);
    assert.doesNotMatch(result.output, /PRIVATE_ID|private\.invalid|SECRET|fixture\.ttvnw\.net/, 'no source URI/provider data in diagnostics');
}

function positive(result, marker, snapshot = false) {
    normal(result);
    assert.doesNotMatch(result.output, /AD_LIVE_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    const begin = `AD_LIVE_BEGIN: ${marker}`;
    assert.deepEqual(lines.filter(line => line.startsWith('AD_LIVE_BEGIN: ')), [begin]);
    const end = lines.filter(line => line.startsWith('AD_LIVE_END: '));
    assert.equal(end.length, 1, result.output);
    const tag = `AD_LIVE_END: ${marker} `;
    assert.ok(end[0].startsWith(tag));
    assert.ok(lines.indexOf(begin) < lines.indexOf(end[0]));
    const counts = JSON.parse(end[0].slice(tag.length));
    assert.deepEqual(Object.keys(counts).sort(), snapshot ? ['assertions','failures','snapshot'] : ['assertions','failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.equal(counts.failures, 0);
    if (snapshot) {
        assert.deepEqual(counts.snapshot, {version:1,enableAdMetadata:true,experimentalMode:true,cacheBudgetBytes:25165824,listenPort:0});
    }
    return counts;
}

async function withTemp(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    try {return await action(dir);} finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive:true, force:true});
    }
}

async function add(dir, file, data) {
    const target = path.join(dir, file);
    await fs.mkdir(path.dirname(target), {recursive:true});
    await fs.writeFile(target, data);
}

function uniqueReplace(source, before, after) {
    assert.equal(source.split(before).length, 2, `one exact source boundary: ${before}`);
    return source.replace(before, after);
}

async function session(dir, marker, mutation) {
    const pkg = path.join(dir, 'package');
    const actual = await fs.readFile(path.join(root, manager), 'utf8');
    let source = uniqueReplace(actual, 'CreateObject("roSGNode", "RokuDemuxServer")', 'CreateObject("roSGNode", "AdSessionWorkerBoundary")');
    if (mutation === 'disabled') source = uniqueReplace(source,
        'm.worker.enableAdMetadata = true', 'm.worker.enableAdMetadata = false');
    if (mutation === 'future') source = uniqueReplace(source,
        'if rokuDemuxInteger(descriptor["version"]) and descriptor["version"] = 1', 'if true');
    source += '\nfunction adFixtureRead() as object\n    return {worker:m.worker}\nend function\nsub adFixtureBegin(id as string, descriptor as object)\n    beginSession(id,descriptor)\nend sub\n';
    await add(pkg, manager, source);
    let xml = await fs.readFile(path.join(root, manager.replace('.brs','.xml')), 'utf8');
    xml = uniqueReplace(xml, '</interface>', '<function name="adFixtureRead"/><function name="adFixtureBegin"/></interface>');
    await add(pkg, manager.replace('.brs','.xml'), xml);
    for (const name of ['taskFactory','rokuDemuxDescriptor','playbackHls','deviceCapabilities',
        'rokuVodIndex','rokuVodDescriptor','rokuVodRuntime']) {
        const file = `source/utils/${name}.brs`;
        const bytes = await fs.readFile(path.join(root, file));
        await add(pkg, file, bytes);
        assert.deepEqual(await fs.readFile(path.join(pkg,file)), bytes);
    }
    // Match the actual production Task's strict Boolean false field contract.
    const actualXml = await fs.readFile(path.join(root, server.replace('.brs','.xml')), 'utf8');
    assert.match(actualXml, /<field id="enableAdMetadata" type="boolean" value="false"\s*\/>/);
    const workerFields = `<field id="sessionId" type="string"/><field id="inputDescriptor" type="assocarray"/>
        <field id="experimentalMode" type="boolean" value="false"/>
        <field id="cacheBudgetBytes" type="integer"/><field id="listenPort" type="integer"/><field id="functionName" type="string"/>
        <field id="control" type="string" onChange="onControl"/><field id="state" type="string" value="init" alwaysNotify="true"/>
        <field id="ready" type="assocarray" alwaysNotify="true"/><field id="result" type="assocarray" alwaysNotify="true"/>
        <field id="stopRequested" type="boolean" value="false"/>`;
    const vodXml = await fs.readFile(path.join(root, 'components/Tasks/RokuVodDemuxServer/RokuVodDemuxServer.xml'), 'utf8');
    assert.doesNotMatch(vodXml, /<field id="enableAdMetadata"/);
    await add(pkg, 'components/RokuVodDemuxServer.xml', `<component name="RokuVodDemuxServer" extends="Group"><interface>${workerFields}</interface><script uri="AdSessionWorkerBoundary.brs"/></component>`);
    await add(pkg, 'components/AdSessionWorkerBoundary.xml', `<component name="AdSessionWorkerBoundary" extends="Group"><interface>
        <field id="sessionId" type="string"/><field id="inputDescriptor" type="assocarray"/>
        <field id="experimentalMode" type="boolean" value="false"/><field id="enableAdMetadata" type="boolean" value="false"/>
        <field id="cacheBudgetBytes" type="integer"/><field id="listenPort" type="integer"/><field id="functionName" type="string"/>
        <field id="control" type="string" onChange="onControl"/><field id="state" type="string" value="init" alwaysNotify="true"/>
        <field id="ready" type="assocarray" alwaysNotify="true"/><field id="result" type="assocarray" alwaysNotify="true"/>
        <field id="stopRequested" type="boolean" value="false"/></interface><script uri="AdSessionWorkerBoundary.brs"/></component>`);
    await add(pkg,'components/AdSessionWorkerBoundary.brs','sub onControl()\n if m.top.control = "run" then m.top.state = "run"\n if m.top.control = "stop" then m.top.state = "stop"\nend sub\n');
    for (const name of ['TwitchApiTask','GetTwitchContent']) await add(pkg,`components/${name}.xml`,`<component name="${name}" extends="Group"/>`);
    await add(pkg,'components/AdSessionHarness.xml','<component name="AdSessionHarness" extends="Scene"><interface><function name="runTests"/><field id="result" type="assocarray"/></interface><script uri="session.brs"/><script uri="pkg:/source/utils/rokuDemuxDescriptor.brs"/><script uri="pkg:/source/utils/playbackHls.brs"/><script uri="pkg:/source/utils/deviceCapabilities.brs"/><script uri="pkg:/source/utils/rokuVodIndex.brs"/><script uri="pkg:/source/utils/rokuVodDescriptor.brs"/></component>');
    await add(pkg,'components/session.brs',(await fs.readFile(path.join(fixture,'session.brs'),'utf8')).replaceAll('__MARKER__',marker));
    await add(pkg,'source/main.brs',`sub main()
        screen=CreateObject("roSGScreen")
        scene=screen.CreateScene("AdSessionHarness")
        screen.Show()
        print "AD_LIVE_BEGIN: ${marker}"
        scene.callFunc("runTests")
        print "AD_LIVE_END: ${marker} "; FormatJson(scene.result)
        screen.Close()
    end sub`);
    await add(pkg,'manifest','title=Offline Ad Live Session\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    await add(pkg,'bsconfig.json',JSON.stringify({rootDir:pkg,files:['source/**/*','components/**/*','manifest'],plugins:[],createPackage:false,copyToStaging:false,deploy:false,watch:false,logLevel:'off',showDiagnosticsInConsole:false}));
    const builder = new bsc.ProgramBuilder();
    try {
        await builder.run({project:path.join(pkg,'bsconfig.json')});
        assert.deepEqual(builder.getDiagnostics().map(d=>({code:d.code,message:d.message,file:d.file?.pkgPath,line:d.range?.start.line})),[]);
    } finally {builder.program?.dispose();}
    const zip=path.join(dir,'session.zip');
    await zipFolder(pkg,zip);
    const result=await child([zip],dir);
    assert.equal(await fs.readFile(path.join(root,manager),'utf8'),actual);
    return result;
}

async function pipeline(dir, marker, snapshot, mutation) {
    await add(dir,'worker-config.json',JSON.stringify(snapshot));
    await add(dir,'corpus.json',await fs.readFile(path.join(__dirname,'fixtures/roku-demux-core/corpus.json')));
    const originals = new Map();
    for (const file of [...helpers,server]) {
        const bytes = await fs.readFile(path.join(root,file)); originals.set(file,bytes);
        let source=bytes.toString();
        if (file.endsWith('/rokuDemuxFetch.brs')) {
            source=uniqueReplace(source,'Type(event) <> "roUrlEvent"','ioType(event) <> "roUrlEvent"');
            source=uniqueReplace(source,'payload = ReadAsciiFile(nlInputPath())','payload = ioRead(nlInputPath())');
            source=source.replaceAll('CreateObject("roFileSystem")','ioCreate("roFileSystem")');
            source=source.replaceAll('CreateObject("roUrlTransfer")','ioCreate("roUrlTransfer")');
        }
        if (file===server) {
            for (const name of ['roTimespan','roMessagePort']) source=source.replaceAll(`CreateObject("${name}")`,`ioCreate("${name}")`);
            source=uniqueReplace(source,'event = wait(delayMs, m.port)','event = ioWait(delayMs, m.port)');
            if (mutation==='forward') source=uniqueReplace(source,'m.liveState.adClockEnabled = m.adMetadataEnabled','m.liveState.adClockEnabled = false');
            if (mutation==='seal') source=uniqueReplace(source,'if FormatJson(projection) = entry.adProjectionSeal then bytes = twitchAdClockManifest(request.track, publication, projection)',
                'bytes = twitchAdClockManifest(request.track, publication, projection)');
        }
        assert.deepEqual(bsc.Parser.parse(source,{mode:bsc.ParseMode.BrightScript}).diagnostics,[],file);
        await add(dir,path.basename(file),source);
    }
    const device=await fs.readFile(path.join(root,'source/utils/deviceCapabilities.brs'),'utf8');
    const hex=device.match(/^function playbackHexValue\b[^]*?^end function\r?$/gmi);
    assert.equal(hex?.length,1,'actual descriptor codec parser dependency copied exactly');
    await add(dir,'hex-reference.brs',hex[0]+'\n');
    const main=(await fs.readFile(path.join(fixture,'pipeline.brs'),'utf8')).replaceAll('__MARKER__',marker);
    assert.deepEqual(bsc.Parser.parse(main,{mode:bsc.ParseMode.BrightScript}).diagnostics,[]);
    await add(dir,'main.brs',main);
    const result=await child(['--no-sg','--root',dir,...[...helpers,server].map(file=>path.basename(file)),'hex-reference.brs','main.brs'],dir);
    for (const [file,bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root,file)),bytes);
    return result;
}

test('actual consented LIVE Session Boolean reaches real Fetch/Core/Server projected ad timeline', {timeout:110000}, async t=> {
    await withTemp(async dir=> {
        const marker=randomUUID();
        const start=await session(dir,marker);
        const actual=positive(start,marker,true);
        const result=await pipeline(dir,marker,actual.snapshot);
        const counts=positive(result,marker);
        t.diagnostic(JSON.stringify({sessionAssertions:actual.assertions,pipelineAssertions:counts.assertions,
            sessionMs:start.elapsedMs,pipelineMs:result.elapsedMs,nativeTransportDecoderAndFrameObservation:'mocked'}));
    });
});

test('actual disabled/future Session and Server forwarding source mutants fail despite normal engine exit', {timeout:145000}, async t=> {
    await withTemp(async dir=> {
        const marker=randomUUID();
        for (const mutation of ['disabled','future']) {
            const result=await session(dir,marker,mutation);
            normal(result); assert.throws(()=>positive(result,marker,true));
            assert.match(result.output,/AD_LIVE_FAIL:/);
            t.diagnostic(JSON.stringify({mutation,normalExit:true,rejected:true,elapsedMs:result.elapsedMs}));
        }
        const actual=positive(await session(dir,marker),marker,true);
        for (const mutation of ['forward','seal']) {
            const result=await pipeline(dir,marker,actual.snapshot,mutation);
            normal(result); assert.throws(()=>positive(result,marker));
            assert.match(result.output,/AD_LIVE_FAIL:/);
            t.diagnostic(JSON.stringify({mutation,normalExit:true,rejected:true,elapsedMs:result.elapsedMs}));
        }
    });
});

test('ad integration output has bounded fresh LF/CRLF summaries and rejects stale, empty or crashed runs', ()=> {
    const marker='fresh-control';
    const output=`AD_LIVE_BEGIN: ${marker}\nAD_LIVE_END: ${marker} {"assertions":1,"failures":0}\n`;
    const good={code:0,signal:null,output,timedOut:false,exceeded:false};
    positive(good,marker); positive({...good,output:output.replaceAll('\n','\r\n')},marker);
    for (const control of [{code:1},{signal:'SIGTERM'},{timedOut:true},{exceeded:true},{startupError:'Error'},
        {output:output.replace('"assertions":1','"assertions":0')},{output:output.replace('"failures":0','"failures":1')},
        {output:output.replaceAll(marker,'stale')},{output:output+output},{output:output.trim().split('\n').reverse().join('\n')},
        {output:output+'BRIGHTSCRIPT: ERROR: crash\n'},{output:output+'PRIVATE_ID\n'}]) assert.throws(()=>positive({...good,...control},marker));
});
