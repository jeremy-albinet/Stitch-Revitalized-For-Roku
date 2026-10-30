'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const {zipFolder} = require('roku-deploy');
const corpus = require('./fixtures/chat-gifs/corpus');
const webp = require('./fixtures/chat-animation/corpus');
const atlasCorpus = require('./fixtures/chat-gifs/atlas-corpus');
const {enginePngBoundary} = require('./fixtures/chat-gifs/atlas-boundary');
const {deflateSync} = require('node:zlib');
const root = path.resolve(__dirname, '../..');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const fixtures = path.join(__dirname, 'fixtures/chat-gifs');

async function add(dir, name, data) {
    const file = path.join(dir, name);
    await fs.mkdir(path.dirname(file), {recursive:true});
    await fs.writeFile(file, data);
}
async function execute(build, sceneGraph = false) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-gif-'));
    const marker = `GIF_PASS_${randomUUID()}`;
    try {
        await build(dir, marker);
        const sources = (await fs.readdir(dir)).filter(file => file.endsWith('.brs'));
        let args = [cli, '--no-sg', '--root', dir, ...sources];
        if (sceneGraph) {
            const zip = path.join(dir, 'app.zip');
            await zipFolder(path.join(dir, 'package'), zip);
            args = [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'), cli, zip];
        }
        const result = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, args, {cwd:dir,windowsHide:true});
            let output = '', timedOut = false;
            const timer = setTimeout(() => {timedOut=true; child.kill();}, 45000);
            const collect = data => {output+=data; if(output.length>1024*1024) child.kill();};
            child.stdout.on('data',collect); child.stderr.on('data',collect);
            child.on('error',reject);
            child.on('close',code => {clearTimeout(timer);resolve({code,output,timedOut});});
        });
        assert.equal(result.timedOut,false,result.output.slice(-10000));
        assert.equal(result.code,0,result.output.slice(-10000));
        assert.doesNotMatch(result.output,/STITCH_TEST_FAIL:|runtime error|BrightScript Debugger|EXIT_BRIGHTSCRIPT_CRASH|unhandled exception|failed to set up component/i);
        if (sceneGraph) assert.match(result.output, /EXIT_USER_NAV/);
        const count=result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(count && Number(count[1])>0,`fresh nonzero summary required\n${result.output.slice(-10000)}`);
        return Number(count[1]);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)),path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith('stitch-gif-'));
        await fs.rm(dir,{recursive:true,force:true});
    }
}
async function helpers(dir, names) {
    for(const name of names) await add(dir,`${name}.brs`,await fs.readFile(path.join(root,`source/utils/${name}.brs`)));
}
test('actual Twitch GIF parser preserves documented URLs/titles and validates bounded code-point occurrences', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['ircParser','ircEmotes','ircGifs']);
        const main=await fs.readFile(path.join(root,'source/tests/offline/chat-gifs.brs'),'utf8');
        await add(dir,'main.brs',main.replace('STITCH_TEST_PASS: chat-gifs ',`${marker}: `));
    });
    t.diagnostic(`${count} actual BrightScript wire/parser assertions; Unicode and negative cases are authored fixtures`);
});
test('actual GIF structural admission accepts the pinned public sample and rejects malformed/budget mutations', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['chatAnimationGif']);
        await add(dir,'main.brs',(await fs.readFile(path.join(fixtures,'admission-main.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        await add(dir,'cases.json',JSON.stringify(corpus.cases.map(({bytes,...sample})=>sample)));
        for(const sample of corpus.cases) await add(dir,`${sample.name}.gif`,sample.bytes);
    });
    t.diagnostic(`${count} actual structural assertions; no LZW decode or native playback proof`);
});
test('actual GIF Task preserves URL, requires HEAD/GET/final stat, bounds time, and cleans cancellations', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['chatAnimationGif','chatAnimationWebp','ircEmotes','ircGifs']);
        const source=await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimationAsset/ChatAnimationAsset.brs'),'utf8');
        assert.equal((source.match(/\bfs\.stat\(/g)||[]).length,2,'only polling and final stat are explicit boundaries');
        await add(dir,'task.brs',source.replace(/\bcreateObject\("(roFileSystem|roMessagePort|roTimespan|roUrlTransfer|roByteArray)"\)/gi,'fixtureCreateObject("$1")')
            .replace(/\bwait\(/gi,'fixtureWait(').replace('type(event) = "roUrlEvent"','fixtureIsUrlEvent(event)')
            .replace(/\bfs\.stat\(([^)]*)\)/g,'fixtureStat(fs, $1)'));
        await add(dir,'atlas.brs',enginePngBoundary(await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimationAsset/ChatGifAtlas.brs'),'utf8')));
        await add(dir,'main.brs',(await fs.readFile(path.join(fixtures,'asset-main.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        await add(dir,'tiny.gif',corpus.tiny);
        await add(dir,'twitch-official.gif',corpus.official);
        await add(dir,'petpet.webp',webp.petpet);
    });
    t.diagnostic(`${count} actual Task/filesystem assertions with HTTP/clock and PNG-format boundaries; not a native/network performance claim`);
});

function rgbaPng() {
    function crc32(bytes) {let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
    function chunk(type,data){const body=Buffer.concat([Buffer.from(type),data]);const size=Buffer.alloc(4);size.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(body));return Buffer.concat([size,body,crc]);}
    const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(2);ihdr.writeUInt32BE(2,4);ihdr[8]=8;ihdr[9]=6;
    const raw=Buffer.from([0,255,0,0,255,0,255,0,255,0,0,0,255,128,17,34,51,0]);
    return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}

async function buildAtlas(dir,marker,mutation = source=>source,disposalProbe = '',budgetProbe = '') {
        await helpers(dir,['chatAnimationGif','chatAnimationWebp','ircGifs','ircEmotes']);
        const asset=await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimationAsset/ChatAnimationAsset.brs'),'utf8');
        await add(dir,'task.brs',asset.replace(/\bfs\.delete\(/g,'fixtureDelete(fs, '));
        let source=enginePngBoundary(await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimationAsset/ChatGifAtlas.brs'),'utf8'));
        source=source.replaceAll('createObject("roTimespan")','fixtureGifClock()')
            .replace('    m.gifClock = fixtureGifClock()', '    fixtureBeginConversion()\n    m.gifClock = fixtureGifClock()')
            .replace('createObject("roBitmap", { width: width, height: height, AlphaEnable: false })','fixtureBitmap({ width: width, height: height, AlphaEnable: false })')
            .replace('sub chatGifCheck()','sub chatGifCheck()\n    fixtureCheckpoint()')
            .replace('createObject("roBitmap", framePath)','fixtureDecode(framePath)')
            .replace('prefix.writeFile(path)','fixtureWrite(prefix, path)')
            .replace('bytes.appendFile(path, frame.dataStart, frame.dataLength)','fixtureAppend(bytes, path, frame.dataStart, frame.dataLength)')
            .replace('png.writeFile(renderPath)','fixturePngWrite(png, renderPath)')
            .replace('stored.readFile(renderPath, 0, 525313)','fixturePngRead(stored, renderPath, 0, 525313)')
            .replace('fs.stat(path)','fixtureAtlasStat(fs, path)')
            .replace(/\bfs\.delete\(/g,'fixtureDelete(fs, ')
            .replace('drawn = shown.drawObject(frame.x, frame.y, decoded)', 'drawn = fixtureDraw(shown, frame.x, frame.y, decoded)')
            .replace('canvas = shown', 'canvas = fixtureReplaceCanvas(canvas, shown)')
            .replace('canvas = disposed', 'canvas = fixtureReplaceCanvas(canvas, disposed)');
        for (const name of ['decoded','shown','canvas','cleared','disposed','atlas'])
            source=source.replace(new RegExp(`^([ \\t]*)${name} = invalid\\r?$`,'gm'),`$1${name} = fixtureReleaseBitmap(${name})`);
        await add(dir,'atlas.brs',mutation(source));
        await add(dir,'immutable-bitmap.brs',await fs.readFile(path.join(fixtures,'immutable-bitmap.brs')));
        await add(dir,'main.brs',(await fs.readFile(path.join(fixtures,'atlas-main.brs'),'utf8')).replaceAll('__PASS_MARKER__',marker).replace('__DISPOSAL_PROBE__',disposalProbe).replace('__BUDGET_PROBE__',budgetProbe)+
            '\nfunction fixtureDraw(destination as object, x as integer, y as integer, source as object) as boolean\n if getGlobalAA().decodeIndex = 2\n if getGlobalAA().mode = "draw-failed" then return false\n if getGlobalAA().mode = "draw-throw" then throw "scripted native draw exception"\n end if\n return destination.drawObject(x,y,source)\nend function\n');
        await add(dir,'official.gif',corpus.official);
        await add(dir,'pillow-goldens.json',await fs.readFile(path.join(fixtures,'pillow-goldens.json')));
        await add(dir,'atlas-cases.json',JSON.stringify(atlasCorpus.cases.map(({bytes,...item})=>item)));
        for(const sample of atlasCorpus.cases) await add(dir,`${sample.name}.gif`,sample.bytes);
        for(const frames of [32,33]) await add(dir,`${frames}-frames.gif`,atlasCorpus.many(frames));
        await add(dir,'rgba.png',rgbaPng());
}
test('actual GIF wrappers and immutable atlas composition match all 15 Pillow pins, hand pixels, bounds and failure cleanup', async t => {
    const count=await execute(buildAtlas);
    t.diagnostic(`${count} actual parser/wrapper/compositor/PNG-roundtrip assertions; native still decoder and GPU filter remain device boundaries`);
});

test('OS 16 regression guard rejects changing a canvas after it became a source', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>source.replace('        decoded = fixtureReleaseBitmap(decoded)', '        shown.clear(0)\n        decoded = fixtureReleaseBitmap(decoded)'))),/source bitmap mutated after draw/);
});

test('queued draw regression rejects releasing decoded input before the atlas fence', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>source.replace('        atlas.finish()\n        decoded = fixtureReleaseBitmap(decoded)', '        decoded = fixtureReleaseBitmap(decoded)\n        atlas.finish()'))),/bitmap released before Finish/);
});

