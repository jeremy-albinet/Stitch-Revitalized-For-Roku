"""fMP4 box parser and track demuxer.

Parses ISO/IEC 14496-12 (ISO BMFF) containers and demuxes muxed fMP4
into separate single-track segments (video and audio).

Pure functions on bytes.  No global state, stdlib only.
"""

from __future__ import annotations

import struct
from collections.abc import Iterator, Mapping
from typing import Final, Literal, NamedTuple

_HANDLER_VIDEO: Final[bytes] = b"vide"
_HANDLER_AUDIO: Final[bytes] = b"soun"

TrackKind = Literal["video", "audio", "other"]


class Fmp4Error(Exception):
    """Base exception for fMP4 parsing/rewriting errors."""


class TruncatedBoxError(Fmp4Error):
    """Box header declares a size larger than the available data."""


class InvalidBoxError(Fmp4Error):
    """Box has an invalid size (e.g. < 8 and not 0 or 1)."""


class BoxHeader(NamedTuple):
    """Parsed box header metadata."""

    offset: int
    header_size: int
    total_size: int
    type: bytes


def _parse_box_header(data: bytes, offset: int, data_len: int) -> BoxHeader:
    remaining = data_len - offset
    if remaining < 8:
        raise TruncatedBoxError(
            f"Need 8 bytes for box header at offset {offset}, only {remaining} available"
        )

    size_field = struct.unpack_from(">I", data, offset)[0]
    box_type = data[offset + 4 : offset + 8]

    if size_field == 1:
        if remaining < 16:
            raise TruncatedBoxError(
                f"Need 16 bytes for largesize header at offset {offset}, only {remaining} available"
            )
        largesize = struct.unpack_from(">Q", data, offset + 8)[0]
        if largesize < 16:
            raise InvalidBoxError(f"Largesize {largesize} < 16 at offset {offset}")
        if offset + largesize > data_len:
            raise TruncatedBoxError(
                f"Largesize box at offset {offset} declares {largesize} bytes, "
                f"but only {data_len - offset} available"
            )
        return BoxHeader(offset=offset, header_size=16, total_size=int(largesize), type=box_type)

    if size_field == 0:
        total = data_len - offset
        return BoxHeader(offset=offset, header_size=8, total_size=total, type=box_type)

    if size_field < 8:
        raise InvalidBoxError(f"Box size {size_field} < 8 at offset {offset}")

    if offset + size_field > data_len:
        raise TruncatedBoxError(
            f"Box at offset {offset} declares {size_field} bytes, "
            f"but only {data_len - offset} available"
        )

    return BoxHeader(offset=offset, header_size=8, total_size=size_field, type=box_type)


def iter_top_level_boxes(data: bytes) -> Iterator[tuple[BoxHeader, bytes]]:
    """Yield ``(header, raw_box_bytes)`` for each top-level box in *data*."""
    offset = 0
    data_len = len(data)
    while offset < data_len:
        hdr = _parse_box_header(data, offset, data_len)
        end = offset + hdr.total_size
        yield hdr, data[offset:end]
        offset = end


def _iter_children(body: bytes) -> Iterator[tuple[BoxHeader, bytes]]:
    offset = 0
    body_len = len(body)
    while offset < body_len:
        hdr = _parse_box_header(body, offset, body_len)
        end = offset + hdr.total_size
        yield hdr, body[offset:end]
        offset = end


def _classify_trak(trak_body: bytes) -> TrackKind:
    # trak -> mdia -> hdlr: handler_type at hdlr body[8:12]
    # (4B version+flags, 4B pre_defined, 4B handler_type)
    for _, mdia_raw in _iter_children(trak_body):
        mdia_hdr = _parse_box_header(mdia_raw, 0, len(mdia_raw))
        if mdia_hdr.type != b"mdia":
            continue
        mdia_body = mdia_raw[mdia_hdr.header_size :]
        for _, hdlr_raw in _iter_children(mdia_body):
            hdlr_hdr = _parse_box_header(hdlr_raw, 0, len(hdlr_raw))
            if hdlr_hdr.type != b"hdlr":
                continue
            hdlr_body = hdlr_raw[hdlr_hdr.header_size :]
            if len(hdlr_body) < 12:
                return "other"
            handler_type = hdlr_body[8:12]
            if handler_type == _HANDLER_VIDEO:
                return "video"
            if handler_type == _HANDLER_AUDIO:
                return "audio"
            return "other"
    return "other"


