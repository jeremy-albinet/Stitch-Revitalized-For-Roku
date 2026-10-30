'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const walk = { walkMode: bsc.WalkMode.visitAllRecursive };
const containers = new Set(['variables', 'extensions', 'persistedQuery', 'input', 'context']);
// Persisted operations omit their query text. Preserve the existing intended
// input contract here; this does not verify Twitch's current persisted hashes.
const persistedInputs = new Map([
    ['FollowButton_FollowUser', ['disableNotifications', 'targetID']],
    ['FollowButton_UnfollowUser', ['targetID']],
    ['updateUserViewedVideo', ['userID', 'position', 'videoID', 'videoType']],
]);

function stringLiteral(expression) {
    if (!bsc.isLiteralExpression(expression) || expression.token.kind !== bsc.TokenKind.StringLiteral) return undefined;
    return expression.token.text.slice(1, -1).replaceAll('""', '"');
}

function staticString(expression) {
    const literal = stringLiteral(expression);
    if (literal !== undefined) return literal;
    if (bsc.isBinaryExpression(expression) && expression.operator.text === '+') {
        const left = staticString(expression.left);
        const right = staticString(expression.right);
        if (left !== undefined && right !== undefined) return left + right;
    }
    if (bsc.isCallExpression(expression) && bsc.isVariableExpression(expression.callee) &&
        expression.callee.name.text.toLowerCase() === 'chr' && expression.args.length === 1 &&
        bsc.isLiteralExpression(expression.args[0]) && /^\d+$/.test(expression.args[0].token.text)) {
        return String.fromCharCode(Number(expression.args[0].token.text));
    }
    return undefined;
}

function before(node, call) {
    const end = node.range.end;
    const start = call.range.start;
    return end.line < start.line || (end.line === start.line && end.character <= start.character);
}

function objectMembers(expression, call, label) {
    const additions = [];
    if (bsc.isVariableExpression(expression)) {
        const name = expression.name.text.toLowerCase();
        const containingFunction = call.findAncestor(bsc.isFunctionExpression);
        assert.ok(containingFunction, `${label}: request must belong to a function`);
        const bindings = [];
        containingFunction.walk(bsc.createVisitor({
            AssignmentStatement(node) {
                if (node.findAncestor(bsc.isFunctionExpression) === containingFunction && node.name.text.toLowerCase() === name && before(node, call)) bindings.push(node.value);
            },
            IndexedSetStatement(node) {
                if (node.findAncestor(bsc.isFunctionExpression) === containingFunction && bsc.isVariableExpression(node.obj) && node.obj.name.text.toLowerCase() === name && before(node, call)) {
                    const key = stringLiteral(node.index);
                    assert.notEqual(key, undefined, `${label}: dynamic request key needs an explicit contract`);
                    additions.push({ name: key, native: key, value: node.value });
                }
            },
            DottedSetStatement(node) {
                if (node.findAncestor(bsc.isFunctionExpression) === containingFunction && bsc.isVariableExpression(node.obj) && node.obj.name.text.toLowerCase() === name && before(node, call)) {
                    additions.push({ name: node.name.text, native: node.name.text.toLowerCase(), value: node.value });
                }
            },
        }), walk);
        assert.equal(bindings.length, 1, `${label}: expected one literal request-object binding`);
        expression = bindings[0];
    }
    assert.ok(bsc.isAALiteralExpression(expression), `${label}: request object must resolve to an AA literal`);
    assert.ok(expression.elements.every(member => bsc.isAAMemberExpression(member) || bsc.isCommentStatement(member)),
        `${label}: computed AA member needs an explicit wire-key contract`);
    return expression.elements.filter(bsc.isAAMemberExpression).map(member => {
        const quoted = member.keyToken.kind === bsc.TokenKind.StringLiteral;
        const name = quoted ? member.keyToken.text.slice(1, -1).replaceAll('""', '"') : member.keyToken.text;
        // Native Roku preserves quoted literal keys, but lowercases identifiers.
        // brs-engine preserves both, so running FormatJson in that emulator alone
        // would incorrectly accept the original broken playback requests.
        return { name, native: quoted ? name : name.toLowerCase(), value: member.value };
    }).concat(additions);
}