test('queued draw regression rejects omitting the completion fence', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>source.replace('        atlas.finish()\n        decoded = fixtureReleaseBitmap(decoded)', '        decoded = invalid'))),/bitmap released before Finish|PNG read before Finish|unfinished draws survived conversion/);
});

test('fence count regression rejects restoring a redundant composition wait per frame', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>source.replace('        atlas.finish()\n        decoded = fixtureReleaseBitmap(decoded)', '        shown.finish()\n        atlas.finish()\n        decoded = fixtureReleaseBitmap(decoded)'))),/whole official movie uses fifteen fences for fifteen exact frames/);
});

test('failure regression rejects unwinding queued sources without the exception fence', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>source.replace('            atlas.finish()\n            throw e','            throw e'))),/native draws finished before failure\/cancel unwinds source refs/);
});

for (const mode of ['disposal-cancel','disposal-deadline','disposal-request-deadline','disposal-allocation','disposal-base-false','disposal-rect-false']) {
    test(`disposal-2 checkpoint fences queued work before unwind: ${mode}`,async t=>{
        const count=await execute((dir,marker)=>buildAtlas(dir,marker,source=>source,mode));
        t.diagnostic(`${count} actual disposal checkpoint assertions with queued draw/clock/allocation boundaries`);
    });
}

