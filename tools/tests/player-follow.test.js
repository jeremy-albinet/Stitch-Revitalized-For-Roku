'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const sdk = 'components/Tasks/twitch-api-sdk';
const sources = [`${sdk}/playerFollow.bs`, `${sdk}/follow.bs`, `${sdk}/shared.bs`, 'source/enums/TaskControl.bs'];
const prefix = 'stitch-player-follow-';
const state = (following = false, overrides = {}) => ({ data: { currentUser: { id: '101', login: 'alice' },
    user: { id: '987654', login: 'canned', self: { follower: following ? { followedAt: '2026-10-25T12:00:00Z' } : null } }, ...overrides } });
const params = { account: 'alice', login: 'canned', id: '987654' };
const changed = { ...params, viewerId: '101', following: true };
const http = (body, status = 200) => ({ status, body: typeof body === 'string' ? body : JSON.stringify(body) });
const error = { errors: [{ message: 'failed integrity check' }] };
const ack = { data: {} }; // Deliberately opaque; only the subsequent read can confirm success.
const cases = [];
function add(name, fn, inputs, response, extra = {}) {
    cases.push({ name, fn, account: 'alice', token: 'canned-token', device: 'canned-device', params,
        inputs: inputs.map(input => input?.status ? input : http(input)), response, ...extra });
}
const flat = (following, extra = {}) => ({ account: 'alice', login: 'canned', id: '987654', viewerId: '101', following, isSelf: false, ...extra });
add('status not following', 'getPlayerFollowState', [state()], flat(false));
add('status following', 'getPlayerFollowState', [state(true)], flat(true));
add('missing broadcaster id resolves by login', 'getPlayerFollowState', [state()], flat(false), { params: { ...params, id: '' } });
add('self channel', 'getPlayerFollowState', [state(false, { user: { id: '101', login: 'canned', self: null } })], flat(false, { id: '101', isSelf: true }), { params: { ...params, id: '' } });
for (const [name, extra] of [
    ['anonymous', { account: '$default$', params: { ...params, account: '$default$' } }],
    ['token absent', { token: '' }], ['device absent', { device: '' }],
    ['wrong account owner', { params: { ...params, account: 'bob' } }],
    ['invalid login', { params: { ...params, login: 'bad/login' } }],
    ['clip slug is not broadcaster id', { params: { ...params, id: 'RecordingSlug' } }],
]) {
    add(name, 'getPlayerFollowState', [], null, extra);
    add(`${name} cannot mutate`, 'setPlayerFollowState', [], null, { params: { ...changed, ...extra.params }, ...extra });
}
for (const [name, body] of [
    ['errors only', error], ['data null', { data: null }], ['missing viewer', state(false, { currentUser: null })],
    ['token owned by another viewer', state(false, { currentUser: { id: '102', login: 'bob' } })],
    ['missing subjective state', state(false, { user: { id: '987654', login: 'canned', self: null } })],
    ['missing follower field', state(false, { user: { id: '987654', login: 'canned', self: {} } })],
    ['malformed follower edge', state(false, { user: { id: '987654', login: 'canned', self: { follower: {} } } })],
    ['different broadcaster', state(false, { user: { id: '987654', login: 'another', self: { follower: null } } })],
    ['different broadcaster id', state(false, { user: { id: '123', login: 'canned', self: { follower: null } } })],
    ['partial data with GraphQL error', { ...state(), errors: [{ message: 'failed', path: ['user', 'self'] }] }],
    ['malformed GraphQL error', { ...state(), errors: {} }], ['invalid JSON', 'bad JSON'],
]) add(name, 'getPlayerFollowState', [body], null);
add('HTTP 401 is failure even with data', 'getPlayerFollowState', [http(state(), 401)], null);
for (const switchKey of ['account', 'access_token', 'device_code']) {
    add(`${switchKey} changed during status`, 'getPlayerFollowState', [state()], null, { switchKey, switchAfter: 1 });
    add(`${switchKey} changed before write`, 'setPlayerFollowState', [state()], null, { params: changed, switchKey, switchAfter: 1 });
    add(`${switchKey} changed during write`, 'setPlayerFollowState', [state(), ack], null, { params: changed, switchKey, switchAfter: 2 });
}
add('one follow plus authenticated verification', 'setPlayerFollowState', [state(), ack, state(true)], flat(true), { params: changed });
add('one unfollow plus authenticated verification', 'setPlayerFollowState', [state(true), ack, state()], flat(false), { params: { ...changed, following: false } });
add('mutation HTTP 200 errors are failure', 'setPlayerFollowState', [state(), error], null, { params: changed });
add('mutation HTTP 403 is failure', 'setPlayerFollowState', [state(), http(ack, 403)], null, { params: changed });
add('mutation missing data is failure', 'setPlayerFollowState', [state(), {}], null, { params: changed });
add('ambiguous acknowledgement with unchanged status', 'setPlayerFollowState', [state(), ack, state()], null, { params: changed });
add('verification GraphQL failure', 'setPlayerFollowState', [state(), ack, error], null, { params: changed });
add('verification viewer changed', 'setPlayerFollowState', [state(), ack, state(true, { currentUser: { id: '102', login: 'alice' } })], null, { params: changed });
add('preflight already follows cannot toggle', 'setPlayerFollowState', [state(true)], null, { params: changed });
add('preflight viewer differs from displayed status', 'setPlayerFollowState', [state()], null, { params: { ...changed, viewerId: '102' } });
add('self follow cannot write', 'setPlayerFollowState', [state(false, { user: { id: '101', login: 'canned', self: null } })], null, { params: { ...changed, id: '101' } });
add('missing id cannot write without resolved status', 'setPlayerFollowState', [state()], null, { params: { ...changed, id: '' } });
add('missing direction cannot write', 'setPlayerFollowState', [state()], null, { params });
add('canceled before status cannot request', 'getPlayerFollowState', [], null, { cancelBefore: true });
add('cancel during preflight prevents mutation', 'setPlayerFollowState', [state()], null, { params: changed, cancelAfter: 1 });
add('cancel during mutation prevents further requests', 'setPlayerFollowState', [state(), ack], null, { params: changed, cancelAfter: 2 });
for (const fn of ['followChannel', 'unfollowChannel']) {
    add(`${fn} legacy raw success`, fn, [ack], ack);
    add(`${fn} legacy raw failure`, fn, [http(error, 503)], { response: null });
}

