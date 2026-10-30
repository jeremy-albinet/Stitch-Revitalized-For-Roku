"""Developer-only regeneration. CI uses the checked self-contained corpus.

Synthetic ISO-BMFF builders and the independent Python demux implementation
produce complete byte expectations. No private files, media or network input.
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "fmp4-demux-proxy/src"))
from fmp4_demux_proxy import fmp4
sys.path.insert(0, str(ROOT / "fmp4-demux-proxy/tests"))
from _fixtures import make_split_media_segment, make_box


def identity(data: bytes) -> dict:
    return {"hex": data.hex(), "count": len(data),
            "sha256": hashlib.sha256(data).hexdigest()}


seed = json.loads((HERE / "init-seed.json").read_text(encoding="utf-8"))
init = bytes.fromhex(seed["hex"])
tracks = fmp4.extract_track_map(init)
assert tracks == {7: "video", 8: "audio"}
video = fmp4.split_moov(init, tracks, "video")
audio = fmp4.split_moov(init, tracks, "audio")
media = []
for sequence in range(10, 270):
    data = make_split_media_segment(sequence,
                                   sequence.to_bytes(4, "big") * 4,
                                   sequence.to_bytes(4, "big") * 2, 7, 8)
    media.append({"sequence": sequence, "input": identity(data),
                  "video": identity(fmp4.split_moof_mdat(data, tracks, "video")),
                  "audio": identity(fmp4.split_moof_mdat(data, tracks, "audio"))})

negative = []
base = bytes.fromhex(media[0]["input"]["hex"])
for keep in ("video", "audio"):
    for flagged in (7, 8):
        data = bytearray(base)
        needle = b"tfhd\x00\x02\x00\x00" + struct.pack(">I", flagged)
        at = data.index(needle)
        data[at + 5] |= 1  # duration-is-empty; not implemented in native subset
        role = "requested" if tracks[flagged] == keep else "discarded"
        negative.append({"name": f"duration-empty-{keep}-{role}", "operation": "media",
                         "keep": keep, "input": identity(data),
                         "reason": "unsupported tfhd flags"})

negative.append({"name": "truncated-init", "operation": "init", "keep": "video",
                 "input": identity(init[:-1]), "reason": "invalid or truncated box size"})
negative.append({"name": "encrypted-init", "operation": "init", "keep": "audio",
                 "input": identity(init + make_box(b"pssh", b"\x00" * 8)),
                 "reason": "encrypted or UUID layout unsupported"})
duplicate = bytearray(init)
at = duplicate.index(b"tkhd", duplicate.index(b"tkhd") + 4)
struct.pack_into(">I", duplicate, at + 16, 7)
negative.append({"name": "duplicate-track-id", "operation": "init", "keep": "video",
                 "input": identity(duplicate), "reason": "track limit or duplicate ID"})
bad_offset = bytearray(base)
at = bad_offset.index(b"trun")
struct.pack_into(">i", bad_offset, at + 12, -1)
negative.append({"name": "negative-sample-offset", "operation": "media", "keep": "audio",
                 "input": identity(bad_offset), "reason": "sample data outside mdat"})
negative.append({"name": "sample-grouping", "operation": "media", "keep": "video",
                 "input": identity(base + make_box(b"sgpd", b"\x00" * 8)),
                 "reason": "sample grouping layout unsupported"})

result = {"version": 1, "init": {"input": identity(init), "video": identity(video),
                                    "audio": identity(audio), "metadata": seed["expected"]},
          "media": media, "negative": negative}
encoded = (json.dumps(result, separators=(",", ":")) + "\n").encode()
(HERE / "corpus.json").write_bytes(encoded)
parser = ROOT / "fmp4-demux-proxy/src/fmp4_demux_proxy/fmp4.py"
builders = ROOT / "fmp4-demux-proxy/tests/_fixtures.py"
provenance = {"synthetic": True, "network": False, "runtimePythonRequired": False,
              "pythonReferenceSha256": hashlib.sha256(parser.read_bytes()).hexdigest(),
              "pythonBuilderSha256": hashlib.sha256(builders.read_bytes()).hexdigest(),
              "corpusSha256": hashlib.sha256(encoded).hexdigest(),
              "initCount": len(init), "mediaCount": len(media),
              "largestCombinedMedia": max(x["input"]["count"] for x in media),
              "aggregateCombinedMedia": sum(x["input"]["count"] for x in media),
              "uniqueCombinedMedia": len({x["input"]["sha256"] for x in media}),
              "fullPythonOutputGoldens": 2 + 2 * len(media),
              "malformedCases": len(negative)}
(HERE / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
print(json.dumps(provenance))
