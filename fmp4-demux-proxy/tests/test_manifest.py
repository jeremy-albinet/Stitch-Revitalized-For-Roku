"""Tests for the HLS manifest rewriter."""

from __future__ import annotations

import time
from urllib.parse import parse_qs, unquote, urlparse

import pytest

from fmp4_demux_proxy.manifest import ManifestKind, RewriteConfig, classify, rewrite

MASTER_BASIC = (
    "#EXTM3U\n"
    "#EXT-X-VERSION:3\n"
    '#EXT-X-TWITCH-INFO:NODE="video-weaver.lax07.hls.ttvnw.net"\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=6000000,CODECS="avc1.64002A,mp4a.40.2",'
    'RESOLUTION=1920x1080,FRAME-RATE=60.000,STABLE-VARIANT-ID="1080p60",'
    'IVS-NAME="1080p60"\n'
    "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/playlist/1080p60/playlist.m3u8\n"
    '#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS="hev1.1.6.L150.B0,mp4a.40.2",'
    'RESOLUTION=1920x1080,FRAME-RATE=60.000,STABLE-VARIANT-ID="1080p60_hevc",'
    'IVS-NAME="1080p60_hevc"\n'
    "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/playlist/1080p60_hevc/playlist.m3u8\n"
)

VARIANT_BASIC = (
    "#EXTM3U\n"
    "#EXT-X-VERSION:6\n"
    "#EXT-X-TARGETDURATION:2\n"
    "#EXT-X-MEDIA-SEQUENCE:1454\n"
    "#EXT-X-TWITCH-LIVE-SEQUENCE:1454\n"
    '#EXT-X-MAP:URI="https://video-edge-xxx.lax07.hls.ttvnw.net/v1/seg/init.mp4?t=abc"\n'
    "#EXTINF:2.000,live\n"
    "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/seg/chunk-1454.m4s?t=abc\n"
    "#EXT-X-TWITCH-PREFETCH:https://video-edge-xxx.lax07.hls.ttvnw.net/v1/seg/chunk-1455.m4s?t=abc\n"
)

PROXY = "https://proxy.example.com"
BASE_MASTER = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8"
BASE_VARIANT = "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/playlist/1080p60_hevc/playlist.m3u8"


@pytest.fixture
def config() -> RewriteConfig:
    return RewriteConfig(proxy_base=PROXY)


def _decode_proxy_url(proxy_url: str) -> tuple[str, str, str]:
    parsed = urlparse(proxy_url)
    qs = parse_qs(parsed.query, keep_blank_values=True)
    upstream = qs["u"][0]
    kind = qs.get("k", [""])[0]
    return parsed.path, upstream, kind


class TestClassify:
    def test_master_with_stream_inf(self) -> None:
        assert classify(MASTER_BASIC) == ManifestKind.MASTER

    def test_master_audio_only(self) -> None:
        body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",'
            'URI="audio.m3u8"\n'
        )
        assert classify(body) == ManifestKind.MASTER

    def test_variant_with_extinf(self) -> None:
        assert classify(VARIANT_BASIC) == ManifestKind.VARIANT

    def test_variant_with_map_only(self) -> None:
        body = '#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-MAP:URI="init.mp4"\n'
        assert classify(body) == ManifestKind.VARIANT

    def test_variant_with_targetduration_only(self) -> None:
        body = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:2\n"
        assert classify(body) == ManifestKind.VARIANT

    def test_empty_body(self) -> None:
        assert classify("") == ManifestKind.UNKNOWN

    def test_only_comments(self) -> None:
        assert classify("# just a comment\n# another\n") == ManifestKind.UNKNOWN

    def test_garbage(self) -> None:
        assert classify("random\nnonsense\nhere\n") == ManifestKind.UNKNOWN


