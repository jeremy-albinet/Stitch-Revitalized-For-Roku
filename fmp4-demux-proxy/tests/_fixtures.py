"""Synthetic fMP4 fixture builders for testing box parsing and rewriting."""

from __future__ import annotations

import struct


def make_box(box_type: bytes, body: bytes, use_largesize: bool = False) -> bytes:
    """Build a single ISO BMFF box."""
    if use_largesize:
        total = 16 + len(body)
        return struct.pack(">I", 1) + box_type + struct.pack(">Q", total) + body
    total = 8 + len(body)
    return struct.pack(">I", total) + box_type + body


def make_hdlr(handler_type: bytes) -> bytes:
    """Build a minimal hdlr (handler reference) box.

    FullBox layout: version(1) + flags(3) + pre_defined(4) + handler_type(4)
    + reserved(12) + name(null-terminated).
    """
    body = (
        b"\x00\x00\x00\x00"  # version + flags
        + b"\x00\x00\x00\x00"  # pre_defined
        + handler_type  # handler_type (4 bytes)
        + b"\x00" * 12  # reserved
        + b"\x00"  # name (empty, null-terminated)
    )
    return make_box(b"hdlr", body)


def make_tkhd(track_id: int, version: int = 0) -> bytes:
    """Build a minimal tkhd (track header) box.

    Version 0: version(1) + flags(3) + creation_time(4) + modification_time(4)
    + track_ID(4) + reserved(4) + duration(4) + ...padding to 80 bytes body.
    """
    if version == 0:
        body = (
            b"\x00\x00\x00\x00"  # version 0 + flags
            + b"\x00" * 4  # creation_time
            + b"\x00" * 4  # modification_time
            + struct.pack(">I", track_id)  # track_ID
            + b"\x00" * 4  # reserved
            + b"\x00" * 4  # duration
            + b"\x00" * 60  # remaining fields (reserved, layer, etc.)
        )
    else:
        body = (
            b"\x01\x00\x00\x00"  # version 1 + flags
            + b"\x00" * 8  # creation_time (8 bytes in v1)
            + b"\x00" * 8  # modification_time (8 bytes in v1)
            + struct.pack(">I", track_id)  # track_ID
            + b"\x00" * 4  # reserved
            + b"\x00" * 8  # duration (8 bytes in v1)
            + b"\x00" * 52  # remaining fields
        )
    return make_box(b"tkhd", body)


def make_mdhd() -> bytes:
    """Build a minimal mdhd (media header) box."""
    body = b"\x00" * 24  # version 0 mdhd is 24 bytes
    return make_box(b"mdhd", body)


def make_stbl() -> bytes:
    """Build a minimal stbl (sample table) container with an empty stsd."""
    stsd_body = b"\x00" * 8  # version+flags + entry_count=0
    stsd = make_box(b"stsd", stsd_body)
    return make_box(b"stbl", stsd)


def make_minf(handler_type: bytes) -> bytes:
    """Build a minimal minf container (hdlr + stbl)."""
    return make_box(b"minf", make_hdlr(handler_type) + make_stbl())


def make_mdia(handler_type: bytes) -> bytes:
    """Build a minimal mdia container (mdhd + hdlr + minf)."""
    return make_box(b"mdia", make_mdhd() + make_hdlr(handler_type) + make_minf(handler_type))


def make_trak(track_id: int, handler_type: bytes) -> bytes:
    """Build a minimal trak container (tkhd + mdia)."""
    return make_box(b"trak", make_tkhd(track_id) + make_mdia(handler_type))


def make_mvhd() -> bytes:
    """Build a minimal mvhd (movie header) box."""
    body = b"\x00" * 108  # version 0 mvhd is 108 bytes body
    return make_box(b"mvhd", body)


def make_trex(track_id: int) -> bytes:
    """Build a minimal trex (track extends) box."""
    body = (
        b"\x00\x00\x00\x00"  # version + flags
        + struct.pack(">I", track_id)
        + b"\x00\x00\x00\x01"  # default_sample_description_index
        + b"\x00\x00\x00\x00"  # default_sample_duration
        + b"\x00\x00\x00\x00"  # default_sample_size
        + b"\x00\x00\x00\x00"  # default_sample_flags
    )
    return make_box(b"trex", body)


def make_mvex(track_ids: list[int]) -> bytes:
    """Build a minimal mvex container with trex entries."""
    children = b"".join(make_trex(tid) for tid in track_ids)
    return make_box(b"mvex", children)


def make_moov(
    traks: list[tuple[int, bytes]],
    include_mvex: bool = True,
) -> bytes:
    """Build a moov container: mvhd + traks (in given order) + optional mvex.

    *traks* is a list of ``(track_id, handler_type)`` pairs.
    """
    children = make_mvhd()
    for track_id, handler_type in traks:
        children += make_trak(track_id, handler_type)
    if include_mvex:
        children += make_mvex([tid for tid, _ in traks])
    return make_box(b"moov", children)


def make_ftyp() -> bytes:
    """Build a minimal ftyp box."""
    body = b"isom" + b"\x00\x00\x02\x00" + b"isom" + b"iso6" + b"mp41"
    return make_box(b"ftyp", body)


