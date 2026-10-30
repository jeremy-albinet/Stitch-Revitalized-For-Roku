'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const locales = ['en_US', 'es_MX', 'pt_BR'];
const prefixes = ['Checking follow status', 'Updating follow status'];
const featureKeys = ['Unfollow', 'Sign in to follow', 'Check follow status', "You can't follow your own channel.",
    "Couldn't confirm follow status. Select again to check, or close this menu and try later.",
    'Not following this channel.', 'Following this channel.', 'Select again to refresh this menu.'];
const failureKey = featureKeys[4];

async function runtimeStatusKeys() {
    const source = await fs.readFile(path.join(root, 'components/Scenes/VideoPlayer/ChannelFollow.brs'), 'utf8');
    const keys = [...source.matchAll(/\btr\("((?:[^"\r\n]|"")*)"\)/g)].map(match => match[1].replaceAll('""', '"'));
    return prefixes.map(prefix => {
        const found = keys.filter(key => key.startsWith(prefix));
        assert.deepEqual(found, [`${prefix}\u2026`], 'runtime checking/updating keys use the intended U+2026 ellipsis');
        return found[0];
    });
}

function checkCatalog(bytes, locale, statusKeys) {
    const source = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    const messages = [...source.matchAll(/<message>\s*<source>([\s\S]*?)<\/source>\s*<translation(?:\s[^>]*)?>([\s\S]*?)<\/translation>\s*<\/message>/g)];
    const translations = new Map();
    for (const key of [...featureKeys, ...statusKeys]) {
        const found = messages.filter(message => message[1] === key);
        assert.equal(found.length, 1, `${locale}: exactly one translation for runtime key ${key}`);
        const value = found[0][2];
        assert.ok(value.length > 0, `${locale}: ${key} is translated`);
        assert.doesNotMatch(value, /[?\uFFFD]/, `${locale}: ${key} has no ASCII substitution or replacement characters`);
        translations.set(key, value);
    }
    for (const key of statusKeys) assert.ok(translations.get(key).endsWith('\u2026'), `${locale}: ${key} translation retains its ellipsis`);
    const words = locale === 'es_MX' ? [
        ['Sign in to follow', ['sesi\u00f3n']],
        [failureKey, ['men\u00fa', 'int\u00e9ntalo', 'despu\u00e9s']],
        ['Select again to refresh this menu.', ['men\u00fa']],
    ] : locale === 'pt_BR' ? [
        ['Check follow status', ['voc\u00ea']],
        ["You can't follow your own channel.", ['Voc\u00ea', 'n\u00e3o', 'pr\u00f3prio']],
        [failureKey, ['N\u00e3o', 'poss\u00edvel', 'voc\u00ea']],
    ] : [];
    for (const [key, expected] of words) {
        for (const word of expected) assert.ok(translations.get(key).includes(word), `${locale}: ${key} preserves accented word ${word}`);
    }
    return source;
}

for (const locale of locales) {
    test(`${locale} player follow translations match runtime keys and retain UTF-8 accents`, async () => {
        const bytes = await fs.readFile(path.join(root, `locale/${locale}/translations.ts`));
        checkCatalog(bytes, locale, await runtimeStatusKeys());
    });
}

test('follow locale contract rejects the reviewed ASCII substitutions', async () => {
    const keys = await runtimeStatusKeys();
    for (const locale of locales) {
        const bytes = await fs.readFile(path.join(root, `locale/${locale}/translations.ts`));
        const source = checkCatalog(bytes, locale, keys);
        const badKey = source.replace(`<source>${keys[0]}</source>`, `<source>${prefixes[0]}?</source>`);
        assert.notEqual(badKey, source);
        assert.throws(() => checkCatalog(Buffer.from(badKey, 'utf8'), locale, keys), /exactly one translation/);
    }
    for (const [locale, word, damaged] of [
        ['es_MX', 'Inicia sesi\u00f3n para seguir', 'Inicia sesi?n para seguir'],
        ['pt_BR', 'Voc\u00ea n\u00e3o pode seguir seu pr\u00f3prio canal.', 'Voc\u00ea n\u00e3o pode seguir seu pr?prio canal.'],
    ]) {
        const source = (await fs.readFile(path.join(root, `locale/${locale}/translations.ts`), 'utf8'));
        const badAccent = source.replace(word, damaged);
        assert.notEqual(badAccent, source);
        assert.throws(() => checkCatalog(Buffer.from(badAccent, 'utf8'), locale, keys), /ASCII substitution|preserves accented word/);
    }
});
