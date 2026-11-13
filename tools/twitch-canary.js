#!/usr/bin/env node
// Twitch canary: runs the app's own GraphQL documents and the live/VOD playback path
// against Twitch, anonymously, and exits non-zero if any of them stopped working.
// Usage: node tools/twitch-canary.js
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..');
const CLIENT_ID = 'ue6666qo983tsx6so1t0vnawi233wa'; // shared.bs
const FALLBACK_LOGIN = 'twitch'; // only used where the query does not need a live channel
const FALLBACK_GAME = 'Just Chatting';
const RETRY_DELAY_MS = 5000;

// The app sends the device_code from the OAuth device flow (getRendezvouzToken). For anonymous
// reads Twitch accepted a random id, a one-letter id and no header at all (checked 2026-11-12).
const DEVICE_ID = crypto.randomBytes(16).toString('hex');

const readGql = (file) => fs.readFileSync(path.join(ROOT, 'source/graphql', file), 'utf8');

// The playback path ships inline query strings in GetTwitchContent.brs, not the .gql files.
// Extract them at run time so the canary tests what the player actually sends.
function readInlineQuery(operation) {
    const brs = fs.readFileSync(path.join(ROOT, 'components/Tasks/GetTwitchContent/GetTwitchContent.brs'), 'utf8');
    const match = brs.match(new RegExp(`query: "(query ${operation}\\b[^"]*)"`));
    if (!match) throw new Error(`inline ${operation} not found in GetTwitchContent.brs`);
    return match[1];
}

const get = (obj, dotted) => dotted.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);

function need(obj, dotted, type = 'any') {
    const value = get(obj, dotted);
    const ok = type === 'array' ? Array.isArray(value) : value != null;
    if (!ok) throw new Error(`missing ${dotted}`);
    return value;
}

