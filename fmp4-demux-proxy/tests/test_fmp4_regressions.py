"""Malformed addressing regressions must fail before silently changing sample bytes."""

import struct

import pytest

from fmp4_demux_proxy.fmp4 import (
    Fmp4Error,
    TruncatedBoxError,
    _parse_tfhd_info,
    _parse_trun_data,
    extract_track_map,
    iter_top_level_boxes,
    split_moof_mdat,
    split_moov,
)
from tests._fixtures import (
    make_box,
    make_emsg,
    make_init_segment,
    make_mfhd,
    make_split_media_segment,
    make_tfhd_dbim,
    make_trun_with_samples,
)


def samples(data: bytes) -> bytes:
    return b"".join(
        raw[header.header_size :]
        for header, raw in iter_top_level_boxes(data)
        if header.type == b"mdat"
    )


@pytest.mark.parametrize("offset", [-1, 0, 999999])
def test_sample_ranges_outside_mdat_fail(offset: int) -> None:
    data = bytearray(make_split_media_segment(1, b"video", b"audio"))
    struct.pack_into(">i", data, data.index(b"trun") + 12, offset)
    with pytest.raises(Fmp4Error, match="outside mdat"):
        split_moof_mdat(bytes(data), {1: "video", 2: "audio"}, "video")


def test_prefixed_and_multiple_fragments_preserve_samples() -> None:
    first = make_split_media_segment(1, b"first-video", b"first-audio")
    second = make_split_media_segment(2, b"second-video", b"second-audio")
    data = make_emsg() + make_box(b"styp", b"iso6") + first + second
    assert samples(split_moof_mdat(data, {1: "video", 2: "audio"}, "video")) == (
        b"first-videosecond-video"
    )
    assert samples(split_moof_mdat(data, {1: "video", 2: "audio"}, "audio")) == (
        b"first-audiosecond-audio"
    )


def test_indexes_with_original_offsets_are_not_returned() -> None:
    data = make_box(b"sidx", b"original offsets") + make_split_media_segment(1, b"video", b"audio")
    result = split_moof_mdat(data, {1: "video", 2: "audio"}, "video")
    assert b"sidx" not in [header.type for header, _ in iter_top_level_boxes(result)]
    assert samples(result) == b"video"


def test_trailing_fragment_without_mdat_is_not_silently_discarded() -> None:
    data = make_split_media_segment(1, b"video", b"audio") + make_box(b"moof", make_mfhd(2))
    with pytest.raises(Fmp4Error, match="complete"):
        split_moof_mdat(data, {1: "video", 2: "audio"}, "video")


@pytest.mark.parametrize(
    "tfhd,trun,reason",
    [
        (
            make_box(b"tfhd", b"\x00\x02\x00\x01" + struct.pack(">IQ", 1, 0)),
            make_trun_with_samples(0, [5]),
            "relative",
        ),
        (
            make_tfhd_dbim(1),
            make_box(b"trun", b"\x00\x00\x02\x00" + struct.pack(">II", 1, 5)),
            "explicit data offset",
        ),
    ],
)
def test_unsupported_addressing_fails_descriptively(tfhd: bytes, trun: bytes, reason: str) -> None:
    traf = make_box(b"traf", tfhd + trun)
    data = make_box(b"moof", make_mfhd(1) + traf) + make_box(b"mdat", b"video")
    with pytest.raises(Fmp4Error, match=reason):
        split_moof_mdat(data, {1: "video"}, "video")


def test_overlapping_runs_are_rejected() -> None:
    tfhd = make_tfhd_dbim(1)
    placeholder = make_box(
        b"moof", make_mfhd(1) + make_box(b"traf", tfhd + make_trun_with_samples(0, [5]) * 2)
    )
    offset = len(placeholder) + 8
    data = make_box(
        b"moof", make_mfhd(1) + make_box(b"traf", tfhd + make_trun_with_samples(offset, [5]) * 2)
    ) + make_box(b"mdat", b"video")
    with pytest.raises(Fmp4Error, match="overlaps"):
        split_moof_mdat(data, {1: "video"}, "video")


@pytest.mark.parametrize(
    "body",
    [
        b"\x00\x00\x02\x00" + struct.pack(">I", 0xFFFFFFFF),
        b"\x00\x00\x00\x01" + struct.pack(">I", 1),
        b"\x00\x00\x02\x01" + struct.pack(">Ii", 2, 100) + struct.pack(">I", 5),
    ],
)
def test_truncated_sample_tables_raise_domain_error(body: bytes) -> None:
    with pytest.raises(TruncatedBoxError):
        _parse_trun_data(body, 0)


@pytest.mark.parametrize("flags", [1, 2, 8, 16, 32])
def test_truncated_tfhd_optional_fields_raise_domain_error(flags: int) -> None:
    body = bytes([0]) + flags.to_bytes(3, "big") + struct.pack(">I", 1)
    with pytest.raises(TruncatedBoxError):
        _parse_tfhd_info(body)


def test_init_missing_and_duplicate_tracks_fail() -> None:
    init = make_init_segment([(1, b"vide")])
    with pytest.raises(Fmp4Error, match="requested track"):
        split_moov(init, extract_track_map(init), "audio")
    duplicate = make_init_segment([(1, b"vide"), (1, b"soun")])
    with pytest.raises(Fmp4Error, match="duplicate"):
        extract_track_map(duplicate)