function inspectObject(expression, call, label, seen) {
    const members = objectMembers(expression, call, label);
    const result = new Map();
    for (const member of members) {
        assert.equal(member.native, member.name,
            `${label}.${member.name}: native Roku serializes unquoted key as ${member.native}; quote the wire key`);
        assert.ok(!result.has(member.native), `${label}: duplicate outgoing key ${member.native}`);
        seen.add(member.name);
        let nested;
        if (bsc.isAALiteralExpression(member.value) || containers.has(member.name)) {
            nested = inspectObject(member.value, call, `${label}.${member.name}`, seen);
        }
        result.set(member.native, { expression: member.value, nested });
    }
    return result;
}

function queryText(expression) {
    if (bsc.isCallExpression(expression) && bsc.isVariableExpression(expression.callee) &&
        expression.callee.name.text.toLowerCase() === 'readasciifile') {
        assert.equal(expression.args.length, 1, 'query file must have one path');
        const resource = staticString(expression.args[0]);
        assert.ok(resource && resource.startsWith('pkg:/source/graphql/'), 'query file must use the tracked GraphQL directory');
        const filename = path.resolve(root, resource.slice(5));
        assert.equal(path.dirname(filename), path.join(root, 'source/graphql'), 'query file must stay in the GraphQL directory');
        return fs.readFileSync(filename, 'utf8');
    }
    return staticString(expression);
}

