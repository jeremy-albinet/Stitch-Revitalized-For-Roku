'use strict';

// Twitch redesign regressions. Roku draws RowList/MarkupList focus bitmaps
// under item components by default, so cards and settings rows draw their own
// focus; these tests keep that true, keep the redesign's 9-patches from
// smearing when stretched, and run the actual card/row components.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/twitch-visuals');
const timeoutMs = 25000;
const outputLimit = 1024 * 1024;

async function read(file) {
    return (await fs.readFile(path.join(root, file), 'utf8')).replace(/\r\n/g, '\n');
}

// Minimal PNG reader for 8-bit RGB/RGBA, non-interlaced images.
function decodePng(buffer) {
    assert.equal(buffer.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'PNG signature');
    let offset = 8;
    let width = 0;
    let height = 0;
    let colorType = 0;
    const data = [];
    while (offset < buffer.length) {
        const length = buffer.readUInt32BE(offset);
        const type = buffer.toString('ascii', offset + 4, offset + 8);
        const body = buffer.subarray(offset + 8, offset + 8 + length);
        if (type === 'IHDR') {
            width = body.readUInt32BE(0);
            height = body.readUInt32BE(4);
            assert.equal(body[8], 8, '8-bit channels');
            colorType = body[9];
            assert.ok(colorType === 6 || colorType === 2, 'RGB or RGBA');
            assert.equal(body[12], 0, 'non-interlaced');
        } else if (type === 'IDAT') {
            data.push(body);
        }
        offset += 12 + length;
    }
    const bpp = colorType === 6 ? 4 : 3;
    const raw = zlib.inflateSync(Buffer.concat(data));
    const stride = width * bpp;
    const pixels = [];
    let previous = Buffer.alloc(stride);
    for (let y = 0; y < height; y++) {
        const filter = raw[y * (stride + 1)];
        const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
        for (let x = 0; x < stride; x++) {
            const a = x >= bpp ? line[x - bpp] : 0;
            const b = previous[x];
            const c = x >= bpp ? previous[x - bpp] : 0;
            let add = 0;
            if (filter === 1) add = a;
            else if (filter === 2) add = b;
            else if (filter === 3) add = (a + b) >> 1;
            else if (filter === 4) {
                const p = a + b - c;
                const pa = Math.abs(p - a);
                const pb = Math.abs(p - b);
                const pc = Math.abs(p - c);
                add = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
            }
            line[x] = (line[x] + add) & 255;
        }
        const row = [];
        for (let x = 0; x < width; x++) {
            const i = x * bpp;
            row.push([line[i], line[i + 1], line[i + 2], bpp === 4 ? line[i + 3] : 255]);
        }
        pixels.push(row);
        previous = line;
    }
    return { width, height, pixels };
}

// Roku 9-patch: 1 px guide border (opaque black marks, otherwise clear), at
// least one stretch mark on top and left, and every stretched pixel inside a
// uniform core at least two pixels wide on each side, so filtering never
// blends border colours across the stretched area.
function ninePatchProblems({ width, height, pixels }) {
    const problems = [];
    const isMark = p => p[3] === 255 && p[0] === 0 && p[1] === 0 && p[2] === 0;
    const isClear = p => p[3] === 0;
    for (const [x, y] of [[0, 0], [width - 1, 0], [0, height - 1], [width - 1, height - 1]]) {
        if (!isClear(pixels[y][x])) problems.push(`corner ${x},${y} is not clear`);
    }
    const guides = [];
    for (let x = 1; x < width - 1; x++) guides.push(pixels[0][x], pixels[height - 1][x]);
    for (let y = 1; y < height - 1; y++) guides.push(pixels[y][0], pixels[y][width - 1]);
    if (guides.some(p => !isMark(p) && !isClear(p))) problems.push('guide border has a non-guide pixel');
    const stretchX = [];
    const stretchY = [];
    for (let x = 1; x < width - 1; x++) if (isMark(pixels[0][x])) stretchX.push(x);
    for (let y = 1; y < height - 1; y++) if (isMark(pixels[y][0])) stretchY.push(y);
    if (!stretchX.length || !stretchY.length) problems.push('missing stretch guides');
    // Resampled assets may differ by a unit or two; a smear differs by far more.
    const same = (a, b) => a.every((v, i) => Math.abs(v - b[i]) <= 3);
    for (const sx of stretchX) {
        for (const sy of stretchY) {
            const core = pixels[sy][sx];
            for (let dy = -2; dy <= 2; dy++) {
                for (let dx = -2; dx <= 2; dx++) {
                    const p = pixels[sy + dy]?.[sx + dx];
                    if (!p || !same(p, core)) {
                        problems.push(`stretch pixel ${sx},${sy} is not inside a uniform 5x5 core`);
                        dy = dx = 3;
                    }
                }
            }
        }
    }
    return problems;
}

