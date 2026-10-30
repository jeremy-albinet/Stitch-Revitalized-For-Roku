'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/graphql-boundaries/main.brs');
const prefix = 'stitch-graphql-boundaries-';
const sdk = 'components/Tasks/twitch-api-sdk';
const production = [`${sdk}/shared.bs`, `${sdk}/home.bs`, `${sdk}/browse.bs`, `${sdk}/channel.bs`, `${sdk}/game.bs`, `${sdk}/user.bs`,
    'source/enums/TaskControl.bs', 'source/enums/ContentType.bs'];

const failure = { message: 'synthetic GraphQL operation failed' };
const at = (...segments) => ({ message: 'synthetic field failure', path: segments });
const errorsOnly = { errors: [failure] };
const dataNull = { data: null, errors: [failure] };
const broadcaster = login => ({ id: `id-${login}`, login, displayName: login.toUpperCase(), profileImageURL: 'avatar', broadcastSettings: { title: `${login} title` } });
const shelf = { node: {
    title: { fallbackLocalizedTitle: 'Live now', localizedTitleTokens: [{ node: { __typename: 'TextToken', text: 'Live now' } }] },
    content: { edges: [{ node: { __typename: 'Stream', id: 's1', createdAt: 't', viewersCount: 5, broadcaster: broadcaster('shelf'), game: null } }] },
} };
const liveFollow = { node: { id: 'u1', stream: { id: 's2', createdAt: 't', viewersCount: 9, broadcaster: broadcaster('live'), game: null } } };
const offlineFollow = { node: { id: 'u2', login: 'offline', displayName: 'Offline', profileImageURL: 'avatar', followers: { totalCount: 3 } } };
const streamEdge = cursor => ({ cursor, node: { id: `s-${cursor}`, viewersCount: 4, broadcaster: broadcaster(cursor), game: null } });
const categoryEdge = { cursor: 'g1', node: { id: 'g1', name: 'Game', displayName: 'Game', viewersCount: 10, boxArtURL: 'https://static-cdn.jtvnw.net/ttv-boxart/1-{width}x{height}.jpg' } };
const follows = (live, offline) => ({ followedLiveUsers: { edges: live }, follows: { edges: offline } });

const isInvalid = rsp => assert.equal(rsp, null);
const shelves = count => rsp => {
    assert.equal(rsp.shelves.length, count);
    if (count > 0) assert.equal(rsp.shelves[0].streams[0].streamerlogin, 'shelf');
};
const following = (live, offline, shelfCount = 0) => rsp => {
    assert.deepEqual(rsp.livefollows.map(item => item.streamerlogin), live);
    assert.deepEqual(rsp.offlinefollows.map(item => item.streamerlogin), offline);
    assert.equal(rsp.shelves.length, shelfCount);
};
const channelOffline = { streamerid: '', description: '', followercount: 0, islive: false, profileimageurl: null, videoshelves: [], livetitle: '', liveviewerscount: 0, livegamedisplayname: '' };

