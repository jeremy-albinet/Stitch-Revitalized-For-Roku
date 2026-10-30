'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { cosmiconfigSync } = require('cosmiconfig');

test('commitlint loads and validates YAML configuration through the upgraded CommonJS loader', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-dependency-compat-'));
    try {
        const file = path.join(dir, '.commitlintrc.yaml');
        await fs.writeFile(file, 'rules:\n  type-empty: [2, never]\n  subject-empty: [2, never]\n');
        const expected = { 'type-empty': [2, 'never'], 'subject-empty': [2, 'never'] };
        assert.deepEqual(cosmiconfigSync('commitlint').load(file).config.rules, expected);
        const { default: load } = await import('@commitlint/load');
        const { default: lint } = await import('@commitlint/lint');
        const config = await load({}, { cwd: dir, file });
        assert.deepEqual(config.rules, expected);
        assert.equal((await lint('chore: refresh dependencies', config.rules)).valid, true);
        assert.equal((await lint('missing conventional fields', config.rules)).valid, false);
    } finally {
        await fs.rm(dir, { recursive: true, force: true });
    }
});