async function gql(query, variables) {
    const res = await fetch('https://gql.twitch.tv/gql', {
        method: 'POST',
        headers: {
            'Accept': '*/*',
            'Content-Type': 'application/json',
            'Client-Id': CLIENT_ID,
            'Device-ID': DEVICE_ID,
            'Origin': 'https://android.tv.twitch.tv',
            'Referer': 'https://android.tv.twitch.tv/',
            'Accept-Language': 'en-US',
        },
        body: JSON.stringify({ query, variables }),
        signal: AbortSignal.timeout(20000),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (body.errors && body.errors.length) {
        throw new Error(`errors: ${body.errors.map((e) => e.message).join('; ').slice(0, 300)}`);
    }
    return body;
}

async function usher(url) {
    const res = await fetch(url, {
        headers: {
            // Same headers as GetTwitchContent.brs
            'Accept': '*/*',
            'Origin': 'https://android.tv.twitch.tv',
            'Referer': 'https://android.tv.twitch.tv/',
            'User-Agent': 'Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36',
            'Client-ID': 'kimne78kx3ncx6brgo4mv6wki5h1ko',
        },
        signal: AbortSignal.timeout(20000),
    });
    const text = await res.text();
    if (res.status !== 200) throw new Error(`usher HTTP ${res.status}: ${text.slice(0, 200)}`);
    if (!text.startsWith('#EXTM3U')) throw new Error(`usher body does not start with #EXTM3U: ${text.slice(0, 80)}`);
    return text;
}

class Skip extends Error {}

// Inputs derived from earlier results, so nothing depends on a hard-coded channel being live.
const ctx = { liveLogin: null, game: null, vodId: null };

function noteStreams(nodes) {
    const stream = nodes.find((n) => n && n.__typename === 'Stream' && get(n, 'broadcaster.login'));
    if (stream && !ctx.liveLogin) ctx.liveLogin = stream.broadcaster.login;
    if (stream && stream.game && !ctx.game) ctx.game = stream.game.name;
}

const requireLive = () => {
    if (!ctx.liveLogin) throw new Error('no live channel found in Homepage or BrowseLiveChannels results');
    return ctx.liveLogin;
};

const checks = [
    ['Homepage_Query', async () => {
        const rsp = await gql(readGql('Homepage_Query.gql'), { itemsPerRow: 20, limit: 8, platform: 'web_tv', requestID: crypto.randomUUID() });
        const shelves = need(rsp, 'data.shelves.edges', 'array');
        noteStreams(shelves.flatMap((s) => (get(s, 'node.content.edges') || []).map((e) => e.node)));
        return `${shelves.length} shelves`;
    }],
    ['BrowseLiveChannels_Query', async () => {
        const rsp = await gql(readGql('BrowseLiveChannels_Query.gql'), { limit: 30, sort: 'VIEWER_COUNT' });
        const edges = need(rsp, 'data.streams.edges', 'array');
        noteStreams(edges.map((e) => e.node));
        return `${edges.length} streams`;
    }],
    ['BrowseCategories_Query', async () => {
        const rsp = await gql(readGql('BrowseCategories_Query.gql'), { first: 80 });
        const edges = need(rsp, 'data.games.edges', 'array');
        if (!ctx.game) ctx.game = get(edges, '0.node.name');
        return `${edges.length} categories`;
    }],
    ['GamesDirectory_Query', async () => {
        const rsp = await gql(readGql('GamesDirectory_Query.gql'), { first: 80 });
        return `${need(rsp, 'data.games.edges', 'array').length} games`;
    }],
    ['GameDirectory_Query_Directory', async () => {
        const game = ctx.game || FALLBACK_GAME;
        const rsp = await gql(readGql('GameDirectory_Query_Directory.gql'), { gameAlias: game, channelsCount: 40 });
        return `${game}: ${need(rsp, 'data.game.streams.edges', 'array').length} streams`;
    }],
    ['GameDirectory_Query_Category', async () => {
        const game = ctx.game || FALLBACK_GAME;
        const rsp = await gql(readGql('GameDirectory_Query_Category.gql'), { gameAlias: game, channelsCount: 40 });
        need(rsp, 'data.game');
        return game;
    }],
    ['Search_Query', async () => {
        const term = ctx.liveLogin || FALLBACK_LOGIN;
        const rsp = await gql(readGql('Search_Query.gql'), { userQuery: term, platform: 'web_tv', noQuery: false });
        need(rsp, 'data.searchFor');
        return `"${term}"`;
    }],
    ['ChannelHome_Query', async () => {
        // Also the VOD source: the live channel's shelves first, then the stable fallback channel.
        const logins = [...new Set([ctx.liveLogin || FALLBACK_LOGIN, FALLBACK_LOGIN])];
        for (const login of logins) {
            const rsp = await gql(readGql('ChannelHome_Query.gql'), { login, platform: 'web_tv', playerType: 'quasar', skipPlayToken: false });
            const channel = need(rsp, 'data.channel');
            if (!('videoShelves' in channel)) throw new Error('missing data.channel.videoShelves');
            const items = (get(channel, 'videoShelves.edges') || []).flatMap((e) => get(e, 'node.items') || []);
            const vod = items.find((i) => i && i.__typename === 'Video');
            if (vod) {
                ctx.vodId = vod.id;
                break;
            }
        }
        return `${logins[0]}, vod=${ctx.vodId || 'none'}`;
    }],
    ['ChannelInterstitial_Query', async () => {
        const login = ctx.liveLogin || FALLBACK_LOGIN;
        const rsp = await gql(readGql('ChannelInterstitial_Query.gql'), { login, platform: 'web_tv', playerType: 'pulsar', skipPlayToken: true });
        need(rsp, 'data.channel');
        return login;
    }],
    ['StreamPlayer_Query', async () => {
        const login = requireLive();
        const rsp = await gql(readGql('StreamPlayer_Query.gql'), { login, platform: 'web_tv', playerType: 'pulsar', skipPlayToken: false });
        need(rsp, 'data.user.stream.playbackAccessToken.value');
        return login;
    }],
    ['VodPlayerWrapper_Query', async () => {
        if (!ctx.vodId) throw new Skip('no VOD id found on the channel pages');
        const rsp = await gql(readGql('VodPlayerWrapper_Query.gql'), { videoId: ctx.vodId, platform: 'web_tv', playerType: 'pulsar', skipPlayToken: false });
        need(rsp, 'data.video.playbackAccessToken.value');
        return ctx.vodId;
    }],
    ['FollowingPage_Query', async () => {
        throw new Skip('needs auth (reads the logged-in user\'s follows)');
    }],
    ['playback: live (GetTwitchContent)', async () => {
        const login = requireLive();
        const rsp = await gql(readInlineQuery('StreamPlayer_Query'), { login, platform: 'web_tv', playerType: 'roku', skipPlayToken: false });
        const token = need(rsp, 'data.user.stream.playbackAccessToken');
        const params = new URLSearchParams({
            allow_source: 'true', fast_bread: 'true', playlist_include_framerate: 'true', player_backend: 'mediaplayer',
            reassignments_supported: 'true', supported_codecs: 'avc1,mp4a', transcode_mode: 'cbr_v1',
            p: crypto.randomUUID().replace(/-/g, ''), token: token.value, sig: token.signature,
        });
        await usher(`https://usher.ttvnw.net/api/channel/hls/${rsp.data.user.login}.m3u8?${params}`);
        return `${login}: #EXTM3U`;
    }],
    ['playback: vod (GetTwitchContent)', async () => {
        if (!ctx.vodId) throw new Skip('no VOD id found on the channel pages');
        const rsp = await gql(readInlineQuery('VodPlayerWrapper_Query'), { videoId: ctx.vodId, platform: 'web_tv', playerType: 'pulsar', skipPlayToken: false });
        const token = need(rsp, 'data.video.playbackAccessToken');
        const params = new URLSearchParams({
            playlist_include_framerate: 'true', allow_source: 'true', player_type: 'pulsar', player_backend: 'mediaplayer',
            reassignments_supported: 'true', nauth: token.value, nauthsig: token.signature,
        });
        await usher(`https://usher.ttvnw.net/vod/${rsp.data.video.id}.m3u8?${params}`);
        return `${ctx.vodId}: #EXTM3U`;
    }],
];

async function main() {
    let failed = 0;
    for (const [name, run] of checks) {
        let line;
        for (let attempt = 1; attempt <= 2; attempt++) {
            try {
                line = `PASS  ${name}: ${await run()}`;
                break;
            } catch (err) {
                if (err instanceof Skip) {
                    line = `SKIP  ${name}: skipped: ${err.message}`;
                    break;
                }
                line = `FAIL  ${name}: ${err.message}`;
                if (attempt === 1) await new Promise((r) => setTimeout(r, RETRY_DELAY_MS));
            }
        }
        if (line.startsWith('FAIL')) failed++;
        console.log(line);
    }
    console.log(`\n${failed} failed of ${checks.length} checks`);
    process.exit(failed ? 1 : 0);
}

main();