// attributed: the expected outcome depends on matching an error to the null
// field it explains. The negative control below disables only that matching.
const cases = [
    ['advisory network failure', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, null, isInvalid],
    ['advisory errors-only', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, errorsOnly, isInvalid],
    ['advisory missing labels', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: {} } } }, isInvalid],
    ['advisory offline', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: null } } }, isInvalid],
    ['advisory malformed labels', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: { contentClassificationLabels: {} } } } }, isInvalid],
    ['advisory failed field', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: { contentClassificationLabels: null } } }, errors: [at('user', 'stream', 'contentClassificationLabels')] }, isInvalid],
    ['advisory unflagged stream', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: { contentClassificationLabels: [] } } } }, rsp => assert.deepEqual(rsp, { labels: [] })],
    ['advisory flags without login', 'getContentAdvisoryQuery', false, { params: { login: 'fixture' } }, { data: { user: { stream: { contentClassificationLabels: [
        { id: 'MatureGame', localizedName: 'Mature-rated game' }, { id: 'ProfanityVulgarity', localizedName: 'Significant Profanity or Vulgarity' },
    ] } } } }, rsp => assert.deepEqual(rsp, { labels: ['Mature-rated game', 'Significant Profanity or Vulgarity'] })],
    ['advisory localized malformed duplicate and future labels', 'getContentAdvisoryQuery', true, { params: { login: 'fixture' } }, { data: { user: { stream: { contentClassificationLabels: [
        null, {}, { id: 3 }, { id: ' ' }, { id: 'MatureGame', localizedName: '  Jeu\nmature\r ' }, { id: 'MatureGame', localizedName: 'duplicate' }, { id: 'FutureLabel' },
    ] } } } }, rsp => assert.deepEqual(rsp, { labels: ['Jeu mature', ''] })],
    ['home errors-only', 'getHomePageQuery', false, {}, errorsOnly, isInvalid],
    ['home data null', 'getHomePageQuery', false, {}, dataNull, isInvalid],
    ['home network failure', 'getHomePageQuery', false, {}, null, isInvalid],
    ['home missing shelves root', 'getHomePageQuery', false, {}, { data: { currentUser: null } }, isInvalid],
    ['home anonymous shelves failed', 'getHomePageQuery', false, {}, { data: { currentUser: null, shelves: null }, errors: [at('shelves')] }, isInvalid, true],
    ['home anonymous genuine empty', 'getHomePageQuery', false, {}, { data: { currentUser: null, shelves: { edges: [] } } },
        rsp => assert.deepEqual(rsp, { shelves: [], errors: [], currentuser: null })],
    ['home anonymous partial shelves', 'getHomePageQuery', false, {}, { data: { currentUser: null, shelves: { edges: [shelf, { node: null }] } }, errors: [at('currentUser'), at('shelves', 'edges', 1, 'node')] },
        rsp => { shelves(1)(rsp); assert.equal(rsp.currentuser, null); assert.equal(rsp.errors.length, 2); }],
    ['home login keeps currentUser when shelves failed', 'getHomePageQuery', true, {}, { data: { currentUser: { id: '1', login: 'viewer' }, shelves: null }, errors: [at('shelves')] },
        rsp => { assert.equal(rsp.currentuser.login, 'viewer'); assert.deepEqual(rsp.shelves, []); }],
    ['home login currentUser and shelves', 'getHomePageQuery', true, {}, { data: { currentUser: { id: '1', login: 'viewer' }, shelves: { edges: [shelf] } } },
        rsp => { assert.equal(rsp.currentuser.login, 'viewer'); shelves(1)(rsp); }],
    ['home Browse rejects failed shelves despite currentUser', 'getHomePageQuery', true, { requireShelves: true },
        { data: { currentUser: { id: '1', login: 'viewer' }, shelves: null }, errors: [at('shelves')] }, isInvalid, true],
    ['home Browse rejects missing shelves despite currentUser', 'getHomePageQuery', true, { requireShelves: true },
        { data: { currentUser: { id: '1', login: 'viewer' } } }, isInvalid],
    ['home Browse keeps shelves when currentUser fails', 'getHomePageQuery', true, { requireShelves: true },
        { data: { currentUser: null, shelves: { edges: [shelf] } }, errors: [at('currentUser')] }, shelves(1)],

    ['following anonymous errors-only', 'getFollowingPageQuery', false, {}, errorsOnly, isInvalid],
    ['following anonymous data null', 'getFollowingPageQuery', false, {}, dataNull, isInvalid],
    ['following anonymous missing shelves root', 'getFollowingPageQuery', false, {}, { data: { user: null } }, isInvalid],
    ['following anonymous shelves failed', 'getFollowingPageQuery', false, {}, { data: { user: null, shelves: null }, errors: [at('shelves')] }, isInvalid, true],
    ['following anonymous genuine empty', 'getFollowingPageQuery', false, {}, { data: { user: null, shelves: { edges: [] } } }, following([], [])],
    ['following anonymous shelves without account', 'getFollowingPageQuery', false, {}, { data: { user: null, shelves: { edges: [shelf] } }, errors: [at('user')] }, following([], [], 1)],
    ['following signed-in errors-only', 'getFollowingPageQuery', true, {}, errorsOnly, isInvalid],
    ['following signed-in data null', 'getFollowingPageQuery', true, {}, dataNull, isInvalid],
    ['following signed-in user failed', 'getFollowingPageQuery', true, {}, { data: { user: null, shelves: { edges: [shelf] } }, errors: [at('user')] }, isInvalid, true],
    ['following signed-in live follows failed', 'getFollowingPageQuery', true, {}, { data: { user: { followedLiveUsers: null, follows: { edges: [offlineFollow] } } }, errors: [at('user', 'followedLiveUsers')] }, isInvalid, true],
    ['following signed-in offline follows failed', 'getFollowingPageQuery', true, {}, { data: { user: { followedLiveUsers: { edges: [liveFollow] }, follows: null } }, errors: [at('user', 'follows')] }, isInvalid, true],
    ['following signed-in genuine empty', 'getFollowingPageQuery', true, {}, { data: { user: follows([], []), shelves: null } }, following([], [])],
    ['following signed-in partial', 'getFollowingPageQuery', true, {},
        { data: { user: { ...follows([liveFollow, { node: null }], [offlineFollow]), followedGames: null }, shelves: null },
            errors: [at('user', 'followedLiveUsers', 'edges', 1, 'node'), at('user', 'followedGames'), at('shelves')] },
        following(['live'], ['offline'])],

    ['live errors-only', 'getBrowsePagePopularQuery', false, {}, errorsOnly, isInvalid],
    ['live data null', 'getBrowsePagePopularQuery', false, {}, dataNull, isInvalid],
    ['live root failed', 'getBrowsePagePopularQuery', false, {}, { data: { streams: null }, errors: [at('streams')] }, isInvalid, true],
    ['live edges failed', 'getBrowsePagePopularQuery', false, {}, { data: { streams: { edges: null, pageInfo: { hasNextPage: true } } }, errors: [at('streams', 'edges')] }, isInvalid, true],
    ['live genuine empty', 'getBrowsePagePopularQuery', false, {}, { data: { streams: { edges: [], pageInfo: { hasNextPage: false } } } },
        rsp => assert.deepEqual(rsp, { streams: [], cursor: '', hasnextpage: false })],
    ['live partial', 'getBrowsePagePopularQuery', false, {},
        { data: { streams: { edges: [streamEdge('c1'), { cursor: 'c2', node: null }], pageInfo: { hasNextPage: true } } }, errors: [at('streams', 'edges', 1, 'node'), failure] },
        rsp => { assert.deepEqual(rsp.streams.map(item => item.streamerlogin), ['c1']); assert.equal(rsp.cursor, 'c2'); assert.equal(rsp.hasnextpage, true); }],

    ['categories errors-only', 'getBrowsePageQuery', false, {}, errorsOnly, isInvalid],
    ['categories root failed', 'getBrowsePageQuery', false, {}, { data: { directoriesWithTags: null }, errors: [at('directoriesWithTags')] }, isInvalid, true],
    ['categories genuine empty', 'getBrowsePageQuery', false, {}, { data: { directoriesWithTags: { edges: [], pageInfo: { hasNextPage: false } } } },
        rsp => assert.deepEqual(rsp, { games: [], cursor: '', hasnextpage: false })],
    ['categories partial', 'getBrowsePageQuery', false, {}, { data: { directoriesWithTags: { edges: [categoryEdge], pageInfo: { hasNextPage: true } } }, errors: [at('directoriesWithTags', 'edges', 0, 'node', 'tags')] },
        rsp => { assert.deepEqual(rsp.games.map(item => item.gamename), ['Game']); assert.equal(rsp.cursor, 'g1'); assert.equal(rsp.hasnextpage, true); }],

    ['channel errors-only', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, errorsOnly, isInvalid],
    ['channel data null', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, dataNull, isInvalid],
    ['channel missing root', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: {} }, isInvalid],
    ['channel root failed', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: { channel: null }, errors: [at('channel')] }, isInvalid, true],
    ['channel null with unattributed error', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: { channel: null }, errors: [failure] }, isInvalid, true],
    ['channel not found', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: { channel: null } }, rsp => assert.deepEqual(rsp, channelOffline)],
    ['channel missing broadcaster id', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: { channel: {} } }, rsp => assert.deepEqual(rsp, channelOffline)],
    ['channel empty broadcaster id', 'getChannelHomeQuery', false, { params: { id: 'fixture' } }, { data: { channel: { id: '' } } }, rsp => assert.deepEqual(rsp, channelOffline)],
    ['channel partial', 'getChannelHomeQuery', true, { params: { id: 'fixture' } },
        { data: { channel: { description: 'About', followers: { totalCount: 12 }, profileImageUrl: 'avatar', stream: { id: 'live' }, videoShelves: null } }, errors: [at('channel', 'videoShelves')] },
        rsp => assert.deepEqual(rsp, { ...channelOffline, description: 'About', followercount: 12, islive: true, profileimageurl: 'avatar' })],
    ['channel live metadata', 'getChannelHomeQuery', false, { params: { id: 'fixture' } },
        { data: { channel: { id: '71092938', broadcastSettings: { title: 'A live stream title' }, stream: { id: 'live', viewersCount: 2468, game: { displayName: 'Fixture Game' } }, videoShelves: { edges: [] } } } },
        rsp => { assert.equal(rsp.streamerid, '71092938'); assert.equal(rsp.livetitle, 'A live stream title'); assert.equal(rsp.liveviewerscount, 2468); assert.equal(rsp.livegamedisplayname, 'Fixture Game'); }],

    ['game errors-only', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, errorsOnly, isInvalid],
    ['game data null', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, dataNull, isInvalid],
    ['game root failed', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, { data: { currentUser: null, game: null }, errors: [at('game')] }, isInvalid, true],
    ['game streams failed', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, { data: { currentUser: null, game: { name: 'Fixture', streams: null } }, errors: [at('game', 'streams')] }, isInvalid, true],
    ['game not found', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, { data: { currentUser: null, game: null } }, rsp => assert.deepEqual(rsp, { edges: [] })],
    ['game genuine empty', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } }, { data: { currentUser: null, game: { name: 'Fixture', streams: { edges: [] } } } }, rsp => assert.deepEqual(rsp, { edges: [] })],
    ['game partial', 'getGameDirectoryQuery', false, { params: { gameAlias: 'Fixture' } },
        { data: { currentUser: null, game: { name: 'Fixture', streams: { edges: [streamEdge('g'), { node: null }] } } }, errors: [at('currentUser'), at('game', 'streams', 'edges', 1, 'node')] },
        rsp => assert.deepEqual(rsp.edges.map(edge => edge.node.broadcaster.login), ['g'])],

    // Raw pass-through contracts stay unchanged: callers receive the decoded body.
    ['raw category errors-only', 'getCategoryQuery', false, { params: { id: 'fixture' } }, errorsOnly, rsp => assert.deepEqual(rsp, errorsOnly)],
    ['raw category data null', 'getCategoryQuery', false, { params: { id: 'fixture' } }, dataNull, rsp => assert.deepEqual(rsp, dataNull)],
    ['raw recommended errors-only', 'getRecommendedSections', false, {}, errorsOnly, rsp => assert.deepEqual(rsp, errorsOnly)],
    ['raw recommended network failure', 'getRecommendedSections', false, {}, null, rsp => assert.deepEqual(rsp, { response: null })],
    ['bookmarks errors-only completes with failure', 'getTwitchBookmarks', true, {}, errorsOnly, isInvalid],
    ['bookmarks data null completes with failure', 'getTwitchBookmarks', true, {}, dataNull, isInvalid],
    ['bookmarks genuine empty completes', 'getTwitchBookmarks', true, {},
        { data: { currentUser: { viewedVideos: { edges: [] } } } }, rsp => assert.deepEqual(rsp, { bookmarks: {} })],
    ['bookmarks skips incomplete histories and saves valid positions', 'getTwitchBookmarks', true, {},
        { data: { currentUser: { viewedVideos: { edges: [null, { node: { id: 'bad' } }, { node: { id: 'v1' }, history: { position: 42.8 } }] } } } },
        rsp => assert.deepEqual(rsp, { bookmarks: { v1: '42' } })],
    ['bookmarks does not save into another active profile', 'getTwitchBookmarks', true, { switchProfile: true },
        { data: { currentUser: { viewedVideos: { edges: [{ node: { id: 'v1' }, history: { position: 42 } }] } } } }, isInvalid],
    ['anonymous bookmarks completes without a request', 'getTwitchBookmarks', false, {}, null, isInvalid],
].map(([name, query, signedIn, request, body, expect, attributed = false]) => ({ name, query, signedIn, request, body, expect, attributed }));

