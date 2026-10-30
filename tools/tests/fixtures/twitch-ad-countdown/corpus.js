'use strict';

// Only the observed field shape is mirrored. All dates/IDs/ignored values below
// are synthetic, with no captured media, source URLs, tracking tokens or IDs.
const start = Date.parse('2030-01-02T03:04:05.000Z');
function line(offsetMs, duration, count, position, extra = '') {
    return '#EXT-X-DATERANGE:ID="fixture-only",CLASS="twitch-stitched-ad",' +
        `START-DATE="${new Date(start + offsetMs).toISOString()}",DURATION=${duration}` +
        (count === undefined ? '' : `,X-TV-TWITCH-AD-POD-LENGTH=${count}`) +
        (position === undefined ? '' : `,X-TV-TWITCH-AD-POD-POSITION=${position}`) + extra;
}
const single = line(0, '30.239', 4, 0, ',X-TV-TWITCH-AD-RADS-TOKEN="synthetic-discard",X-TV-TWITCH-AD-URL="synthetic-discard"');
const pod = [single, line(30238, '15.224', 4, 1), line(45462, '15.431', 4, 2), line(60893, '15.217', 4, 3)];
const unknown = single.replace('twitch-stitched-ad', 'unrelated-source-metadata');
const plain = line(0, '30.239');
const before = single.replace('2030-01-02T03:04:05.000Z', '2030-01-02T03:04:04.000Z');
const bad = [
    ['zero duration', single.replace('DURATION=30.239', 'DURATION=0')],
    ['negative duration', single.replace('DURATION=30.239', 'DURATION=-30')],
    ['exponent duration', single.replace('DURATION=30.239', 'DURATION=3e1')],
    ['too long duration', single.replace('DURATION=30.239', 'DURATION=3600.000001')],
    ['overprecision duration', single.replace('DURATION=30.239', 'DURATION=30.2390001')],
    ['missing duration', single.replace(',DURATION=30.239', '')],
    ['missing date', single.replace(/,START-DATE="[^"]+"/, '')],
    ['invalid calendar', single.replace('2030-01-02', '2030-02-29')],
    ['invalid seconds', single.replace('03:04:05', '03:04:60')],
    ['unknown timezone', single.replace('05.000Z', '05.000+01:00')],
    ['huge pod count', single.replace('POD-LENGTH=4', 'POD-LENGTH=33')],
    ['ordinal equals count', single.replace('POD-POSITION=0', 'POD-POSITION=4')],
    ['fractional ordinal', single.replace('POD-POSITION=0', 'POD-POSITION=0.5')],
    ['duplicate known key', single + ',DURATION=30.239'],
    ['duplicate ignored key', single + ',ID="fixture-only"'],
    ['trailing comma', single + ','],
    ['unterminated quote', single + ',X-IGNORE="missing-end'],
    ['quoted comma escape failure', single + ',X-IGNORE="a"tail'],
    ['non-ASCII value', single + ',X-IGNORE="\u0080"'],
    ['empty value', single + ',X-IGNORE='],
    ['oversize line', single + ',X-IGNORE="' + 'x'.repeat(32768) + '"']
].map(([name, text]) => ({name, text}));
const overlapBad = [
    ['excess overlap', [plain, line(30237, '15')]],
    ['unknown pod overlap', [plain, line(30238, '15')]],
    ['different count overlap', [single, line(30238, '15', 5, 1)]],
    ['skipped ordinal overlap', [single, line(30238, '15', 4, 2)]],
    ['reversed ordinal overlap', [single, line(30238, '15', 4, 0)]],
    ['conflicting duplicate duration', [single, single.replace('DURATION=30.239', 'DURATION=30.240')]],
    ['conflicting duplicate count', [single, single.replace('POD-LENGTH=4', 'POD-LENGTH=5')]]
].map(([name, lines]) => ({name, text: lines.join('\n')}));
const limit = single + Array.from({length: 120}, (_, i) => `,X-FIXTURE-${i}="discard"`).join('');
module.exports = {startUs: start * 1000, single, pod: pod.join('\n'), reversedPod: pod.toReversed().join('\r\n'), unknown, plain, before,
    missingCount: single.replace(',X-TV-TWITCH-AD-POD-LENGTH=4', ''), missingPosition: single.replace(',X-TV-TWITCH-AD-POD-POSITION=0', ''),
    incompletePod: pod.slice(0, 3).map(x => x.replace('POD-LENGTH=4', 'POD-LENGTH=5')).join('\n'),
    bad, overlapBad, attributeLimit: limit, attributeOver: limit + ',X-FIXTURE-OVER="discard"',
    cuesLimit: Array.from({length: 32}, (_, i) => line(i * 31000, '30')).join('\n'),
    cuesOver: Array.from({length: 33}, (_, i) => line(i * 31000, '30')).join('\n'),
    rangesLimit: Array(128).fill(unknown).join('\n'), rangesOver: Array(129).fill(unknown).join('\n'),
    golden: pod.map((_, i) => ({startUs: (start + [0,30238,45462,60893][i]) * 1000,
        endUs: (start + [0,30238,45462,60893][i] + [30239,15224,15431,15217][i]) * 1000,
        durationUs: [30239,15224,15431,15217][i] * 1000, podCount: 4, podPosition: i}))};