test('disposal-2 regression rejects omitting its exceptional completion fence', async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>{
        const fence='            catch e\n                atlas.finish()\n                throw e';
        assert.ok(source.includes(fence),'disposal catch/fence anchor required');
        return source.replace(fence,'            catch e\n                throw e');
    },'disposal-allocation')),/disposal-2 pending draws completed before source unwind/);
});

for (const mode of ['budget-valid-2001','budget-valid-2999','budget-exact-3000','budget-request-8000','budget-cancel']) {
    test(`GIF conversion budget policy: ${mode}`,async t=>{
        const count=await execute((dir,marker)=>buildAtlas(dir,marker,source=>source,'',mode));
        t.diagnostic(`${count} actual conversion/golden/cleanup assertions with mocked 3-second/8-second clocks; no native timing claim`);
    });
}

function mutateGuard(source,before,after) {
    assert.equal(source.split(before).length,2,'one exact production guard required');
    return source.replace(before,after);
}

test('budget regression rejects restoring the previous two-second conversion cap',async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>mutateGuard(source,
        'm.gifClock.totalMilliseconds() >= 3000','m.gifClock.totalMilliseconds() >= 2000'),'', 'budget-valid-2001')),/GIF conversion deadline/);
});

test('budget regression rejects allowing exactly 3000 ms conversion work',async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>mutateGuard(source,
        'm.gifClock.totalMilliseconds() >= 3000','m.gifClock.totalMilliseconds() > 3000'),'', 'budget-exact-3000')),/3000 ms conversion boundary rejects/);
});