function lowerKeys(value) {
    if (Array.isArray(value)) return value.map(lowerKeys);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key.toLowerCase(), lowerKeys(item)]));
    return value;
}

function run(zip, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
            { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 25000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => { clearTimeout(timer); resolve({ code, output, timedOut, exceeded, startupError }); });
    });
}

// Returns the names of cases whose actual response breaks its contract.
function evaluate(result, marker) {
    const detail = result.output.slice(-20000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|unhandled exception|Syntax Error/i, detail);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_GQL_PASS: ')), [`STITCH_GQL_PASS: ${marker} ${cases.length}`], detail);
    const reported = lines.filter(line => line.startsWith('STITCH_GQL_CASE: ')).map(line => lowerKeys(JSON.parse(line.slice(17))));
    assert.deepEqual(reported.map(item => item.name), cases.map(item => item.name), 'every case reports once, in order');
    const broken = [];
    reported.forEach((actual, index) => {
        const expected = cases[index];
        const sent = expected.query === 'getTwitchBookmarks' && !expected.signedIn ? 0 : 1;
        assert.equal(actual.requests, sent, `${expected.name}: expected request count`);
        assert.equal(actual.deviceid, sent ? 'fixture-device' : null, `${expected.name}: Device-ID header`);
        assert.equal(actual.authorized, sent > 0 && expected.signedIn, `${expected.name}: Authorization only when signed in`);
        assert.equal(actual.control, 'STOP', `${expected.name}: task stops`);
        try { expected.expect(actual.response); } catch { broken.push(expected.name); }
    });
    return broken;
}

