"use strict";
// SDK worker entry: importing the SDK registers its normal payload handler.
// Install synchronously before that queued payload can run; no engine files change.
const assert = require('node:assert/strict');
const {install} = require('./engine');
const marker = process.env.STITCH_VOD_LARGE_WORKER_MARKER;
assert.match(marker,/^[0-9a-f-]{36}$/);
install(() => process.stdout.write('VOD_LARGE_WORKER_INDEX_READ '+marker+'\n'));
process.stdout.write('VOD_LARGE_WORKER_READY '+marker+'\n');