function run(dir, staging, files) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', staging, ...files],
            { cwd: dir, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 30000);
        const collect = data => { output += data.toString(); if (output.length > 1024 * 1024) { exceeded = true; child.kill(); } };
        child.stdout.on('data', collect); child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => { clearTimeout(timer); resolve({ output, code, timedOut, exceeded, startupError }); });
    });
}

test('actual player follow SDK boundaries gate ownership and verify each mutation with canned wire I/O', { timeout: 60000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const staging = path.join(dir, 'staging');
    const marker = `STITCH_FOLLOW_WIRE_PASS:${randomUUID()}`;
    const hashes = async () => Promise.all(sources.map(async file => createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')));
    const before = await hashes();
    try {
        const add = async (file, contents) => {
            await fs.mkdir(path.dirname(path.join(dir, file)), { recursive: true });
            await fs.writeFile(path.join(dir, file), contents);
        };
        for (const file of sources) await add(`source/${path.basename(file)}`, await fs.readFile(path.join(root, file)));
        const httpSource = await fs.readFile(path.join(root, 'source/utils/http.brs'), 'utf8');
        const bodies = [...httpSource.matchAll(/^function decodeJsonBody\b[\s\S]*?^end function/gm)];
        assert.equal(bodies.length, 1);
        await add('source/http-body.brs', bodies[0][0]);
        await add('source/main.brs', (await fs.readFile(path.join(__dirname, 'fixtures/player-follow/main.brs'), 'utf8')).replace('__PASS_MARKER__', marker));
        await add('source/cases.json', JSON.stringify(cases));
        await add('bsconfig.json', JSON.stringify({ rootDir: dir, stagingDir: staging, files: ['source/**/*'], createPackage: false,
            retainStagingDir: true, deploy: false, logLevel: 'off', showDiagnosticsInConsole: false }));
        const builder = new bsc.ProgramBuilder();
        try {
            await builder.run({ project: path.join(dir, 'bsconfig.json') });
            assert.deepEqual(builder.getDiagnostics().map(d => ({ code: d.code, message: d.message })), []);
        } finally { builder.program?.dispose(); }
        const files = (await fs.readdir(path.join(staging, 'source'))).filter(file => file.endsWith('.brs')).map(file => `source/${file}`);
        const result = await run(dir, staging, files);
        assert.equal(result.startupError, undefined, result.output);
        assert.equal(result.timedOut, false, result.output);
        assert.equal(result.exceeded, false, result.output);
        assert.equal(result.code, 0, result.output);
        const errors = result.output.split(/\r?\n/).filter(line => /BRIGHTSCRIPT:\s*ERROR:/i.test(line));
        assert.equal(errors.length, 1, result.output);
        assert.match(errors[0], /^BRIGHTSCRIPT: ERROR: ParseJSON: .*pkg:\/source\/http-body\.brs\(\d+\)$/);
        assert.doesNotMatch(result.output, /runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, result.output);
        assert.match(result.output, new RegExp(`${marker}:\\s*${cases.length} cases`), result.output);
        assert.doesNotMatch(result.output, /canned-token|canned-device/, 'credentials never enter response or diagnostics');
        const reported = result.output.split(/\r?\n/).filter(line => line.startsWith('FOLLOW_WIRE_CASE: ')).map(line => JSON.parse(line.slice(18)));
        assert.deepEqual(reported.map(item => item.name), cases.map(item => item.name));
        for (const [index, actual] of reported.entries()) {
            const expected = cases[index];
            assert.deepEqual(actual.response, expected.response, expected.name);
            assert.equal(actual.control.toLowerCase(), 'stop', expected.name);
            assert.equal(actual.requests.length, expected.inputs.length, expected.name);
            assert.equal(actual.headersValid, true, expected.name);
            const mutations = actual.requests.filter(request => request.data.operationName);
            for (const request of actual.requests) {
                assert.equal(request.method, 'POST', expected.name);
                if (!expected.fn.endsWith('Channel')) { assert.equal(request.timeout, 8000); assert.equal(request.retries, 1); }
                if (request.data.query) {
                    assert.equal(request.data.variables.login, 'canned');
                    assert.match(request.data.query, /currentUser \{ id login \} user\(login: \$login\)/);
                    assert.match(request.data.query, /self \{ follower \{ followedAt \} \}/);
                }
            }
            assert.ok(mutations.length <= 1, `${expected.name}: never retry a mutation`);
            for (const request of mutations) {
                assert.equal(request.data.variables.input.targetID, '987654');
                assert.equal(request.data.extensions.persistedQuery.version, 1);
                const follow = expected.fn === 'followChannel' || expected.params.following === true;
                assert.equal(request.data.operationName, follow ? 'FollowButton_FollowUser' : 'FollowButton_UnfollowUser');
                assert.equal(request.data.extensions.persistedQuery.sha256Hash, follow
                    ? '800e7346bdf7e5278a3c1d3f21b2b56e2639928f86815677a7126b093b2fdd08'
                    : 'f7dae976ebf41c755ae2d758546bfd176b4eeb856656098bb40e0a672ca0d880');
                assert.deepEqual(Object.keys(request.data.variables.input).sort(), follow ? ['disableNotifications', 'targetID'] : ['targetID']);
            }
        }
        assert.deepEqual(await hashes(), before);
        t.diagnostic(`${cases.length} actual compiled query/mutation boundary cases; no external I/O or authenticated Twitch claim`);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, { recursive: true, force: true });
    }
});

test('player follow persisted builders quote native mixed-case wire keys', async () => {
    const source = await fs.readFile(path.join(root, `${sdk}/playerFollow.bs`), 'utf8');
    const parsed = bsc.Parser.parse(source, { mode: bsc.ParseMode.BrighterScript });
    assert.deepEqual(parsed.diagnostics, []);
    const names = [];
    parsed.ast.walk(bsc.createVisitor({ AAMemberExpression(member) {
        const name = member.keyToken.text.replace(/^"|"$/g, '');
        if (['operationName', 'persistedQuery', 'sha256Hash', 'disableNotifications', 'targetID'].includes(name)) {
            assert.equal(member.keyToken.kind, bsc.TokenKind.StringLiteral, name);
            names.push(name);
        }
    } }), { walkMode: bsc.WalkMode.visitAllRecursive });
    assert.equal(names.filter(name => name === 'targetID').length, 2);
    for (const name of ['operationName', 'persistedQuery', 'sha256Hash', 'disableNotifications']) assert.ok(names.includes(name));
});
