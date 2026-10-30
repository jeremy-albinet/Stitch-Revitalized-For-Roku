These fixtures create synthetic clear AVC/AAC ISO-BMFF fragments. They contain no
downloaded recording, address, token or private-file dependency. The checked seed
is copied from the existing synthetic core fixture and extended with mdhd/trex
timing by corpus.js. Every golden single-track fragment is constructed directly
from declared samples, independently of the production chunker and demuxer.

The test executes byte-identical production Bulk, InitMetadata and VodChunks
BrightScript. It compares the complete 95-pair output and independently reparses
every sample payload, absolute DTS/PTS, duration and flags; five emsg records are
exact on video only. A second fixture verifies trailing metadata. Malformed
whole-input tails, addressing, cross-track overlap, encryption, continuity,
work/byte caps, forged plans, cancellation, close and output failure are actual
helper assertions. Four deliberately mutated helpers must fail normal assertions.

Each fresh brs-node child uses the worker/read instrumentation from
roku-vod-large/engine.js. brs-node 2.6.2 fixes numeric-byte-read copying itself;
the wrapper now observes the first numeric read and delegates every read unchanged
to the engine. Production helpers and their assertions are unchanged. The
large-fixture regression separately compares instrumented and ordinary execution.
Fresh worker markers are required in every mode.

Each child has a 40-second deadline and 1MiB output ceiling; no
network, SceneGraph, deployment, media decoder or device is involved. These are
logical buffer and offline conversion checks, not native heap or throughput
measurements and not an enabled recorded-playback path.