class TestRewriteMaster:
    def test_simple_master_absolute_uris(self, config: RewriteConfig) -> None:
        out = rewrite(MASTER_BASIC, BASE_MASTER, config)
        lines = out.splitlines()
        variant_lines = [ln for ln in lines if not ln.startswith("#") and ln.strip()]
        assert len(variant_lines) == 2
        for ln in variant_lines:
            assert ln.startswith(f"{PROXY}/m3u8?u=")
            path, upstream, _ = _decode_proxy_url(ln)
            assert path == "/m3u8"
            assert upstream.startswith("https://video-edge-xxx.lax07.hls.ttvnw.net/")

    def test_master_relative_variant_uris(self, config: RewriteConfig) -> None:
        body = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\n360p/playlist.m3u8\n"
        out = rewrite(body, BASE_MASTER, config)
        rewritten = out.splitlines()[-1]
        _, upstream, _ = _decode_proxy_url(rewritten)
        assert upstream == "https://usher.ttvnw.net/api/channel/hls/360p/playlist.m3u8"

    def test_ext_x_media_with_uri(self, config: RewriteConfig) -> None:
        body = (
            "#EXTM3U\n"
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="en",'
            'DEFAULT=YES,URI="audio/en.m3u8"\n'
        )
        out = rewrite(body, BASE_MASTER, config)
        assert 'URI="https://proxy.example.com/m3u8?u=' in out
        assert 'GROUP-ID="audio"' in out
        assert "DEFAULT=YES" in out

    def test_ext_x_media_without_uri_passthrough(self, config: RewriteConfig) -> None:
        body = (
            "#EXTM3U\n"
            '#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",'
            'INSTREAM-ID="CC1",NAME="English"\n'
        )
        out = rewrite(body, BASE_MASTER, config)
        assert out == body

    def test_ext_x_i_frame_stream_inf(self, config: RewriteConfig) -> None:
        body = '#EXTM3U\n#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,URI="iframes.m3u8"\n'
        out = rewrite(body, BASE_MASTER, config)
        assert 'URI="https://proxy.example.com/m3u8?u=' in out

    def test_preserves_crlf_line_endings(self, config: RewriteConfig) -> None:
        body = MASTER_BASIC.replace("\n", "\r\n")
        out = rewrite(body, BASE_MASTER, config)
        assert "\r\n" in out
        assert out.count("\r\n") == body.count("\r\n")

    def test_preserves_lf_line_endings(self, config: RewriteConfig) -> None:
        out = rewrite(MASTER_BASIC, BASE_MASTER, config)
        assert "\r\n" not in out
        assert out.count("\n") == MASTER_BASIC.count("\n")

    def test_preserves_no_trailing_newline(self, config: RewriteConfig) -> None:
        body = MASTER_BASIC.rstrip("\n")
        out = rewrite(body, BASE_MASTER, config)
        assert not out.endswith("\n")

    def test_unknown_ext_tag_passthrough(self, config: RewriteConfig) -> None:
        body = "#EXTM3U\n#EXT-X-CUSTOM-FOO:BAR=baz\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nv.m3u8\n"
        out = rewrite(body, BASE_MASTER, config)
        assert "#EXT-X-CUSTOM-FOO:BAR=baz" in out