def _extract_track_id_from_tkhd(trak_body: bytes) -> int | None:
    # tkhd FullBox: v0 track_ID at offset 12, v1 at offset 20
    for _, child_raw in _iter_children(trak_body):
        child_hdr = _parse_box_header(child_raw, 0, len(child_raw))
        if child_hdr.type != b"tkhd":
            continue
        body = child_raw[child_hdr.header_size :]
        if len(body) < 4:
            return None
        version = body[0]
        if version == 0:
            if len(body) < 16:
                return None
            return struct.unpack_from(">I", body, 12)[0]
        if len(body) < 24:
            return None
        return struct.unpack_from(">I", body, 20)[0]
    return None


def _extract_track_id_from_tfhd(traf_body: bytes) -> int | None:
    # tfhd FullBox: track_ID at body[4:8]
    for _, child_raw in _iter_children(traf_body):
        child_hdr = _parse_box_header(child_raw, 0, len(child_raw))
        if child_hdr.type != b"tfhd":
            continue
        body = child_raw[child_hdr.header_size :]
        if len(body) < 8:
            return None
        return struct.unpack_from(">I", body, 4)[0]
    return None


def _extract_track_id_from_trex(trex_body: bytes) -> int | None:
    # trex FullBox: version(1)+flags(3)+track_ID(4) => track_ID at body[4:8]
    if len(trex_body) < 8:
        return None
    return struct.unpack_from(">I", trex_body, 4)[0]


def extract_track_map(data: bytes) -> dict[int, TrackKind]:
    """Build ``{track_id: kind}`` from an init segment's moov box."""
    result: dict[int, TrackKind] = {}
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type != b"moov":
            continue
        moov_body = raw[hdr.header_size :]
        for _, child_raw in _iter_children(moov_body):
            child_hdr = _parse_box_header(child_raw, 0, len(child_raw))
            if child_hdr.type != b"trak":
                continue
            trak_body = child_raw[child_hdr.header_size :]
            track_id = _extract_track_id_from_tkhd(trak_body)
            if track_id is not None:
                result[track_id] = _classify_trak(trak_body)
    return result


# ---------------------------------------------------------------------------
# Track splitting - demux into single-track segments
# ---------------------------------------------------------------------------


def _build_box(box_type: bytes, body: bytes) -> bytes:
    """Build a box from type + body, using largesize if needed."""
    total = 8 + len(body)
    if total > 0xFFFFFFFF:
        return struct.pack(">I", 1) + box_type + struct.pack(">Q", 16 + len(body)) + body
    return struct.pack(">I", total) + box_type + body


def _remap_tkhd_track_id(trak_body: bytes, new_id: int) -> bytes:
    """Return trak children bytes with tkhd.track_id rewritten to *new_id*."""
    parts: list[bytes] = []
    for child_hdr, child_raw in _iter_children(trak_body):
        if child_hdr.type == b"tkhd":
            raw_mut = bytearray(child_raw)
            version = raw_mut[child_hdr.header_size]
            id_off = child_hdr.header_size + (12 if version == 0 else 20)
            struct.pack_into(">I", raw_mut, id_off, new_id)
            parts.append(bytes(raw_mut))
        else:
            parts.append(child_raw)
    return b"".join(parts)


