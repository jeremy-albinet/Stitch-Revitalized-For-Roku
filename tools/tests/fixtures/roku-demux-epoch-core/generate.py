"""Build small synthetic binary goldens with the existing independent Python splitter.

Generation only; Node regression execution does not require Python or private files.
The payload/configuration is syntactically inspectable AVC/AAC, not native decode proof.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'fmp4-demux-proxy/src'))
sys.path.insert(0, str(ROOT / 'fmp4-demux-proxy/tests'))
from fmp4_demux_proxy import fmp4
from _fixtures import make_split_media_segment


def box(kind, body):
    return struct.pack('>I4s', 8 + len(body), kind) + body


def boxes(data):
    cursor = 0
    while cursor < len(data):
        count, kind = struct.unpack_from('>I4s', data, cursor)
        assert 8 <= count <= len(data) - cursor
        yield kind, data[cursor + 8:cursor + count]
        cursor += count
    assert cursor == len(data)


def init_variant(original, video_id, audio_id, video_scale, audio_scale):
    result = b''
    for kind, body in boxes(original):
        if kind == b'moov':
            children = b''
            track_index = 0
            for child_kind, child in boxes(body):
                if child_kind == b'trak':
                    track_id = (video_id, audio_id)[track_index]
                    scale = (video_scale, audio_scale)[track_index]
                    fields = b''
                    for field_kind, field in boxes(child):
                        if field_kind == b'tkhd':
                            field = field[:12] + struct.pack('>I', track_id) + field[16:]
                        if field_kind == b'mdia':
                            # Existing sample descriptions are retained byte-for-byte.
                            field = box(b'mdhd', struct.pack('>IIII IHH', 0, 0, 0, scale, 0, 0, 0)) + field
                        fields += box(field_kind, field)
                    child = fields
                    track_index += 1
                children += box(child_kind, child)
            assert track_index == 2
            body = children
        result += box(kind, body)
    return result


def timing(data, video_time, audio_time):
    result = b''
    for kind, body in boxes(data):
        if kind == b'moof':
            children = b''
            index = 0
            for child_kind, child in boxes(body):
                if child_kind == b'traf':
                    fields = b''
                    for field_kind, field in boxes(child):
                        if field_kind == b'tfdt':
                            assert len(field) == 12 and field[0] == 1
                            field = field[:4] + struct.pack('>Q', (video_time, audio_time)[index])
                        fields += box(field_kind, field)
                    child = fields
                    index += 1
                children += box(child_kind, child)
            assert index == 2
            body = children
        result += box(kind, body)
    return result


def record(data):
    return {'hex': data.hex(), 'count': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


base = json.loads((HERE.parent / 'roku-demux-core/corpus.json').read_text())
original = bytes.fromhex(base['init']['input']['hex'])
variants = {'content': (7, 8, 90000, 48000), 'ad': (17, 23, 60000, 96000),
            'other': (27, 31, 120000, 48000)}
inits = {}
maps = {}
for name, (video_id, audio_id, video_scale, audio_scale) in variants.items():
    data = init_variant(original, video_id, audio_id, video_scale, audio_scale)
    tracks = fmp4.extract_track_map(data)
    maps[name] = tracks
    inits[name] = {'input': record(data), 'video': record(fmp4.split_moov(data, tracks, 'video')),
                   'audio': record(fmp4.split_moov(data, tracks, 'audio')),
                   'videoTrackId': video_id, 'audioTrackId': audio_id,
                   'videoTimescale': video_scale, 'audioTimescale': audio_scale}
media = []
for sequence in range(10, 35):
    name = 'ad' if 13 <= sequence <= 15 else 'content'
    if sequence >= 20:
        name = ('content', 'ad', 'other')[(sequence - 20) % 3]
    vi, ai, vs, aus = variants[name]
    origin = 13 if name == 'ad' and sequence < 20 else 16 if sequence >= 16 and sequence < 20 else 10
    video_time = (sequence - origin) * vs * 2002 // 1000
    audio_time = (sequence - origin) * aus * 2002 // 1000
    data = make_split_media_segment(sequence, sequence.to_bytes(4, 'big') * 4,
                                   sequence.to_bytes(4, 'big') * 2, vi, ai)
    data = timing(data, video_time, audio_time)
    media.append({'sequence': sequence, 'map': name, 'videoDecodeTime': video_time, 'audioDecodeTime': audio_time,
                  'input': record(data), 'video': record(fmp4.split_moof_mdat(data, maps[name], 'video')),
                  'audio': record(fmp4.split_moof_mdat(data, maps[name], 'audio'))})

# Independent literal publication snapshots with the known deterministic IDs.
snapshots = {'initial': [(10, 0, 1, 2, 3, 4), (11, 0, 1, 2, 5, 6), (12, 0, 1, 2, 7, 8)],
             'first-ad': [(11, 0, 1, 2, 5, 6), (12, 0, 1, 2, 7, 8), (13, 1, 9, 10, 11, 12)],
             'return': [(14, 1, 9, 10, 13, 14), (15, 1, 9, 10, 15, 16), (16, 2, 17, 18, 19, 20)],
             'rolled': [(16, 2, 17, 18, 19, 20), (17, 2, 17, 18, 21, 22), (18, 2, 17, 18, 23, 24)]}
manifests = {}
prefix = 'live-0123456789abcdef0123456789abcdef-'
for name, rows in snapshots.items():
    manifests[name] = {}
    for track in ('video', 'audio'):
        lines = ['#EXTM3U', '#EXT-X-VERSION:7', '#EXT-X-TARGETDURATION:2',
                 '#EXT-X-MEDIA-SEQUENCE:' + str(rows[0][0]),
                 '#EXT-X-DISCONTINUITY-SEQUENCE:' + str(rows[0][1])]
        previous = None
        for sequence, epoch, iv, ia, video, audio in rows:
            if epoch != previous:
                if previous is not None:
                    lines.append('#EXT-X-DISCONTINUITY')
                lines.append('#EXT-X-MAP:URI="/asset/' + prefix + str(iv if track == 'video' else ia) + '"')
            lines += ['#EXTINF:2.002000,', '/asset/' + prefix + str(video if track == 'video' else audio)]
            previous = epoch
        manifests[name][track] = '\n'.join(lines) + '\n'

data = timing(make_split_media_segment(13, b'PTS-VIDEO-RESET!!', b'PTS-AUD!', 7, 8), 0, 0)
pts_media = {'input': record(data), 'video': record(fmp4.split_moof_mdat(data, maps['content'], 'video')),
             'audio': record(fmp4.split_moof_mdat(data, maps['content'], 'audio'))}
corpus = {'version': 1, 'inits': inits, 'media': media, 'manifests': manifests, 'ptsMedia': pts_media}
# A one-line blob without LF is byte-stable under Git's Windows text policy.
corpus_bytes = json.dumps(corpus, separators=(',', ':')).encode()
(HERE / 'corpus.json').write_bytes(corpus_bytes)
provenance = {'synthetic': True, 'network': False, 'runtimePythonRequired': False,
              'pythonReferenceSha256': hashlib.sha256((ROOT / 'fmp4-demux-proxy/src/fmp4_demux_proxy/fmp4.py').read_bytes()).hexdigest(),
              'generatorSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'corpusSha256': hashlib.sha256(corpus_bytes).hexdigest(), 'actualDecoderApproval': False,
              'initVariants': 3, 'mediaPairs': len(media), 'manifestGoldens': 8}
(HERE / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(json.dumps(provenance))