class TestRewriteVariant:
    def test_basic_variant_segments(self, config: RewriteConfig) -> None:
        out = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        assert 'URI="https://proxy.example.com/s?u=' in out
        init_line = next(ln for ln in out.splitlines() if ln.startswith("#EXT-X-MAP:"))
        assert "&k=init" in init_line

    def test_extinf_segment_rewritten_as_media(self, config: RewriteConfig) -> None:
        out = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        seg_lines = [
            ln
            for ln in out.splitlines()
            if not ln.startswith("#") and ln.strip() and "chunk-1454" in ln
        ]
        assert len(seg_lines) == 1
        assert seg_lines[0].startswith(f"{PROXY}/s?u=")
        assert "&k=media" in seg_lines[0]

    def test_ext_x_map_rewritten_as_init(self, config: RewriteConfig) -> None:
        out = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        map_line = next(ln for ln in out.splitlines() if ln.startswith("#EXT-X-MAP:"))
        assert "&k=init" in map_line

    def test_ext_x_part_rewritten_as_part(self, config: RewriteConfig) -> None:
        body = '#EXTM3U\n#EXT-X-PART:DURATION=0.5,URI="part1.m4s",INDEPENDENT=YES\n'
        out = rewrite(body, BASE_VARIANT, config, track="video")
        assert "&k=part" in out
        assert "DURATION=0.5" in out
        assert "INDEPENDENT=YES" in out

    def test_preload_hint_type_part(self, config: RewriteConfig) -> None:
        body = (
            "#EXTM3U\n"
            "#EXT-X-PART-INF:PART-TARGET=0.33334\n"
            '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="next.m4s"\n'
        )
        out = rewrite(body, BASE_VARIANT, config, track="video")
        assert "&k=part" in out

    def test_preload_hint_type_map(self, config: RewriteConfig) -> None:
        body = '#EXTM3U\n#EXT-X-PRELOAD-HINT:TYPE=MAP,URI="init.mp4"\n'
        out = rewrite(body, BASE_VARIANT, config, track="video")
        assert "&k=init" in out

    def test_rendition_report_rewritten_as_m3u8(self, config: RewriteConfig) -> None:
        # Rendition-report URIs point to sibling media playlists, not segments.
        # They MUST use the /m3u8 proxy path (no `k=` kind param).
        body = (
            "#EXTM3U\n"
            "#EXT-X-TARGETDURATION:2\n"
            '#EXT-X-RENDITION-REPORT:URI="../1080p60/playlist.m3u8",'
            "LAST-MSN=1454,LAST-PART=3\n"
        )
        out = rewrite(body, BASE_VARIANT, config, track="video")
        rr = next(ln for ln in out.splitlines() if ln.startswith("#EXT-X-RENDITION-REPORT:"))
        assert "/m3u8?u=" in rr
        assert "&k=" not in rr

    def test_ext_x_twitch_prefetch_rewritten(self, config: RewriteConfig) -> None:
        out = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        prefetch_lines = [ln for ln in out.splitlines() if ln.startswith("#EXT-X-TWITCH-PREFETCH:")]
        assert len(prefetch_lines) == 1
        url_portion = prefetch_lines[0][len("#EXT-X-TWITCH-PREFETCH:") :]
        assert url_portion.startswith(f"{PROXY}/s?u=")
        assert "&k=prefetch" in url_portion

    def test_relative_segment_uri_resolved(self, config: RewriteConfig) -> None:
        body = "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.000,\nchunk-1.m4s\n"
        out = rewrite(body, BASE_VARIANT, config, track="video")
        seg = out.splitlines()[-1]
        _, upstream, kind = _decode_proxy_url(seg)
        assert kind == "media"
        assert upstream == (
            "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/playlist/1080p60_hevc/chunk-1.m4s"
        )

    def test_passthrough_tags(self, config: RewriteConfig) -> None:
        body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            "#EXT-X-PLAYLIST-TYPE:VOD\n"
            "#EXT-X-DISCONTINUITY-SEQUENCE:0\n"
            "#EXTINF:2.000,\n"
            "s1.m4s\n"
            "#EXT-X-DISCONTINUITY\n"
            "#EXTINF:2.000,\n"
            "s2.m4s\n"
            "#EXT-X-ENDLIST\n"
        )
        out = rewrite(body, BASE_VARIANT, config, track="video")
        for tag in (
            "#EXT-X-VERSION:6",
            "#EXT-X-TARGETDURATION:2",
            "#EXT-X-MEDIA-SEQUENCE:1",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-DISCONTINUITY-SEQUENCE:0",
            "#EXT-X-DISCONTINUITY",
            "#EXT-X-ENDLIST",
        ):
            assert tag in out