function encodePng(rows) {
    const height = rows.length;
    const width = rows[0].length;
    const raw = Buffer.concat(rows.map(row => Buffer.from([0, ...row.flat()])));
    const chunk = (type, body) => {
        const length = Buffer.alloc(4);
        length.writeUInt32BE(body.length);
        const crc = Buffer.alloc(4);
        crc.writeUInt32BE(zlib.crc32(Buffer.concat([Buffer.from(type), body])) >>> 0);
        return Buffer.concat([length, Buffer.from(type), body, crc]);
    };
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0);
    header.writeUInt32BE(height, 4);
    header[8] = 8;
    header[9] = 6;
    return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
        chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

test('every redesign 9-patch has Roku guides and a uniform stretch core', async () => {
    const dir = path.join(root, 'images/twitch-redesign');
    const patches = (await fs.readdir(dir)).filter(name => name.endsWith('.9.png'));
    assert.ok(patches.length >= 4, 'redesign 9-patches present');
    for (const name of patches) {
        assert.deepEqual(ninePatchProblems(decodePng(await fs.readFile(path.join(dir, name)))), [], name);
    }
    // Negative control: a ring whose 1 px transparent core touches the border
    // (the shape that smeared across Settings rows) is rejected.
    const W = [255, 255, 255, 255];
    const C = [0, 0, 0, 0];
    const K = [0, 0, 0, 255];
    const smear = [];
    for (let y = 0; y < 9; y++) {
        const row = [];
        for (let x = 0; x < 9; x++) {
            if (y === 0) row.push(x === 4 ? K : C);
            else if (y === 8) row.push(x > 0 && x < 8 ? K : C);
            else if (x === 0) row.push(y === 4 ? K : C);
            else if (x === 8) row.push(K);
            else row.push(x === 4 && y === 4 ? C : W);
        }
        smear.push(row);
    }
    const problems = ninePatchProblems(decodePng(encodePng(smear)));
    assert.ok(problems.some(p => p.includes('uniform 5x5 core')), 'a 1 px stretch core is rejected');
});

test('cards and settings rows draw their own focus instead of under-item bitmaps', async () => {
    const transparent = 'focusBitmapUri="pkg:/images/transparent.9.png"';
    for (const page of ['Following/Following', 'Browse/Browse', 'Search/Search', 'GamePage/GamePage', 'ChannelPage/ChannelPage']) {
        const xml = await read(`components/Scenes/${page}.xml`);
        const lists = xml.match(/<RowList[\s\S]*?>/g) || [];
        assert.equal(lists.length, 1, `${page} has one RowList`);
        assert.ok(lists[0].includes('itemComponentName="VideoItem"') && lists[0].includes(transparent), `${page} cards own their focus`);
    }
    const item = await read('components/Modules/VideoItem/VideoItem.xml');
    for (const field of ['focusPercent', 'rowListHasFocus', 'itemHasFocus']) {
        assert.match(item, new RegExp(`<field id="${field}"[^>]*onChange=`), `VideoItem reacts to ${field}`);
    }
    const settings = await read('components/Scenes/Settings/settings.xml');
    assert.ok((settings.match(/<MarkupList[\s\S]*?>/) || [''])[0].includes(transparent), 'settings rows own their focus');
    const row = await read('components/Scenes/Settings/SettingsListItem.xml');
    assert.match(row, /id="focusRing"/);
    assert.match(row, /<field id="listHasFocus"[^>]*onChange=/);
});

// The redesigned screens, navigation, cards, panels and player overlays.
const redesigned = ['components/heroScene.xml', 'components/Modules/MenuBar', 'components/Modules/RecentlyWatchedBar',
    'components/Modules/VideoItem', 'components/Modules/StatusPanel', 'components/Modules/StitchVideo',
    'components/Modules/CustomVideo', 'components/Modules/Chat/Chat.xml', 'components/Scenes/Following',
    'components/Scenes/Browse', 'components/Scenes/Search', 'components/Scenes/ChannelPage', 'components/Scenes/GamePage',
    'components/Scenes/LoginPage', 'components/Scenes/Settings', 'components/Scenes/VideoPlayer/VideoPlayer.xml',
    'components/Scenes/VideoPlayer/VideoPlayer.brs', 'source/constants.brs'];

test('every pkg:/images reference in the redesigned components resolves', async () => {
    const missing = [];
    let checked = 0;
    async function visit(rel) {
        const stat = await fs.stat(path.join(root, rel));
        if (stat.isDirectory()) {
            for (const entry of await fs.readdir(path.join(root, rel))) await visit(`${rel}/${entry}`);
        } else if (/\.(xml|brs|bs)$/.test(rel)) {
            for (const [, uri] of (await read(rel)).matchAll(/pkg:\/(images\/[A-Za-z0-9_\-./]+\.(?:png|jpg))/g)) {
                checked++;
                if (!fsSync.existsSync(path.join(root, uri))) missing.push(`${rel}: ${uri}`);
            }
        }
    }
    for (const rel of redesigned) await visit(rel);
    assert.ok(checked >= 20, 'the scan found the redesigned image references');
    assert.deepEqual(missing, []);
});

