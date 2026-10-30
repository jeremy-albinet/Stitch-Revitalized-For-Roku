'use strict';

// brs-engine exports lossless indexed PNG, whereas Roku's documented GetPng
// returns RGBA8. Adapt that format boundary only; production RGBA admission is
// tested separately with CRC-checked, host-encoded RGBA PNG and mutations.
function enginePngBoundary(source) {
    const admission=source.match(/^function chatGifPng\([^]*?^end function/m)[0];
    return source.replace('if not chatGifPng(png,', 'if not fixtureNativePng(png,') + '\n' +
        admission.replace('function chatGifPng(', 'function fixtureNativePng(')
            .replace('    if type(bytes)', '    if getGlobalAA().mode = "png-admission" then return false\n    if type(bytes)')
            .replace('bytes[24] <> 8 or bytes[25] <> 6', '(bytes[24] <> 1 and bytes[24] <> 2 and bytes[24] <> 4 and bytes[24] <> 8) or (bytes[25] <> 3 and bytes[25] <> 6)');
}
module.exports={enginePngBoundary};
