#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const out = path.join(__dirname, '..', 'out');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'test-run-id'), randomUUID());
