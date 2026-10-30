'use strict';

module.exports = corpus => {
    const existingLines = corpus.single.split('\n').length - 1;
    const unterminatedLines = limit => corpus.single.replace('#EXT-X-ENDLIST\n',
        '#comment\n'.repeat(limit - existingLines) + '#EXT-X-ENDLIST');
    return {
        good: [
            ['blank lines between URI and duration', corpus.small.replaceAll(',\n', ',\n\n\n')],
            ['CRLF blank lines preserve pending duration', corpus.small.replaceAll(',\n', ',\n\n').replaceAll('\n', '\r\n')],
            ['final bare CR without LF', corpus.small.slice(0, -1) + '\r'],
            ['trailing CR-only blank line', corpus.small + '\r']
        ],
        bad: [
            { name: 'double trailing CR in URI', text: corpus.single.replace('0.m4s\n', '0.m4s\r\r\n') },
            { name: 'embedded CR in URI', text: corpus.single.replace('0.m4s', '0.\rm4s') },
            { name: 'double trailing CR in ENDLIST', text: corpus.single.replace('#EXT-X-ENDLIST\n', '#EXT-X-ENDLIST\r\r\n') }
        ],
        unterminatedMax: unterminatedLines(16448),
        unterminatedOver: unterminatedLines(16449),
        flood: '\n'.repeat(262144)
    };
};
