# Dependency and diagnostics policy

The Roku channel contains BrightScript, assets, and settings; it does not contain the npm toolchain. All JavaScript dependencies are development tools. The Python demux service is a separate runtime and is audited without exceptions using the locked runtime dependency export and `pip-audit` in CI.

Run `npm run audit` to check the npm graph. The check prints raw audit totals and fails on every unapproved high or critical finding. It does not claim that approved findings have been patched.

## Build dependencies

The temporary development-only `braces` exception was removed after [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm) was withdrawn on October 23, 2026. `security/npm-audit-policy.json` currently grants no exceptions.

The simulator's terminal-image/Jimp dependency chain uses patched Zod 4.6.7 or later through a scoped `brs-node` override for [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5). A regression exercises the actual terminal renderer and image resize path to verify compatibility with that override.

The simulator's source-map chain uses patched `decode-uri-component` 0.5.1 for [GHSA-vcc3-ghjq-m6fr](https://github.com/advisories/GHSA-vcc3-ghjq-m6fr). Its old CommonJS caller needs the decoder's ESM default export on Node 24. `npm ci` runs a small compatibility adapter that verifies the exact caller version/body and decoder version before changing that import; unexpected versions or source fail installation. The upstream decoder remains untouched. Actual synchronous/asynchronous source-map reads, Unicode/percent/plus paths, the broken original import and bounded malformed input are covered by regressions. Use normal `npm ci`; `--ignore-scripts` skips this required compatibility step.

## Credentials and diagnostics

Keep `DEV.md`, local compiler configuration, device credentials, `.env` files, and the optional `env` package configuration out of version control. Signed playback URLs and OAuth tokens must never appear in diagnostic logs or committed fixtures. Secure chat may use OAuth; the anonymous plaintext fallback must never transmit it.

Remote diagnostics are off by default and require a fresh explicit settings opt-in plus a maintainer-configured HTTPS endpoint. The old fork-specific endpoint/key is removed. Optional diagnostics use a session identifier rather than a persistent device identifier, and exception payloads omit raw messages. Configure the optional, ignored `env` file only when maintaining your own diagnostics service:

```json
{
  "analytics": {
    "captureUrl": "https://YOUR_SERVICE/capture/",
    "apiKey": "YOUR_WRITE_KEY"
  }
}
```

The configured file is included in a built channel if present. Treat its contents as client-visible; never place a server-side secret in it.
