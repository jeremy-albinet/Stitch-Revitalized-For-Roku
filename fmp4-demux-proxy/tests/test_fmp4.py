"""Tests for fMP4 box parsing and track-order rewriting."""

from __future__ import annotations

import struct

import pytest

from fmp4_demux_proxy.fmp4 import (
    InvalidBoxError,
    TruncatedBoxError,
    extract_track_map,
    iter_top_level_boxes,
    split_moof_mdat,
    split_moov,
)
from tests._fixtures import (
    make_box,
    make_emsg,
    make_init_segment,
    make_split_media_segment,
)


class TestBoxParsing:
    def test_parse_normal_box(self) -> None:
        body = b"\xab" * 20
        raw = make_box(b"test", body)
        boxes = list(iter_top_level_boxes(raw))
        assert len(boxes) == 1
        hdr, data = boxes[0]
        assert hdr.type == b"test"
        assert hdr.header_size == 8
        assert hdr.total_size == 8 + 20
        assert data == raw

    def test_parse_largesize_box(self) -> None:
        body = b"\xcd" * 32
        raw = make_box(b"big!", body, use_largesize=True)
        boxes = list(iter_top_level_boxes(raw))
        assert len(boxes) == 1
        hdr, data = boxes[0]
        assert hdr.type == b"big!"
        assert hdr.header_size == 16
        assert hdr.total_size == 16 + 32
        assert data == raw

    def test_parse_size_zero_extends_to_eof(self) -> None:
        body = b"\xff" * 10
        raw = struct.pack(">I", 0) + b"mdat" + body
        boxes = list(iter_top_level_boxes(raw))
        assert len(boxes) == 1
        hdr, data = boxes[0]
        assert hdr.type == b"mdat"
        assert hdr.total_size == len(raw)
        assert data == raw

    def test_truncated_input_raises(self) -> None:
        raw = make_box(b"test", b"\x00" * 100)
        with pytest.raises(TruncatedBoxError):
            list(iter_top_level_boxes(raw[:20]))

    def test_invalid_size_raises(self) -> None:
        raw = struct.pack(">I", 4) + b"bad!"
        with pytest.raises(InvalidBoxError):
            list(iter_top_level_boxes(raw))

    def test_multiple_top_level_boxes(self) -> None:
        box1 = make_box(b"aaa1", b"\x00" * 4)
        box2 = make_box(b"bbb2", b"\x00" * 8)
        boxes = list(iter_top_level_boxes(box1 + box2))
        assert len(boxes) == 2
        assert boxes[0][0].type == b"aaa1"
        assert boxes[1][0].type == b"bbb2"

    def test_header_too_short_raises(self) -> None:
        with pytest.raises(TruncatedBoxError):
            list(iter_top_level_boxes(b"\x00\x00"))


