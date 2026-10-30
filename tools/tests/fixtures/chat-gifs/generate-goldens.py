"""Author-time independent reference; Python 3 + Pillow 12.3, not a CI dependency.

Never rewrites the public source GIF. Run from this directory to regenerate JSON.
Native GPU filtering is a separate device boundary: these hashes use the exact
pixel-center nearest lattice from the native two-frame gate, not bilinear filtering.
"""
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import json
import struct
from PIL import Image

root = Path(__file__).parent
data = (root / 'twitch-official.gif').read_bytes()
assert sha256(data).hexdigest() == 'c6fb00eda3e154dd1a2be3f77ffe1fc12443a39464b63fc6cfa0748d9b5ffd42'

def normalized(image):
    rgba = bytearray(image.convert('RGBA').tobytes())
    for i in range(0, len(rgba), 4):
        if rgba[i+3] == 0:
            rgba[i:i+3] = b'\0\0\0'
    return bytes(rgba)

def reference():
    offset = 13
    gct = b''
    if data[10] & 128:
        size = 3 * (2 << (data[10] & 7))
        gct = data[offset:offset+size]
        offset += size
    control = None
    frames = []
    movie = Image.open(BytesIO(data))
    while data[offset] != 0x3b:
        marker = data[offset]
        offset += 1
        if marker == 0x21:
            label = data[offset]
            offset += 1
            if label == 0xf9:
                assert data[offset] == 4
                control = data[offset+1:offset+5]
            while data[offset]:
                offset += data[offset] + 1
            offset += 1
            continue
        assert marker == 0x2c and control is not None
        x, y, w, h, flags = struct.unpack_from('<HHHHB', data, offset)
        offset += 9
        palette = gct
        if flags & 128:
            size = 3 * (2 << (flags & 7))
            palette = data[offset:offset+size]
            offset += size
        start = offset
        offset += 1
        while data[offset]:
            offset += data[offset] + 1
        offset += 1
        # Re-express the active palette as a GCT; no byte of LZW is changed.
        table_flags = 128 | ((len(palette)//3).bit_length() - 2)
        prefix = b'GIF89a' + struct.pack('<HHBBB', w, h, table_flags, 0, 0) + palette
        prefix += bytes([0x21, 0xf9, 4, control[0] & 1, 0, 0, control[3], 0, 0x2c])
        prefix += struct.pack('<HHHHB', 0, 0, w, h, flags & 64)
        wrapper = prefix + data[start:offset] + b'\x3b'
        native = Image.open(BytesIO(wrapper)).convert('RGBA')
        movie.seek(len(frames))
        composed = movie.convert('RGBA')
        # Pillow NEAREST uses the same pixel-center lattice at 480 -> 64.
        sampled = composed.resize((64, 64), Image.Resampling.NEAREST)
        frames.append(dict(wrapperSha256=sha256(wrapper).hexdigest(), wrapperBytes=len(wrapper),
                           decodedSha256=sha256(normalized(native)).hexdigest(),
                           rgba64Sha256=sha256(normalized(sampled)).hexdigest(),
                           delayMs=struct.unpack_from('<H', control, 1)[0]*10,
                           x=x, y=y, width=w, height=h, interlaced=bool(flags & 64)))
        control = None
    assert len(frames) == 15 and sum(f['delayMs'] for f in frames) == 990
    return dict(sourceSha256=sha256(data).hexdigest(), sourceBytes=len(data), frames=frames)

(root / 'pillow-goldens.json').write_text(json.dumps(reference(), indent=2) + '\n')
