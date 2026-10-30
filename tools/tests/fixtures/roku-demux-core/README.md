Run `node --test tools/tests/roku-demux-core.test.js`. CI needs Node and the
existing brs-node/BrighterScript dependencies. It does not need Python, Git,
private files, a service, the simulator's installed package, or a Roku.

The runner copies the CURRENT tracked Bulk/Core/Common/Protocol scripts byte
for byte into an owned temporary root. Four needed cleanup functions are
extracted from CURRENT Fetch without altering their bodies. Source syntax is
parsed, and every tracked snapshot must match after execution. There is no
fake Bulk, Core, cache, digest, publication, quota or clock implementation.
No URL transfer is started. The fixed Fetch input file is absent in the
isolated root; the actual close checks that path rather than faking an ack.

`corpus.json` holds independently generated synthetic ISO-BMFF bytes: one
570-byte AVC4D402A/AAC init, 260 distinct 192-byte combined fragments, their
522 complete Python-reference split outputs, and nine malformed inputs.
Counts and SHA256 identities for every complete binary are checked by Node
before execution. BrightScript verifies complete bytes and SHA256 outputs,
plus input immutability, through the actual splitter/cache. Samples contain
synthetic payload bytes, not encoded frames that establish picture/audio.

`init-seed.json` is a self-contained copy of the previously checked synthetic
AVC/AAC init. `generate_corpus.py` is OPTIONAL developer regeneration using
tracked pure Python reference/builders; it neither imports nor reads private
artifacts. `provenance.json` records source/corpus hashes, unique inputs and
counts. CI reads only the checked corpus/provenance. This corpus was generated
independently of BrightScript; it is not runtime production output replay.

The rolling pipeline crosses the former ID, generation and 45-second limits
using a logical clock, while an actual acquired retired body stays registered
until release. Poll-gap tests require every retained intervening source pair
and reject missing/oversize/map/epoch history. Real advertised-generation and
per-asset lease caps, digest-mutation guard, atomic 64-asset pair admission,
finite defaults, progress deadlines, long wraps/counters and renewal quotas
execute. Cache-byte admission is an arithmetic boundary check, not proof of a
16–32MiB allocation; its real pair-store count rejection uses tiny buffers.
Transfer quota checks charge the actual helper, not network operations.

A temporary source mutation restores the rejected duration-is-empty flag,
and a separate corrupted complete golden must both produce genuine fixture
failures despite normal child exit. Output/marker/timeout/overflow/nonzero
controls reject false positives. Assertion counts are diagnostic, not pinned.
These are pure/offline proofs only: no native decoder, video/audio, sockets,
throughput, device memory, native Task cleanup or supported-device claim.
