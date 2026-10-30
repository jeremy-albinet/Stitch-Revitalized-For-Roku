'use strict';

// Authored tiny GIF encoder for fixtures only: clear before every pixel keeps
// the code width fixed at 3. Expected displayed RGBA grids below are hand-authored.
const u16 = n => [n & 255, n >> 8];
const palette = [0,0,0,255,0,0,0,255,0,0,0,255];
const colors = ['00000000','ff0000ff','00ff00ff','0000ffff'];
function image(width, height, pixels, {x=0,y=0,disposal=1,transparent=true,local=false,interlaced=false,delay=20,localPalette=palette} = {}) {
    let order = pixels;
    if (interlaced) {
        order = [];
        for (const [start,step] of [[0,8],[4,8],[2,4],[1,2]])
            for (let row=start;row<height;row+=step) order.push(...pixels.slice(row*width,(row+1)*width));
    }
    const codes = order.flatMap(index => [4,index]).concat(5);
    const compressed = Buffer.alloc(Math.ceil(codes.length*3/8));
    codes.forEach((code,i) => { const bit=i*3; compressed[bit>>3]|=code<<(bit%8); if(bit%8>5) compressed[(bit>>3)+1]|=code>>(8-bit%8); });
    const blocks=[];
    for(let i=0;i<compressed.length;i+=255) blocks.push(Buffer.from([Math.min(255,compressed.length-i)]),compressed.subarray(i,i+255));
    return Buffer.concat([Buffer.from([0x21,0xf9,4,disposal*4+Number(transparent),...u16(delay/10),0,0,
        0x2c,...u16(x),...u16(y),...u16(width),...u16(height),(local?0x81:0)+(interlaced?0x40:0),...(local?localPalette:[]),2]),...blocks,Buffer.from([0])]);
}
function movie(width,height,frames,{global=true,background=0,loop=-1}={}) {
    const application=loop<0?Buffer.alloc(0):Buffer.from([0x21,0xff,11,...Buffer.from('NETSCAPE2.0'),3,1,...u16(loop),0]);
    return Buffer.concat([Buffer.from([...Buffer.from('GIF89a'),...u16(width),...u16(height),global?0x81:0,background,0,...(global?palette:[])]),application,...frames,Buffer.from([0x3b])]);
}
const grid = indices => indices.map(i=>colors[i]).join('');
const cases = [
    {name:'disposals', bytes:movie(2,2,[
        image(2,2,[1,0,0,1]), image(1,1,[2],{x:1,disposal:0,local:true,localPalette:[0,0,0,0,255,0,0,0,255,255,0,0]}),
        image(1,1,[3],{disposal:2}), image(1,1,[2],{y:1,disposal:3}), image(1,1,[3],{x:1,y:1}),
    ],{loop:0}), expected:[[1,0,0,1],[1,3,0,1],[3,3,0,1],[0,3,2,1],[0,3,0,3]].map(grid)},
    // Logical GCT background is a hand/spec golden. Pillow 12 initializes the
    // untouched first partial opaque frame to palette index 0 instead of 2.
    {name:'opaque-background', bytes:movie(2,2,[image(1,1,[1],{transparent:false,disposal:2,delay:60}),image(1,1,[3],{x:1,y:1,transparent:false,delay:60})],{background:2,loop:2}), expected:[[1,2,2,2],[2,2,2,3]].map(grid)},
    {name:'local-only', bytes:movie(2,1,[image(1,1,[1],{local:true,delay:60}),image(1,1,[3],{x:1,local:true,delay:60})],{global:false}),expected:[[1,0],[1,3]].map(grid)},
    {name:'odd-interlace',bytes:movie(3,5,[image(3,5,[1,1,1,2,2,2,3,3,3,1,1,1,2,2,2],{interlaced:true,delay:60}),image(1,1,[3],{x:1,y:3,delay:60})]),expected:[[1,1,1,2,2,2,3,3,3,1,1,1,2,2,2],[1,1,1,2,2,2,3,3,3,1,3,1,2,2,2]].map(grid)},
    {name:'restore-first', bytes:movie(2,1,[image(1,1,[1],{disposal:3,delay:60}),image(1,1,[3],{x:1,delay:60})]),expected:[[1,0],[0,3]].map(grid)},
];
const striped = Array.from({length:128*64},(_,i)=>1+((i%128)+Math.floor(i/128))%3);
cases.push({name:'scaled-nonsquare',bytes:movie(128,64,[image(128,64,striped,{delay:60}),image(128,64,striped.map(i=>i%3+1),{delay:60})]),expected:[0,1].map(frame=>grid(Array.from({length:64*32},(_,i)=>{const index=1+((i%64)*2+1+Math.floor(i/64)*2+1)%3;return frame?index%3+1:index;})))});
// At an exact texel-edge tie the engine's nearest sampler picks the lower pixel.
// Keep the center reference above distinct; Roku GPU filtering needs native QA.
cases.at(-1).engineExpected=[0,1].map(frame=>grid(Array.from({length:64*32},(_,i)=>{const index=1+((i%64)*2+Math.floor(i/64)*2)%3;return frame?index%3+1:index;})));
const many = frames => movie(64,64,Array.from({length:frames},()=>image(64,64,Array(4096).fill(1),{delay:20})));
module.exports={cases,movie,image,many,grid};