def _filter_mvex_for_split(
    mvex_raw: bytes,
    track_map: Mapping[int, TrackKind],
    keep: TrackKind,
) -> bytes:
    """Keep only trex entries whose track maps to *keep*; remap track_id to 1."""
    mvex_hdr = _parse_box_header(mvex_raw, 0, len(mvex_raw))
    mvex_body = mvex_raw[mvex_hdr.header_size :]
    parts: list[bytes] = []
    for child_hdr, child_raw in _iter_children(mvex_body):
        if child_hdr.type != b"trex":
            parts.append(child_raw)
            continue
        trex_body = child_raw[child_hdr.header_size :]
        track_id = _extract_track_id_from_trex(trex_body)
        if track_id is None or track_id not in track_map or track_map[track_id] != keep:
            continue
        raw_mut = bytearray(child_raw)
        struct.pack_into(">I", raw_mut, child_hdr.header_size + 4, 1)
        parts.append(bytes(raw_mut))
    return _build_box(b"mvex", b"".join(parts))


def split_moov(
    data: bytes,
    track_map: Mapping[int, TrackKind],
    keep: TrackKind,
) -> bytes:
    """Keep only the trak/trex for *keep* kind; remap its track_id to 1."""
    parts: list[bytes] = []
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type != b"moov":
            parts.append(raw)
            continue
        moov_body = raw[hdr.header_size :]
        children: list[bytes] = []
        for child_hdr, child_raw in _iter_children(moov_body):
            if child_hdr.type == b"trak":
                trak_body = child_raw[child_hdr.header_size :]
                track_id = _extract_track_id_from_tkhd(trak_body)
                if track_id is None or track_id not in track_map:
                    continue
                if track_map[track_id] != keep:
                    continue
                new_body = _remap_tkhd_track_id(trak_body, 1)
                children.append(_build_box(b"trak", new_body))
            elif child_hdr.type == b"mvex":
                children.append(_filter_mvex_for_split(child_raw, track_map, keep))
            else:
                children.append(child_raw)
        parts.append(_build_box(b"moov", b"".join(children)))
    return b"".join(parts)


# -- helpers for split_moof_mdat -------------------------------------------


def _parse_tfhd_info(tfhd_body: bytes) -> tuple[int, int, int]:
    """Return ``(track_id, flags24, default_sample_size)`` from a tfhd body."""
    flags = (tfhd_body[1] << 16) | (tfhd_body[2] << 8) | tfhd_body[3]
    track_id = struct.unpack_from(">I", tfhd_body, 4)[0]
    offset = 8
    if flags & 0x000001:  # base_data_offset
        offset += 8
    if flags & 0x000002:  # sample_description_index
        offset += 4
    if flags & 0x000008:  # default_sample_duration
        offset += 4
    default_sample_size = 0
    if flags & 0x000010:  # default_sample_size
        default_sample_size = struct.unpack_from(">I", tfhd_body, offset)[0]
    return track_id, flags, default_sample_size


def _parse_trun_data(
    trun_body: bytes,
    default_sample_size: int,
) -> tuple[int, int, int]:
    """Return ``(data_offset, total_data_size, flags24)`` from a trun body."""
    flags = (trun_body[1] << 16) | (trun_body[2] << 8) | trun_body[3]
    sample_count = struct.unpack_from(">I", trun_body, 4)[0]
    off = 8
    data_offset = 0
    if flags & 0x001:
        data_offset = struct.unpack_from(">i", trun_body, off)[0]
        off += 4
    if flags & 0x004:  # first_sample_flags
        off += 4
    total = 0
    has_size = bool(flags & 0x200)
    for _ in range(sample_count):
        if flags & 0x100:
            off += 4
        if flags & 0x200:
            total += struct.unpack_from(">I", trun_body, off)[0]
            off += 4
        if flags & 0x400:
            off += 4
        if flags & 0x800:
            off += 4
    if not has_size:
        total = sample_count * default_sample_size
    return data_offset, total, flags


