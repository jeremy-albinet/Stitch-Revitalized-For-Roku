"""Manifest addressing and configuration boundary fixtures."""

from dataclasses import replace
from urllib.parse import parse_qs, urlparse

import pytest

from fmp4_demux_proxy.config import get_config, validate_proxy_base
from fmp4_demux_proxy.manifest import ManifestError, RewriteConfig, rewrite
from tests.conftest import make_test_config

BASE = "https://edge.ttvnw.net/playlist"
PROXY = RewriteConfig("https://proxy.example.invalid")


def test_map_and_part_range_attributes_can_appear_first() -> None:
    body = (
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:BYTERANGE="100@0",URI="file"\n'
        '#EXT-X-PART:BYTERANGE="20@100",URI="file",DURATION=0.5\n'
        '#EXT-X-PRELOAD-HINT:BYTERANGE-START=120,BYTERANGE-LENGTH=20,TYPE=PART,URI="file"\n'
    )
    output = rewrite(body, BASE, PROXY, track="video")
    assert "BYTERANGE" not in output and ":," not in output and ",," not in output
    part = next(line for line in output.splitlines() if line.startswith("#EXT-X-PART:"))
    query = parse_qs(urlparse(part.split('URI="')[1].split('"')[0]).query)
    assert query["r"] == ["20@100"] and query["ir"] == ["100@0"]
    assert query["i"] == ["https://edge.ttvnw.net/file"]
    preload = next(line for line in output.splitlines() if line.startswith("#EXT-X-PRELOAD-HINT:"))
    assert "r=20%40120" in preload


@pytest.mark.parametrize(
    "body,reason",
    [
        ("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:20\nfile\n", "Implicit"),
        ('#EXTM3U\n#EXT-X-MAP:URI="init",BYTERANGE="10"\n', "Implicit"),
        ('#EXTM3U\n#EXT-X-PRELOAD-HINT:TYPE=PART,URI="part",BYTERANGE-START=0\n', "Open-ended"),
        ('#EXTM3U\n#EXT-X-MAP:BYTERANGE="10@0"\n', "missing"),
        ('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n', "Encrypted"),
        ("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-BYTERANGE:20@0\n", "following"),
    ],
)
def test_bad_or_unsupported_addressing_is_explicit(body: str, reason: str) -> None:
    with pytest.raises(ManifestError, match=reason):
        rewrite(body, BASE, PROXY, track="video")


def test_rendition_report_retains_track_and_passthrough_mode() -> None:
    body = '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-RENDITION-REPORT:URI="../other"\n'
    assert "track=audio" in rewrite(body, BASE, PROXY, track="audio")
    assert "mode=passthrough" in rewrite(body, BASE, PROXY, mode="passthrough")


def test_session_data_is_not_treated_as_a_playlist() -> None:
    body = "\n".join(
        [
            "#EXTM3U",
            '#EXT-X-SESSION-DATA:DATA-ID="info",URI="data.json"',
            "#EXT-X-STREAM-INF:BANDWIDTH=1",
            "v",
            "",
        ]
    )
    output = rewrite(body, BASE, PROXY)
    assert 'URI="https://edge.ttvnw.net/data.json"' in output


def test_repeated_init_url_expansion_is_bounded() -> None:
    body = '#EXTM3U\n#EXT-X-MAP:URI="' + "x" * 50 + '"\n' + "#EXTINF:2,\ns\n" * 20
    with pytest.raises(ManifestError, match="size limit"):
        rewrite(body, BASE, RewriteConfig(PROXY.proxy_base, max_output_bytes=500), track="video")


def test_invalid_version_is_a_manifest_error() -> None:
    body = (
        "#EXTM3U\n#EXT-X-VERSION:bogus\n"
        '#EXT-X-STREAM-INF:CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=1\nv\n'
    )
    with pytest.raises(ManifestError, match="version"):
        rewrite(body, BASE, PROXY)


def test_empty_allowlist_requires_explicit_unsafe_mode() -> None:
    with pytest.raises(ValueError, match="requires"):
        replace(make_test_config(), allow_unsafe_upstream=False)


@pytest.mark.parametrize(
    "url",
    [
        "ftp://proxy.example.invalid",
        "http://user:password@proxy.example.invalid",
        "http://proxy.example.invalid/?token=fixture",
        "http://proxy.example.invalid/#fragment",
        "http://proxy.example.invalid/path\nbad",
        "http://proxy.example.invalid:99999",
    ],
)
def test_invalid_proxy_base_is_rejected(url: str) -> None:
    with pytest.raises(ValueError):
        validate_proxy_base(url)


@pytest.mark.parametrize(
    "overrides",
    [
        {"max_segment_bytes": 0},
        {"segment_cache_bytes": -1},
        {"upstream_total_timeout": float("inf")},
        {"upstream_read_timeout": float("nan")},
    ],
)
def test_limits_must_be_positive_and_finite(overrides: dict[str, int | float]) -> None:
    with pytest.raises(ValueError):
        replace(make_test_config(), **overrides)


def test_environment_defaults_are_safe(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("UPSTREAM_HOST_ALLOWLIST", raising=False)
    monkeypatch.delenv("ALLOW_UNSAFE_UPSTREAM", raising=False)
    config = get_config()
    assert not config.allow_unsafe_upstream
    assert config.upstream_host_allowlist == (
        "ttvnw.net",
        "twitch.tv",
        "twitchcdn.net",
        "cloudfront.net",
    )