test('budget regression rejects extending the shared eight-second request cap',async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>mutateGuard(source,
        'm.gifRequestClock.totalMilliseconds() >= 8000','m.gifRequestClock.totalMilliseconds() >= 8001'),'', 'budget-request-8000')),/8000 ms request boundary rejects/);
});

test('budget regression rejects ignoring cancellation in the extended conversion window',async()=>{
    await assert.rejects(execute((dir,marker)=>buildAtlas(dir,marker,source=>mutateGuard(source,
        'if m.gifCancelled then throw "GIF conversion cancelled"','if false then throw "GIF conversion cancelled"'),'', 'budget-cancel')),/cancellation remains active below 3000 ms/);
});
for (const omitDesignScaling of [false, true]) test(omitDesignScaling ? 'GIF readiness regression rejects restoring physical-pixel-only bitmap dimensions' : 'actual manager plays GIF atlas without AnimatedImage, bounds elapsed phase and preserves one global owner/worker', async t => {
    const run=()=>execute(async (dir,marker) => {
        const pkg=path.join(dir,'package');
        await add(pkg,'manifest','title=GIF Manager Contract Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add(pkg,'source/main.brs',await fs.readFile(path.join(fixtures,'manager-main.brs')));
        await add(pkg,'components/manager-scene.brs',(await fs.readFile(path.join(fixtures,'manager-scene.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        await add(pkg,'components/manager-atlas.brs',(await fs.readFile(path.join(fixtures,'manager-atlas.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        const chat=await fs.readFile(path.join(root,'components/Modules/Chat/Chat.brs'),'utf8');
        await add(pkg,'components/ChatGifBuilder.brs',['buildChatGif','chatTextNode'].map(name=>chat.match(new RegExp(`^function ${name}\\([^]*?^end function`,'m'))[0]).join('\n'));
        await add(pkg,'fonts/Archivo-Regular.otf',await fs.readFile(path.join(root,'fonts/Archivo-Regular.otf')));
        let source=await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimations.brs'),'utf8');
        if(omitDesignScaling) source=mutateGuard(source,'for each scale in [1.0, 2.0 / 3.0, 1.5]','for each scale in [1.0]');
        await add(pkg,'components/ChatAnimations.brs',source.replace('createObject("roSGNode", nodeType)','createObject("roSGNode", "AnimatedImageBoundary")')
            .replace('createObject("roSGNode", "Poster")','createObject("roSGNode", "PosterBoundary")')
            .replace('createObject("roTimespan")','fixtureElapsedClock()')
            .replace('createObject("roSGNode", "ChatAnimationAsset")','fixtureAssetTask()'));
        for (const helper of ['ircGifs','ircEmotes','taskFactory']) await add(pkg,`source/utils/${helper}.brs`,await fs.readFile(path.join(root,`source/utils/${helper}.brs`)));
        await add(pkg,'components/AnimatedImageBoundary.xml',await fs.readFile(path.join(__dirname,'fixtures/chat-animation/AnimatedImageBoundary.xml')));
        await add(pkg,'components/PosterBoundary.xml',await fs.readFile(path.join(fixtures,'PosterBoundary.xml')));
        for(const [name,base] of [['GifManagerFixture','Scene'],['GifChatBoundary','Group']])
            await add(pkg,`components/${name}.xml`,`<component name="${name}" extends="${base}"><interface><function name="runFixture" /><function name="configureContender" /><function name="probe" /><function name="disposeContender" /></interface>`+
                '<script uri="manager-scene.brs" /><script uri="manager-atlas.brs" /><script uri="ChatAnimations.brs" /><script uri="ChatGifBuilder.brs" />'+
                '<script uri="pkg:/source/utils/ircGifs.brs" /><script uri="pkg:/source/utils/ircEmotes.brs" /><script uri="pkg:/source/utils/taskFactory.brs" /></component>');
    },true);
    if(omitDesignScaling) {
        await assert.rejects(run(),/design-scaled bitmap readiness dimensions/);
        return;
    }
    const count=await run();
    t.diagnostic(`${count} actual manager assertions with scripted native states; no GIF decoding or visible motion proof`);
});