def _traf_data_ranges(
    traf_raw: bytes,
    moof_offset: int,
) -> list[tuple[int, int]]:
    """Return ``[(abs_start, size)]`` for data belonging to this traf."""
    traf_hdr = _parse_box_header(traf_raw, 0, len(traf_raw))
    traf_body = traf_raw[traf_hdr.header_size :]

    default_sample_size = 0
    for ch, cr in _iter_children(traf_body):
        if ch.type == b"tfhd":
            _, _, default_sample_size = _parse_tfhd_info(cr[ch.header_size :])
            break

    ranges: list[tuple[int, int]] = []
    for ch, cr in _iter_children(traf_body):
        if ch.type != b"trun":
            continue
        data_offset, total, _ = _parse_trun_data(cr[ch.header_size :], default_sample_size)
        if total > 0:
            ranges.append((moof_offset + data_offset, total))
    return ranges


def _rewrite_traf_for_split(
    traf_raw: bytes,
    new_track_id: int,
    new_data_offset: int,
) -> bytes:
    """Return traf with patched tfhd track_id and first trun data_offset."""
    traf_hdr = _parse_box_header(traf_raw, 0, len(traf_raw))
    traf_body = traf_raw[traf_hdr.header_size :]
    parts: list[bytes] = []
    running_offset = new_data_offset
    for ch, cr in _iter_children(traf_body):
        if ch.type == b"tfhd":
            mut = bytearray(cr)
            struct.pack_into(">I", mut, ch.header_size + 4, new_track_id)
            parts.append(bytes(mut))
        elif ch.type == b"trun":
            trun_body = cr[ch.header_size :]
            flags = (trun_body[1] << 16) | (trun_body[2] << 8) | trun_body[3]
            if flags & 0x001:
                mut = bytearray(cr)
                struct.pack_into(">i", mut, ch.header_size + 8, running_offset)
                parts.append(bytes(mut))
                tfhd_default = 0
                for ch2, cr2 in _iter_children(traf_body):
                    if ch2.type == b"tfhd":
                        _, _, tfhd_default = _parse_tfhd_info(cr2[ch2.header_size :])
                        break
                _, tsize, _ = _parse_trun_data(trun_body, tfhd_default)
                running_offset += tsize
            else:
                parts.append(cr)
        else:
            parts.append(cr)
    return _build_box(b"traf", b"".join(parts))


def split_moof_mdat(
    data: bytes,
    track_map: Mapping[int, TrackKind],
    keep: TrackKind,
) -> bytes:
    """Demux a media segment: keep only the *keep* track's traf and mdat data."""
    parts: list[bytes] = []
    pending_moof: tuple[BoxHeader, bytes] | None = None

    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"emsg":
            if keep == "video":
                parts.append(raw)
            continue

        if hdr.type == b"moof":
            pending_moof = (hdr, raw)
            continue

        if hdr.type == b"mdat" and pending_moof is not None:
            moof_hdr, moof_raw = pending_moof
            moof_body = moof_raw[moof_hdr.header_size :]

            kept_traf_raw: bytes | None = None
            kept_ranges: list[tuple[int, int]] = []
            non_traf_children: list[bytes] = []

            for ch, cr in _iter_children(moof_body):
                if ch.type != b"traf":
                    non_traf_children.append(cr)
                    continue
                traf_body = cr[ch.header_size :]
                tid = _extract_track_id_from_tfhd(traf_body)
                if tid is not None and tid in track_map and track_map[tid] == keep:
                    kept_traf_raw = cr
                    kept_ranges = _traf_data_ranges(cr, moof_hdr.offset)

            if kept_traf_raw is not None:
                prelim_traf = _rewrite_traf_for_split(kept_traf_raw, 1, 0)
                prelim_moof_body = b"".join(non_traf_children) + prelim_traf
                prelim_moof_size = 8 + len(prelim_moof_body)

                real_data_offset = prelim_moof_size + 8  # +8 = mdat header
                final_traf = _rewrite_traf_for_split(kept_traf_raw, 1, real_data_offset)
                final_moof = _build_box(b"moof", b"".join(non_traf_children) + final_traf)

                kept_bytes = b"".join(data[s : s + n] for s, n in kept_ranges)
                parts.append(final_moof)
                parts.append(_build_box(b"mdat", kept_bytes))

            pending_moof = None
            continue

        parts.append(raw)

    return b"".join(parts)