class TestUnknown:
    def test_unknown_returned_unchanged(self, config: RewriteConfig) -> None:
        body = "# just comments\n# nothing else\n"
        assert rewrite(body, BASE_VARIANT, config) == body

    def test_empty_body_unchanged(self, config: RewriteConfig) -> None:
        assert rewrite("", BASE_VARIANT, config) == ""


class TestEdgeCases:
    def test_proxy_base_trailing_slash_normalized(self) -> None:
        cfg_slash = RewriteConfig(proxy_base=f"{PROXY}/")
        cfg_noslash = RewriteConfig(proxy_base=PROXY)
        assert cfg_slash.proxy_base == cfg_noslash.proxy_base == PROXY

    def test_proxy_base_multiple_trailing_slashes(self) -> None:
        cfg = RewriteConfig(proxy_base=f"{PROXY}///")
        assert cfg.proxy_base == PROXY

    def test_special_chars_in_url_percent_encoded(self, config: RewriteConfig) -> None:
        body = "#EXTM3U\n#EXTINF:2.000,\nhttps://edge/path%20with%20spaces/seg?a=1&b=2&c=x y\n"
        out = rewrite(body, BASE_VARIANT, config, track="video")
        rewritten = out.splitlines()[-1]
        _, upstream, _ = _decode_proxy_url(rewritten)
        assert "path%20with%20spaces" in upstream or "path with spaces" in upstream
        path = urlparse(rewritten).path
        assert path == "/s"
        assert "a=1" in upstream
        assert "b=2" in upstream

    def test_large_manifest_performance(self, config: RewriteConfig) -> None:
        header = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n"
        segs = "".join(f"#EXTINF:2.000,\nseg-{i}.m4s\n" for i in range(500))
        body = header + segs + "#EXT-X-ENDLIST\n"
        start = time.perf_counter()
        out = rewrite(body, BASE_VARIANT, config, track="video")
        elapsed = time.perf_counter() - start
        assert elapsed < 0.1, f"rewrite took {elapsed * 1000:.1f}ms for 500 segs"
        assert out.count(f"{PROXY}/s?u=") == 500
        assert "&k=media" in out

    def test_two_consecutive_stream_inf_no_crash(self, config: RewriteConfig) -> None:
        body = (
            "#EXTM3U\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=100\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=200\n"
            "variant.m3u8\n"
        )
        out = rewrite(body, BASE_MASTER, config)
        rewritten = [ln for ln in out.splitlines() if ln.startswith(f"{PROXY}/m3u8?u=")]
        assert len(rewritten) == 1

    def test_double_rewrite_does_not_crash(self, config: RewriteConfig) -> None:
        once = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        twice = rewrite(once, BASE_VARIANT, config, track="video")
        assert isinstance(twice, str)
        assert twice.count(f"{PROXY}/s?u=") >= once.count(f"{PROXY}/s?u=")

    def test_uri_attr_with_extra_whitespace(self, config: RewriteConfig) -> None:
        body = '#EXTM3U\n#EXT-X-MAP:URI = "init.mp4"\n#EXTINF:2.0,\ns.m4s\n'
        out = rewrite(body, BASE_VARIANT, config, track="video")
        assert "/s?u=" in out
        assert "&k=init" in out

    def test_rewritten_upstream_decodes_to_original(self, config: RewriteConfig) -> None:
        out = rewrite(VARIANT_BASIC, BASE_VARIANT, config, track="video")
        seg = next(
            ln
            for ln in out.splitlines()
            if not ln.startswith("#") and ln.strip() and "chunk-1454" in ln
        )
        _, upstream, kind = _decode_proxy_url(seg)
        assert kind == "media"
        assert upstream == (
            "https://video-edge-xxx.lax07.hls.ttvnw.net/v1/seg/chunk-1454.m4s?t=abc"
        )
        assert (
            unquote(upstream.split("u=")[-1].split("&")[0])
            == upstream.split("u=")[-1].split("&")[0]
        )