function validateVariables(query, variables, label) {
    if (/^\s*\{/.test(query)) {
        assert.equal(variables.size, 0, `${label}: anonymous shorthand query cannot declare variables`);
        return;
    }
    const header = query.replace(/#[^\r\n]*/g, '').match(/^\s*(?:query|mutation|subscription)\b(?:\s+[_A-Za-z][_0-9A-Za-z]*)?\s*(?:\(([\s\S]*?)\))?\s*\{/);
    assert.ok(header, `${label}: cannot identify the GraphQL operation's variable declarations`);
    const declarations = new Map();
    for (const match of (header[1] || '').matchAll(/\$([_A-Za-z][_0-9A-Za-z]*)\s*:\s*([\[\]!_0-9A-Za-z]+)\s*(=?)/g)) {
        assert.ok(!declarations.has(match[1]), `${label}: duplicate GraphQL variable declaration`);
        declarations.set(match[1], match[2].endsWith('!') && match[3] !== '=');
    }
    for (const name of variables.keys()) {
        assert.ok(declarations.has(name), `${label}: outgoing variable ${name} does not match a case-sensitive GraphQL declaration`);
    }
    for (const [name, required] of declarations) {
        if (required) assert.ok(variables.has(name), `${label}: required GraphQL variable ${name} is missing`);
    }
}

function outgoingPayload(call) {
    if (!bsc.isVariableExpression(call.callee)) return undefined;
    const name = call.callee.name.text.toLowerCase();
    if (name === 'twitchgraphqlrequest') {
        assert.equal(call.args.length, 1, 'GraphQL wrapper must have one payload');
        return call.args[0];
    }
    if (name === 'engagementhttp' && staticString(call.args[0]) === 'https://gql.twitch.tv/gql') {
        const encoded = call.args[3];
        assert.ok(bsc.isCallExpression(encoded) && bsc.isVariableExpression(encoded.callee) && encoded.callee.name.text.toLowerCase() === 'formatjson');
        assert.equal(encoded.args.length, 1);
        return encoded.args[0];
    }
    return undefined;
}

function inspectSource(source, filename) {
    const parser = bsc.Parser.parse(source, { mode: filename.endsWith('.bs') ? bsc.ParseMode.BrighterScript : bsc.ParseMode.BrightScript });
    assert.deepEqual(parser.diagnostics, [], `${filename}: request source must parse without errors`);
    const requests = [];
    parser.ast.walk(bsc.createVisitor({
        CallExpression(call) {
            const expression = outgoingPayload(call);
            if (expression === undefined) return;
            const label = `${filename}:${call.range.start.line + 1}`;
            const seen = new Set();
            const payload = inspectObject(expression, call, label, seen);
            const allowed = new Set(['query', 'variables', 'operationName', 'extensions']);
            for (const key of payload.keys()) assert.ok(allowed.has(key), `${label}: unknown GraphQL envelope key ${key}`);
            assert.ok(payload.has('query') || payload.has('operationName'), `${label}: query or operationName is required`);
            const variables = payload.get('variables')?.nested || new Map();
            if (payload.has('query')) {
                const query = queryText(payload.get('query').expression);
                // The batch live-status request builds validated aliases directly
                // in query text and has no variables. Variable-bearing requests
                // must have a query whose actual declarations can be checked.
                if (query !== undefined) validateVariables(query, variables, label);
                else assert.equal(variables.size, 0, `${label}: variable-bearing query must be statically readable`);
            }
            if (payload.has('operationName')) {
                const operation = staticString(payload.get('operationName').expression);
                assert.ok(operation, `${label}: persisted operation must name its contract`);
                const persisted = payload.get('extensions')?.nested?.get('persistedQuery')?.nested;
                assert.ok(persisted, `${label}: persistedQuery envelope is missing or incorrectly cased`);
                assert.equal(persisted.get('version')?.expression?.token?.text, '1', `${label}: APQ version must be 1`);
                assert.match(staticString(persisted.get('sha256Hash')?.expression) || '', /^[a-f0-9]{64}$/, `${label}: APQ sha256Hash is missing or malformed`);
                if (persistedInputs.has(operation)) {
                    const input = variables.get('input')?.nested;
                    assert.ok(input, `${label}: ${operation} input is missing`);
                    assert.deepEqual([...input.keys()].sort(), [...persistedInputs.get(operation)].sort(),
                        `${label}: ${operation} input names differ from the preserved case-sensitive contract`);
                }
            }
            requests.push({ label, keys: seen });
        },
    }), walk);
    return requests;
}

function productionSources() {
    const sources = new Map();
    function collect(directory) {
        for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
            const filename = path.join(directory, entry.name);
            if (entry.isDirectory()) collect(filename);
            else if (/\.(?:brs|bs)$/.test(entry.name)) {
                const source = fs.readFileSync(filename, 'utf8');
                if (/\b(?:TwitchGraphQLRequest|engagementHttp)\s*\(/i.test(source)) sources.set(path.relative(root, filename), source);
            }
        }
    }
    collect(path.join(root, 'components'));
    collect(path.join(root, 'source'));
    return sources;
}

test('actual outgoing GraphQL requests preserve native Roku wire keys and declared variable names', t => {
    const requests = [...productionSources()].flatMap(([filename, source]) => inspectSource(source, filename));
    assert.ok(requests.length > 0, 'the production scan must find outgoing GraphQL requests');
    const keys = new Set(requests.flatMap(request => [...request.keys]));
    for (const key of ['videoId', 'playerType', 'skipPlayToken', 'operationName', 'persistedQuery', 'sha256Hash', 'disableNotifications', 'targetID', 'includeHype']) {
        assert.ok(keys.has(key), `production contract coverage must include ${key}`);
    }
    t.diagnostic(`${requests.length} actual outgoing request sites checked against native literal-key semantics; no live Twitch or decoder claim`);
});

test('removing quotes from each actual mixed-case request key is rejected without touching production', t => {
    let controls = 0;
    for (const [filename, source] of productionSources()) {
        const parser = bsc.Parser.parse(source, { mode: bsc.ParseMode.BrighterScript });
        const mutations = [];
        parser.ast.walk(bsc.createVisitor({
            CallExpression(call) {
                const expression = outgoingPayload(call);
                if (expression === undefined) return;
                expression.walk(bsc.createVisitor({ AAMemberExpression(member) {
                    if (member.keyToken.kind !== bsc.TokenKind.StringLiteral) return;
                    const name = member.keyToken.text.slice(1, -1);
                    if (name !== name.toLowerCase()) mutations.push(member.keyToken);
                } }), walk);
            },
        }), walk);
        for (const token of mutations) {
            const lines = source.split(/\r?\n/);
            const { line, character } = token.range.start;
            const end = token.range.end.character;
            lines[line] = lines[line].slice(0, character) + token.text.slice(1, -1) + lines[line].slice(end);
            assert.throws(() => inspectSource(lines.join('\n'), filename), /native Roku serializes unquoted key/, `${filename}: ${token.text}`);
            controls++;
        }
    }
    assert.ok(controls > 0, 'the negative controls must exercise actual mixed-case request keys');
    t.diagnostic(`${controls} individual missing-quote mutations of actual outgoing keys were rejected`);
});

test('case guard accepts line endings and response maps but rejects wrong wire casing and unreadable requests', () => {
    const valid = `sub makeRequest()
    response = { videoId: "internal", playerType: "internal" }
    ' TwitchGraphQLRequest({ variables: { skipPlayToken: false } })
    TwitchGraphQLRequest({ query: "query X($videoId: ID!, $skipPlayToken: Boolean!, $optional: Int) { x }", variables: { "videoId": response.videoId, "skipPlayToken": false } })
end sub`;
    assert.equal(inspectSource(valid, 'controls.brs').length, 1);
    assert.equal(inspectSource(valid.replaceAll('\n', '\r\n'), 'controls.brs').length, 1);
    assert.throws(() => inspectSource(valid.replace('"videoId":', '"videoid":'), 'controls.brs'), /does not match a case-sensitive GraphQL declaration/);
    assert.throws(() => inspectSource(valid.replace('"skipPlayToken": false', 'other: false'), 'controls.brs'), /does not match a case-sensitive GraphQL declaration/);
    assert.throws(() => inspectSource(valid.replace('"videoId": response.videoId, "skipPlayToken": false', ''), 'controls.brs'), /required GraphQL variable videoId is missing/);
    assert.throws(() => inspectSource('sub makeRequest()\nTwitchGraphQLRequest(payload)\nend sub', 'controls.brs'), /literal request-object binding/);
    assert.throws(() => inspectSource(valid.replace('end sub', ''), 'controls.brs'), /parse without errors/);
    const persisted = `sub makeRequest()
    TwitchGraphQLRequest({ "operationName": "FollowButton_UnfollowUser", variables: { input: { "targetID": "1" } }, extensions: { "persistedQuery": { version: 1, "sha256Hash": "${'a'.repeat(64)}" } } })
end sub`;
    assert.equal(inspectSource(persisted, 'controls.brs').length, 1);
    assert.throws(() => inspectSource(persisted.replace('"targetID":', '"targetid":'), 'controls.brs'), /case-sensitive contract/);
    assert.throws(() => inspectSource(persisted.replace('"operationName":', '"operationname":'), 'controls.brs'), /unknown GraphQL envelope key/);
    assert.throws(() => inspectSource(persisted.replace('"persistedQuery":', '"persistedquery":'), 'controls.brs'), /persistedQuery envelope/);
    assert.throws(() => inspectSource(persisted.replace('"sha256Hash":', '"sha256hash":'), 'controls.brs'), /APQ sha256Hash/);
    const assigned = `sub makeRequest()
    variables = { "videoId": "1" }
    variables["skipPlayToken"] = false
    TwitchGraphQLRequest({ query: "query X($videoId: ID!, $skipPlayToken: Boolean!) { x }", variables: variables })
end sub`;
    assert.equal(inspectSource(assigned, 'controls.brs').length, 1);
    assert.throws(() => inspectSource(assigned.replace('variables["skipPlayToken"]', 'variables.skipPlayToken'), 'controls.brs'), /native Roku serializes unquoted key as skipplaytoken/);
    assert.throws(() => inspectSource(assigned.replace('variables["skipPlayToken"]', 'variables[someKey]'), 'controls.brs'), /dynamic request key needs an explicit contract/);
    assert.throws(() => inspectSource(persisted.replace('variables: {', 'variables: { [someKey]: false,'), 'controls.bs'), /computed AA member needs an explicit wire-key contract/);
});
