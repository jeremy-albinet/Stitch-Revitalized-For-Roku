'use strict';
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {corpus} = require('../roku-vod-chunks/corpus');
const u32 = n => {const out=Buffer.alloc(4); out.writeUInt32BE(n); return out;};
const i32 = n => {const out=Buffer.alloc(4); out.writeInt32BE(n); return out;};
const u64 = n => {const out=Buffer.alloc(8); out.writeBigUInt64BE(BigInt(n)); return out;};
const box = (kind,...body) => {const data=Buffer.concat(body); return Buffer.concat([u32(data.length+8),Buffer.from(kind),data]);};
const full = (kind,version,flags,...parts) => box(kind,u32(version*0x1000000+flags),...parts);
const wideMfhd = index => Buffer.concat([u32(1),Buffer.from('mfhd'),u64(24),u32(0),u32(index+100)]);
const sha = data => createHash('sha256').update(data).digest('hex');
function rows(index,track,size) {
    const count=track==='video'?2:1;
    return Array.from({length:count},(_,n)=>({dts:track==='video'?62033000n+BigInt(index*2000+n*1000):2976816n+BigInt(index*96),
        duration:track==='video'?1000:96,flags:track==='video'?(n?0x1010000:0x2000000):0x2000000,
        composition:track==='video'?(index%2?-7:11):0,bytes:Buffer.alloc(size,(index*17+n+(track==='video'?118:97))&255)}));
}
function traf(id,samples,offset) {
    return box('traf',full('tfhd',0,0x20000,u32(id)),full('tfdt',1,0,u64(samples[0].dts)),
        full('trun',1,0xf01,u32(samples.length),i32(offset),...samples.flatMap(s=>[u32(s.duration),u32(s.bytes.length),u32(s.flags),i32(s.composition)])));
}
function pair(index,video,audio,padding=0) {
    const mfhd=index%31===0?wideMfhd(index):full('mfhd',0,0,u32(index+100));
    const header=box('moof',mfhd,traf(7,video,0),traf(8,audio,0));
    const v=Buffer.concat(video.map(s=>s.bytes)),a=Buffer.concat(audio.map(s=>s.bytes));
    return Buffer.concat([box('moof',mfhd,traf(7,video,header.length+8),traf(8,audio,header.length+8+v.length)),box('mdat',v,a,Buffer.alloc(padding))]);
}
function golden(index,samples) {
    const mfhd=index%31===0?wideMfhd(index):full('mfhd',0,0,u32(index+100));
    const header=box('moof',mfhd,traf(1,samples,0));
    return Buffer.concat([box('moof',mfhd,traf(1,samples,header.length+8)),box('mdat',...samples.map(s=>s.bytes))]);
}
function boxes(data,start=0,end=data.length) {
    const result=[];
    while(start<end) {
        assert.ok(start<=end-8);const short=data.readUInt32BE(start),wide=short===1;
        const size=wide?Number(data.readBigUInt64BE(start+8)):short;
        assert.ok(Number.isSafeInteger(size)&&size>=(wide?16:8)&&size<=end-start);
        result.push({kind:data.toString('ascii',start+4,start+8),start,body:start+(wide?16:8),end:start+size});start+=size;
    }
    assert.equal(start,end);return result;
}
function inspect(data,ids) {
    const result={video:[],audio:[],events:[]};let pending;
    for(const atom of boxes(data)) {
        if(atom.kind==='emsg') {result.events.push(sha(data.subarray(atom.start,atom.end)));continue;}
        if(atom.kind==='moof') {assert.equal(pending,undefined);pending=atom;continue;}
        assert.equal(atom.kind,'mdat');assert.ok(pending);
        for(const t of boxes(data,pending.body,pending.end).filter(x=>x.kind==='traf')) {
            const parts=boxes(data,t.body,t.end),tfhd=parts.find(x=>x.kind==='tfhd'),tfdt=parts.find(x=>x.kind==='tfdt');
            const track=ids[data.readUInt32BE(tfhd.body+4)];assert.ok(track);let dts=data.readBigUInt64BE(tfdt.body+4);
            for(const run of parts.filter(x=>x.kind==='trun')) {
                assert.equal(data.readUInt32BE(run.body),0x1000f01);const count=data.readUInt32BE(run.body+4);let at=run.body+12,payload=pending.start+data.readInt32BE(run.body+8);
                for(let n=0;n<count;n++) {const duration=data.readUInt32BE(at),size=data.readUInt32BE(at+4),flags=data.readUInt32BE(at+8),composition=data.readInt32BE(at+12);
                    assert.ok(payload>=atom.body&&payload+size<=atom.end);
                    result[track].push({dts:String(dts),pts:String(dts+BigInt(composition)),duration,flags,bytes:size,sha256:sha(data.subarray(payload,payload+size))});
                    payload+=size;dts+=BigInt(duration);at+=16;
                }
                assert.equal(at,run.end);
            }
        }
        pending=undefined;
    }
    assert.equal(pending,undefined);return result;
}
function build(target=9418736,count=3) {
    const pairs=[],events=[],v=[],a=[];
    for(let i=0;i<count;i++) {const video=rows(i,'video',800000),audio=rows(i,'audio',1000);pairs.push([i,video,audio]);
        if(i%20===0) {const event=full('emsg',1,0,u32(1000),u64(62033n+BigInt(i*2)),u32(1),u32(i),Buffer.from('synthetic\0event\0payload'));events.push([i,event]);}
        v.push(golden(i,video));a.push(golden(i,audio));
    }
    const base=pairs.reduce((n,p)=>n+pair(...p).length,0)+events.reduce((n,p)=>n+p[1].length,0);assert.ok(base<=target);
    const parts=[],video=[];
    for(let i=0;i<count;i++) {const event=events.find(x=>x[0]===i);if(event) {parts.push(event[1]);video.push(event[1]);}
        parts.push(pair(...pairs[i],Math.floor(target/count)+(i<target%count?1:0)-pair(...pairs[i]).length-(event?event[1].length:0)));video.push(v[i]);
    }
    const input=Buffer.concat(parts),out={video:Buffer.concat(video),audio:Buffer.concat(a)};assert.equal(input.length,target);
    const original=inspect(input,{7:'video',8:'audio'});
    for(const track of ['video','audio']) {const parsed=inspect(out[track],{1:track});assert.deepEqual(parsed[track],original[track]);assert.deepEqual(parsed.events,track==='video'?original.events:[]);}
    return {input,...out,expected:{inputBytes:input.length,inputDigest:sha(input),videoBytes:out.video.length,videoDigest:sha(out.video),audioBytes:out.audio.length,audioDigest:sha(out.audio),pairs:count,events:events.length}};
}
function inputs(seed) {
    const init=Buffer.from(corpus(seed).init.hex,'hex'),media=build();
    const oversizedPair=pair(0,rows(0,'video',2097152),rows(0,'audio',1));assert.ok(oversizedPair.length>4194304&&oversizedPair.length<12582912);
    const maxWhole=build(12582912),overWhole=build(12582913,4);
    return {'init.bin':init,'media.bin':media.input,'maximum.bin':maxWhole.input,'oversize.bin':overWhole.input,'one-pair.bin':oversizedPair,'expected.json':JSON.stringify(media.expected)};
}
module.exports={inputs,sha};
