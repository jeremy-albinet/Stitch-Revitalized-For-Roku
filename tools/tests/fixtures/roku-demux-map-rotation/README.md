# Same-initialization MAP rotation regression

Run `node --test tools/tests/roku-demux-map-rotation.test.js`.

The runner executes actual production Bulk/Core, Fetch cleanup/Tick/feed, init inspector/gate, strict Protocol diagnostics and the Server alias-count helper. It reuses only the released synthetic init and four small media inputs/full Python output goldens from `../roku-demux-core/corpus.json`, verifying that corpus's provenance and binary SHA256 first. No real media, source credentials or giant duplicate corpus is included.

Sixteen cases execute532 assertions. They cover deferred same-epoch alias acceptance, old advertised publication/byte-exact actual media manifest and held lease, exact URI/query and existing init body cap, existing actual-init/canonical gate, unchanged init IDs/tracks/cache, continued real fragment conversion/full byte goldens, equivalent-layout raw-byte mutations, different epoch/mixed MAP/cached-media URI/unapproved origin, cooperative stop/current decoder refusal, actual Tick timeout/work/cancellation, strict pending diagnostics and successful-only Long alias telemetry/overflow/close.

SHA identity and pre-gate order are each deliberately broken in temporary actual production-source copies; both executions must fail at the specified assertion. Success requires one fresh marker, all16 unique ordered cases/all532 assertions, no failure/crash/nonzero result, child deadline45seconds and output cap64KiB. Stale-marker and actual child timeout/overflow/failure/exit controls also reject. Full current Task XML/runtime compiles in a fresh bounded temporary prefix, which is removed and verified absent.

Decoder and transfer start/cancel are explicit IO boundaries. Digest, binary parser/converter, init inspector and state/cleanup helpers execute. These are portable function regressions, not native transport, A/V, performance or device observations. The production transport keeps its existing origin/TLS/5-second/size/work policies. Mixed MAP windows and changed initialization/epoch remain unsupported; actual new MAP acceptance on Roku remains a root-owned hardware gate.