def make_tfhd(track_id: int) -> bytes:
    """Build a minimal tfhd (track fragment header) box."""
    body = b"\x00\x00\x00\x00" + struct.pack(">I", track_id)  # version+flags + track_ID
    return make_box(b"tfhd", body)


def make_tfdt(decode_time: int) -> bytes:
    """Build a tfdt (track fragment decode time) box.

    Uses version 1 (64-bit baseMediaDecodeTime) for generality.
    """
    body = b"\x01\x00\x00\x00" + struct.pack(">Q", decode_time)
    return make_box(b"tfdt", body)


def make_trun() -> bytes:
    """Build a minimal trun (track fragment run) box with zero samples."""
    body = b"\x00\x00\x00\x00" + b"\x00\x00\x00\x00"  # version+flags + sample_count=0
    return make_box(b"trun", body)


def make_traf(track_id: int, decode_time: int = 0) -> bytes:
    """Build a minimal traf container (tfhd + tfdt + trun)."""
    return make_box(
        b"traf",
        make_tfhd(track_id) + make_tfdt(decode_time) + make_trun(),
    )


def make_mfhd(sequence_number: int) -> bytes:
    """Build an mfhd (movie fragment header) box."""
    body = b"\x00\x00\x00\x00" + struct.pack(">I", sequence_number)
    return make_box(b"mfhd", body)


def make_moof(sequence_number: int, trafs: list[int]) -> bytes:
    """Build a moof container: mfhd + traf children.

    *trafs* is a list of track IDs.
    """
    children = make_mfhd(sequence_number)
    for i, track_id in enumerate(trafs):
        children += make_traf(track_id, decode_time=i * 1000)
    return make_box(b"moof", children)


def make_mdat(payload: bytes) -> bytes:
    """Build an mdat box with the given payload."""
    return make_box(b"mdat", payload)


def make_init_segment(traks: list[tuple[int, bytes]]) -> bytes:
    """Build a complete init segment: ftyp + moov."""
    return make_ftyp() + make_moov(traks)


def make_media_segment(
    sequence: int,
    trafs: list[int],
    mdat_size: int = 1024,
) -> bytes:
    """Build a complete media segment: moof + mdat."""
    return make_moof(sequence, trafs) + make_mdat(b"\x00" * mdat_size)


# ---------------------------------------------------------------------------
# Fixtures for split (demux) testing - realistic trun with data_offset
# ---------------------------------------------------------------------------


def make_tfhd_dbim(track_id: int) -> bytes:
    """Build a tfhd with default-base-is-moof flag (0x020000)."""
    body = b"\x00\x02\x00\x00" + struct.pack(">I", track_id)
    return make_box(b"tfhd", body)


def make_trun_with_samples(data_offset: int, sample_sizes: list[int]) -> bytes:
    """Build a trun with data_offset and per-sample size entries.

    Flags: 0x000201 = data_offset_present | sample_size_present.
    """
    sample_count = len(sample_sizes)
    body = (
        b"\x00\x00\x02\x01"  # version=0, flags=0x000201
        + struct.pack(">I", sample_count)
        + struct.pack(">i", data_offset)
    )
    for sz in sample_sizes:
        body += struct.pack(">I", sz)
    return make_box(b"trun", body)


def make_emsg(payload: bytes = b"\x00" * 8) -> bytes:
    """Build a minimal emsg box."""
    return make_box(b"emsg", payload)


def make_split_media_segment(
    sequence: int,
    video_data: bytes,
    audio_data: bytes,
    video_track_id: int = 1,
    audio_track_id: int = 2,
) -> bytes:
    """Build a media segment with correct data_offsets for split testing.

    Returns moof + mdat where each traf's trun data_offset is set so that
    video_data comes first in mdat, followed by audio_data.
    """
    mfhd = make_mfhd(sequence)

    video_traf_placeholder = make_box(
        b"traf",
        make_tfhd_dbim(video_track_id)
        + make_tfdt(0)
        + make_trun_with_samples(0, [len(video_data)]),
    )
    audio_traf_placeholder = make_box(
        b"traf",
        make_tfhd_dbim(audio_track_id)
        + make_tfdt(0)
        + make_trun_with_samples(0, [len(audio_data)]),
    )

    moof_size = 8 + len(mfhd) + len(video_traf_placeholder) + len(audio_traf_placeholder)
    mdat_header_size = 8

    video_data_offset = moof_size + mdat_header_size
    audio_data_offset = video_data_offset + len(video_data)

    video_traf = make_box(
        b"traf",
        make_tfhd_dbim(video_track_id)
        + make_tfdt(0)
        + make_trun_with_samples(video_data_offset, [len(video_data)]),
    )
    audio_traf = make_box(
        b"traf",
        make_tfhd_dbim(audio_track_id)
        + make_tfdt(0)
        + make_trun_with_samples(audio_data_offset, [len(audio_data)]),
    )

    moof = make_box(b"moof", mfhd + video_traf + audio_traf)
    mdat = make_box(b"mdat", video_data + audio_data)
    return moof + mdat
