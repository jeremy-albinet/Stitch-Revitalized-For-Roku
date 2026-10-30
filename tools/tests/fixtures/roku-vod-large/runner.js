'use strict';
// Large-fixture runner: same child deadline/output/current-marker guards;
// only explicit child entry opts into the separately controlled read instrumentation.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const bsc = require('brighterscript');
const root = path.resolve(__dirname, '../../../..');

function replaceFunction(source, name, replacement) {
    const pattern = new RegExp(`^(?:function|sub) ${name}\\([^]*?^end (?:function|sub)`, 'm');
    assert.equal((source.match(new RegExp(`^(?:function|sub) ${name}\\(`, 'gm')) || []).length, 1, `one exact ${name} boundary`);
    return source.replace(pattern, replacement);
}
function child(args, cwd) {
    return new Promise(resolve => {
        const processChild = spawn(process.execPath, args, {cwd, windowsHide: true, stdio: ['ignore','pipe','pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => {timedOut = true; processChild.kill();}, 40000);
        const collect = data => {bytes += data.length; if (bytes > 1048576) {exceeded = true; processChild.kill(); return;} output += data.toString();};
        processChild.stdout.on('data', collect); processChild.stderr.on('data', collect);
        processChild.once('error', error => {startupError = error.name;});
        processChild.once('close', code => {clearTimeout(timer); resolve({code, output, bytes, timedOut, exceeded, startupError});});
    });
}
function workerProof(result, allowFailedTerminal = false) {
    if (result.workerAdapter) {
        const lines=result.output.split(/\r?\n/);
        const ready=lines.filter(line=>line.startsWith('VOD_LARGE_WORKER_READY '));
        const reads=lines.filter(line=>line.startsWith('VOD_LARGE_WORKER_INDEX_READ '));
        assert.deepEqual(ready,['VOD_LARGE_WORKER_READY '+result.marker],'one fresh actual worker-ready marker');
        assert.deepEqual(reads,['VOD_LARGE_WORKER_INDEX_READ '+result.marker],'one fresh actual worker numeric-read marker');
        assert.ok(lines.indexOf(ready[0]) < lines.indexOf(reads[0]),'worker install precedes actual numeric read');
        const summaries=lines.map((line,index)=>(line.includes('_PASS:') || (allowFailedTerminal && line.includes('_FAIL:')))?index:-1).filter(index=>index>=0);
        assert.ok(summaries.length>0 && summaries.every(index=>index>lines.indexOf(reads[0])),'actual numeric read precedes summary');
    }
}
function execution(result) {
    const detail = result.output.slice(-7000);
    assert.equal(result.startupError, undefined, detail); assert.equal(result.timedOut, false, `finite child deadline\n${detail}`);
    assert.equal(result.exceeded, false, `bounded child output\n${detail}`); assert.equal(result.code, 0, detail);
    workerProof(result);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
}
function positive(result, prefix, marker) {
    execution(result); assert.doesNotMatch(result.output, new RegExp(`${prefix}_FAIL:`), result.output);
    const lines = result.output.split(/\r?\n/).filter(line => line.startsWith(`${prefix}_PASS: `));
    assert.equal(lines.length, 1, result.output); assert.ok(lines[0].startsWith(`${prefix}_PASS: ${marker} `), 'fresh actual marker');
    const counts = JSON.parse(lines[0].slice(`${prefix}_PASS: ${marker} `.length));
    assert.deepEqual(Object.keys(counts).sort(), ['assertions','failures']);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0); assert.equal(counts.failures, 0, result.output);
    return counts.assertions;
}
async function packageFixture(names, harness, transform, extras = {}, ordinaryEngine = false) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-vod-backend-'));
    const marker = randomUUID();
    const sources = new Map();
    try {
        for (const name of names) {
            const relative = name.includes('/') ? name : `source/utils/${name}.brs`;
            let source = await fs.readFile(path.join(root, relative), 'utf8'); sources.set(name, source);
            assert.deepEqual(bsc.Parser.parse(source, {mode:bsc.ParseMode.BrightScript}).diagnostics, [], `actual ${name} syntax`);
            if (transform) source = transform(name, source);
            assert.deepEqual(bsc.Parser.parse(source, {mode:bsc.ParseMode.BrightScript}).diagnostics, [], `bounded adapted ${name} syntax`);
            await fs.writeFile(path.join(dir, path.basename(relative)), source);
        }
        assert.deepEqual(bsc.Parser.parse(harness, {mode:bsc.ParseMode.BrightScript}).diagnostics, [], 'actual harness syntax');
        await fs.writeFile(path.join(dir,'main.brs'), harness.replaceAll('__MARKER__', marker));
        await fs.writeFile(path.join(dir,'manifest'), 'title=Finite VOD Backend Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        for (const [name, value] of Object.entries(extras)) await fs.writeFile(path.join(dir,name), value);
        const entry = ordinaryEngine ? path.join(root,'node_modules/brs-node/bin/brs.cli.js') : path.join(__dirname,'engine.js');
        const args = [entry, '--no-sg', '--root',dir, ...(ordinaryEngine ? [] : ['--worker-marker',marker]),
            ...names.map(name => path.basename(name.includes('/') ? name : name + '.brs')), 'main.brs'];
        return {...await child(args,dir), marker, workerAdapter:!ordinaryEngine};
    } finally {
        assert.equal(path.dirname(path.resolve(dir)),path.resolve(os.tmpdir()),'recursive cleanup stays inside the named temporary directory');
        assert.ok(path.basename(dir).startsWith('stitch-vod-backend-'),'cleanup target is our unique fixture directory');
        await fs.rm(dir,{recursive:true,force:true});
    }
}
const master = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8042999,CODECS="avc1.4D402A,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=60.000\nhttps://dsynthetic.cloudfront.net/archive/index.m3u8?fixture=synthetic\n';
const playlist = '#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MEDIA-SEQUENCE:95\n#EXT-X-MAP:URI="init.mp4?fixture=synthetic"\n' +
    Array.from({length:24},(_,i)=>`#EXTINF:10.000000,\n${i}.m4s?fixture=synthetic-${i}\n`).join('') + '#EXT-X-ENDLIST\n';
module.exports = {root, fs, path, assert, replaceFunction, execution, workerProof, positive, packageFixture, master, playlist};