class TestTrackMapExtraction:
    def test_extract_map_single_video(self) -> None:
        init = make_init_segment([(1, b"vide")])
        tmap = extract_track_map(init)
        assert tmap == {1: "video"}

    def test_extract_map_two_tracks(self) -> None:
        init = make_init_segment([(1, b"soun"), (2, b"vide")])
        tmap = extract_track_map(init)
        assert tmap == {1: "audio", 2: "video"}

    def test_extract_map_with_subtitle(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun"), (3, b"subt")])
        tmap = extract_track_map(init)
        assert tmap == {1: "video", 2: "audio", 3: "other"}


def _extract_moov_child_types(data: bytes) -> list[bytes]:
    from fmp4_demux_proxy.fmp4 import _iter_children

    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moov":
            body = raw[hdr.header_size :]
            return [ch.type for ch, _ in _iter_children(body)]
    return []


def _extract_trak_order(data: bytes) -> list[int]:
    from fmp4_demux_proxy.fmp4 import (
        _extract_track_id_from_tkhd,
        _iter_children,
    )

    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moov":
            body = raw[hdr.header_size :]
            ids = []
            for child_hdr, child_raw in _iter_children(body):
                if child_hdr.type == b"trak":
                    trak_body = child_raw[child_hdr.header_size :]
                    tid = _extract_track_id_from_tkhd(trak_body)
                    if tid is not None:
                        ids.append(tid)
            return ids
    return []


def _extract_moof_child_types(data: bytes) -> list[bytes]:
    from fmp4_demux_proxy.fmp4 import _iter_children

    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moof":
            body = raw[hdr.header_size :]
            return [ch.type for ch, _ in _iter_children(body)]
    return []


def _extract_traf_track_ids(data: bytes) -> list[int]:
    from fmp4_demux_proxy.fmp4 import (
        _extract_track_id_from_tfhd,
        _iter_children,
    )

    ids = []
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moof":
            body = raw[hdr.header_size :]
            for child_hdr, child_raw in _iter_children(body):
                if child_hdr.type == b"traf":
                    traf_body = child_raw[child_hdr.header_size :]
                    tid = _extract_track_id_from_tfhd(traf_body)
                    if tid is not None:
                        ids.append(tid)
    return ids


def _extract_box_raw(data: bytes, box_type: bytes) -> bytes | None:
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == box_type:
            return raw
    return None


def _extract_tfdt_decode_times(data: bytes) -> list[int]:
    from fmp4_demux_proxy.fmp4 import _iter_children

    times = []
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moof":
            moof_body = raw[hdr.header_size :]
            for child_hdr, child_raw in _iter_children(moof_body):
                if child_hdr.type == b"traf":
                    traf_body = child_raw[child_hdr.header_size :]
                    for sub_hdr, sub_raw in _iter_children(traf_body):
                        if sub_hdr.type == b"tfdt":
                            tfdt_body = sub_raw[sub_hdr.header_size :]
                            version = tfdt_body[0]
                            if version == 1:
                                t = struct.unpack_from(">Q", tfdt_body, 4)[0]
                            else:
                                t = struct.unpack_from(">I", tfdt_body, 4)[0]
                            times.append(t)
    return times


def _extract_trun_data_offset(data: bytes) -> int | None:
    from fmp4_demux_proxy.fmp4 import _iter_children

    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moof":
            moof_body = raw[hdr.header_size :]
            for ch, cr in _iter_children(moof_body):
                if ch.type == b"traf":
                    traf_body = cr[ch.header_size :]
                    for sh, sr in _iter_children(traf_body):
                        if sh.type == b"trun":
                            trun_body = sr[sh.header_size :]
                            flags = (trun_body[1] << 16) | (trun_body[2] << 8) | trun_body[3]
                            if flags & 0x001:
                                return struct.unpack_from(">i", trun_body, 8)[0]
    return None


def _extract_trex_track_ids(data: bytes) -> list[int]:
    from fmp4_demux_proxy.fmp4 import _iter_children

    ids = []
    for hdr, raw in iter_top_level_boxes(data):
        if hdr.type == b"moov":
            moov_body = raw[hdr.header_size :]
            for ch, cr in _iter_children(moov_body):
                if ch.type == b"mvex":
                    mvex_body = cr[ch.header_size :]
                    for sh, sr in _iter_children(mvex_body):
                        if sh.type == b"trex":
                            trex_body = sr[sh.header_size :]
                            ids.append(struct.unpack_from(">I", trex_body, 4)[0])
    return ids


class TestSplitMoov:
    def test_keep_video_has_one_video_trak(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "video")

        trak_order = _extract_trak_order(result)
        assert len(trak_order) == 1
        assert trak_order[0] == 1
        result_map = extract_track_map(result)
        assert result_map == {1: "video"}

    def test_keep_audio_has_one_audio_trak(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "audio")

        trak_order = _extract_trak_order(result)
        assert len(trak_order) == 1
        assert trak_order[0] == 1
        result_map = extract_track_map(result)
        assert result_map == {1: "audio"}

    def test_keep_video_no_audio_trex(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "video")

        trex_ids = _extract_trex_track_ids(result)
        assert trex_ids == [1]

    def test_keep_audio_no_video_trex(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "audio")

        trex_ids = _extract_trex_track_ids(result)
        assert trex_ids == [1]

    def test_preserves_ftyp(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "video")

        box_types = [h.type for h, _ in iter_top_level_boxes(result)]
        assert b"ftyp" in box_types
        assert b"moov" in box_types

    def test_parseable_output(self) -> None:
        init = make_init_segment([(1, b"vide"), (2, b"soun")])
        track_map = extract_track_map(init)
        result = split_moov(init, track_map, "video")

        total = sum(h.total_size for h, _ in iter_top_level_boxes(result))
        assert total == len(result)


class TestSplitMoofMdat:
    _VIDEO_DATA = b"\xaa" * 500
    _AUDIO_DATA = b"\xbb" * 300

    def test_keep_video_traf_has_track_id_1(self) -> None:
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(segment, track_map, "video")

        tids = _extract_traf_track_ids(result)
        assert tids == [1]

    def test_keep_audio_traf_has_track_id_1(self) -> None:
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(segment, track_map, "audio")

        tids = _extract_traf_track_ids(result)
        assert tids == [1]

    def test_keep_video_mdat_has_correct_size(self) -> None:
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(segment, track_map, "video")

        mdat_raw = _extract_box_raw(result, b"mdat")
        assert mdat_raw is not None
        mdat_hdr = iter_top_level_boxes(mdat_raw).__next__()[0]
        mdat_body = mdat_raw[mdat_hdr.header_size :]
        assert mdat_body == self._VIDEO_DATA

    def test_keep_audio_mdat_has_correct_size(self) -> None:
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(segment, track_map, "audio")

        mdat_raw = _extract_box_raw(result, b"mdat")
        assert mdat_raw is not None
        mdat_hdr = iter_top_level_boxes(mdat_raw).__next__()[0]
        mdat_body = mdat_raw[mdat_hdr.header_size :]
        assert mdat_body == self._AUDIO_DATA

    def test_data_offset_points_to_mdat_body(self) -> None:
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(segment, track_map, "video")

        moof_raw = _extract_box_raw(result, b"moof")
        assert moof_raw is not None
        data_offset = _extract_trun_data_offset(result)
        assert data_offset is not None
        assert data_offset == len(moof_raw) + 8  # +8 = mdat header

    def test_emsg_included_in_video(self) -> None:
        emsg = make_emsg()
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        data = emsg + segment
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(data, track_map, "video")

        box_types = [h.type for h, _ in iter_top_level_boxes(result)]
        assert b"emsg" in box_types

    def test_emsg_excluded_from_audio(self) -> None:
        emsg = make_emsg()
        segment = make_split_media_segment(1, self._VIDEO_DATA, self._AUDIO_DATA)
        data = emsg + segment
        track_map = {1: "video", 2: "audio"}
        result = split_moof_mdat(data, track_map, "audio")

        box_types = [h.type for h, _ in iter_top_level_boxes(result)]
        assert b"emsg" not in box_types