async function withPackage(action) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const hashes = async () => Promise.all(production.map(async file => createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')));
    const before = await hashes();
    try {
        const packageDir = path.join(dir, 'package');
        const stagingDir = path.join(dir, 'staging');
        const add = async (file, contents) => {
            await fs.mkdir(path.dirname(path.join(packageDir, file)), { recursive: true });
            await fs.writeFile(path.join(packageDir, file), contents);
        };
        const sources = new Map();
        for (const file of production) sources.set(file, await fs.readFile(path.join(root, file), 'utf8'));
        for (const query of await fs.readdir(path.join(root, 'source/graphql'))) {
            await add(`source/graphql/${query}`, await fs.readFile(path.join(root, 'source/graphql', query)));
        }
        await add('source/cases.json', JSON.stringify(cases.map(item => ({ name: item.name, query: item.query, request: item.request,
            accessToken: item.signedIn ? 'fixture-token' : null, body: item.body === null ? null : JSON.stringify(item.body) }))));
        await add('manifest', 'title=GraphQL Boundary Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const fixtureMain = await fs.readFile(fixture, 'utf8');
        assert.equal(fixtureMain.split('__PASS_MARKER__').length, 2, 'fixture has one pass marker placeholder');
        const execute = async (mutate = source => source) => {
            for (const [file, source] of sources) await add(`source/${path.basename(file)}`, mutate(source, file));
            const marker = randomUUID();
            await add('source/main.brs', fixtureMain.replace('__PASS_MARKER__', marker));
            assert.equal(path.dirname(path.resolve(stagingDir)), path.resolve(dir), 'staging cleanup stays inside this fixture directory');
            assert.equal(path.basename(stagingDir), 'staging');
            await fs.rm(stagingDir, { recursive: true, force: true });
            await add('bsconfig.json', JSON.stringify({ rootDir: packageDir, stagingDir, files: ['source/**/*', 'manifest'],
                createPackage: false, retainStagingDir: true, deploy: false, watch: false, logLevel: 'off', showDiagnosticsInConsole: false }));
            const builder = new bsc.ProgramBuilder();
            let diagnostics;
            try {
                await builder.run({ project: path.join(packageDir, 'bsconfig.json') });
                diagnostics = builder.getDiagnostics().map(d => ({ code: d.code, message: d.message, file: d.file?.pkgPath, line: d.range?.start.line }));
            } finally { builder.program?.dispose(); }
            const zip = path.join(dir, `${marker}.zip`);
            await zipFolder(stagingDir, zip);
            return { diagnostics, marker, result: await run(zip, dir) };
        };
        await action(execute);
        assert.deepEqual(await hashes(), before, 'production SDK sources unchanged by fixture execution');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix) && path.basename(resolved).length > prefix.length);
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual compiled typed queries reject failed GraphQL roots and keep empty and partial data', { timeout: 120000 }, async t => {
    await withPackage(async execute => {
        const { diagnostics, marker, result } = await execute();
        assert.deepEqual(diagnostics, [], 'actual SDK sources compile without diagnostics');
        assert.deepEqual(evaluate(result, marker), [], result.output.slice(-20000));
        t.diagnostic(`${cases.length} canned responses through actual compiled query functions; live Twitch responses are not tested`);

        // Without error attribution, nulled roots look like valid empty results again.
        const errorAt = /(function graphQLErrorAt\(errors as dynamic, fieldPath as object\) as boolean\r?\n)/;
        const control = await execute((source, file) => {
            if (!file.endsWith('shared.bs')) return source;
            assert.match(source, errorAt);
            return source.replace(errorAt, '$1    return false\n');
        });
        assert.deepEqual(evaluate(control.result, control.marker), cases.filter(item => item.attributed).map(item => item.name));
        t.diagnostic(`error-attribution control breaks exactly ${cases.filter(item => item.attributed).length} failed-root cases`);
    });
});