function luminance(hex) {
    const channel = i => {
        const v = parseInt(hex.slice(i, i + 2), 16) / 255;
        return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4);
}

function contrast(a, b) {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
}

test('stat pills, live pills and the wordmark keep contrast on worst-case backgrounds', async () => {
    const constants = await read('source/constants.brs');
    const token = name => {
        const match = constants.match(new RegExp(`\\b${name}: "0x([0-9A-Fa-f]{8})"`));
        assert.ok(match, `token ${name}`);
        return match[1];
    };
    const overlay = token('overlay');
    const alpha = parseInt(overlay.slice(6), 16) / 255;
    // White pill text over the overlay on a white thumbnail (the worst case).
    const blended = [0, 2, 4].map(i => Math.round(parseInt(overlay.slice(i, i + 2), 16) * alpha + 255 * (1 - alpha)))
        .map(v => v.toString(16).padStart(2, '0')).join('');
    assert.ok(contrast('FFFFFF', blended) >= 4.5, `stat pill text ${contrast('FFFFFF', blended).toFixed(2)}:1`);
    assert.ok(contrast('FFFFFF', token('live').slice(0, 6)) >= 4.5, 'LIVE text on red');
    assert.ok(contrast(token('brand').slice(0, 6), token('chrome').slice(0, 6)) >= 3, 'wordmark on the header');
    assert.ok(contrast(token('focus').slice(0, 6), token('surface').slice(0, 6)) >= 3, 'settings ring on a row plate');
});

async function addFile(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, data);
}

async function copyFile(dir, file) {
    await addFile(dir, file, await fs.readFile(path.join(root, file)));
}

async function copyTree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await copyTree(dir, file);
        else await copyFile(dir, file);
    }
}

async function buildPackage(dir, marker, mutation) {
    await addFile(dir, 'manifest', 'title=Twitch Visuals Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/contentBuilder.brs',
        'source/utils/config.brs', 'components/Modules/EmojiLabel/EmojiLabel.xml',
        'components/Modules/EmojiLabel/EmojiLabel.brs', 'components/Modules/EmojiLabel/EmojiLabelUtil.brs',
        'components/Scenes/Settings/SettingsListItem.xml', 'components/Scenes/Settings/SettingsListItem.brs',
    ]) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'locale', 'components/Modules/VideoItem', 'components/Modules/CirclePoster',
        'components/Modules/TwitchContentNode']) await copyTree(dir, folder);
    if (mutation) {
        // Negative control only: the temp copy loses its focus input.
        const file = path.join(dir, 'components/Modules/VideoItem/VideoItem.brs');
        const source = await fs.readFile(file, 'utf8');
        assert.ok(source.includes(mutation[0]), 'negative-control boundary still matches VideoItem.brs');
        await fs.writeFile(file, source.replace(mutation[0], mutation[1]));
    }
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(fixtures, 'EmojiLabelRegex.brs')));
    await addFile(dir, 'components/VisualsHost.xml', await fs.readFile(path.join(fixtures, 'VisualsHost.xml')));
    await addFile(dir, 'source/main.brs', (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

async function runFixture(mutation) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-visuals-'));
    const marker = `STITCH_VISUALS_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await buildPackage(packageDir, marker, mutation);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        return { marker, result: await runPackage(zip, temp) };
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith('stitch-visuals-'), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
}

test('actual cards and settings rows draw focus, clear their text and fit pills', { timeout: 35000 }, async t => {
    const { marker, result } = await runFixture();
    const failure = result.output.slice(-16000);
    assert.equal(result.timedOut, false, `visuals fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `visuals fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `visuals fixture exited ${result.code} (${result.signal})\n${failure}`);
    assert.doesNotMatch(result.output, /STITCH_VISUALS_FAIL|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, failure);
    const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
    assert.ok(summary, `fresh visuals success marker missing\n${failure}`);
    assert.ok(Number(summary[1]) > 0, `visuals fixture executed zero assertions\n${failure}`);
    t.diagnostic(`${summary[1]} actual-component assertions; images are local, pixels are not compared`);
});

test('a card that ignores RowList focus is rejected', { timeout: 35000 }, async () => {
    const { marker, result } = await runFixture(['        amount = m.top.focusPercent\n', '        amount = 0.0\n']);
    assert.equal(result.timedOut, false, result.output.slice(-4000));
    assert.match(result.output, /STITCH_VISUALS_FAIL: full focus offsets the purple slab/, result.output.slice(-4000));
    assert.doesNotMatch(result.output, new RegExp(`${marker}:`), 'the mutated card must not report success');
});
