"""HLS manifest (m3u8) URL rewriting."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum
from typing import Final
from urllib.parse import quote, urljoin

_DEFAULT_BANDWIDTH: Final[int] = 4_000_000
_DEFAULT_CODECS: Final[str] = "avc1.64001f,mp4a.40.2"
_CODEC_CHARS_RE: Final[re.Pattern[str]] = re.compile(r"^[A-Za-z0-9.,_\-]+$")

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------


class ManifestKind(StrEnum):
    MASTER = "master"
    VARIANT = "variant"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class RewriteConfig:
    proxy_base: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "proxy_base", self.proxy_base.rstrip("/"))


@dataclass(frozen=True)
class VariantHints:
    """Optional codec/bandwidth/resolution hints for synthesized master playlists.

    Twitch Enhanced Broadcasting variants may use H.264, HEVC, or AV1. Because
    the proxy only sees the variant body (not the original master), the caller
    must supply the codec tuple parsed from the upstream master's
    #EXT-X-STREAM-INF line; otherwise the fallback H.264 codec is advertised
    and HEVC/AV1 streams will fail on the client decoder.
    """

    codecs: str | None = None
    bandwidth: int | None = None
    resolution: str | None = None


# ---------------------------------------------------------------------------
# Private constants
# ---------------------------------------------------------------------------

_PREFETCH_TAG: Final[str] = "#EXT-X-TWITCH-PREFETCH:"
_URI_ATTR_RE: Final[re.Pattern[str]] = re.compile(r'URI\s*=\s*"([^"]*)"')
_TYPE_ATTR_RE: Final[re.Pattern[str]] = re.compile(r"TYPE\s*=\s*([^,\s]+)")

_MASTER_INDICATORS: Final[tuple[str, ...]] = (
    "#EXT-X-STREAM-INF:",
    "#EXT-X-I-FRAME-STREAM-INF:",
)
_VARIANT_INDICATORS: Final[tuple[str, ...]] = (
    "#EXTINF:",
    "#EXT-X-MAP:",
    "#EXT-X-TARGETDURATION:",
    "#EXT-X-PART:",
    "#EXT-X-PRELOAD-HINT:",
    "#EXT-X-RENDITION-REPORT:",
    "#EXT-X-TWITCH-PREFETCH:",
)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def classify(body: str) -> ManifestKind:
    has_master_indicator = False
    has_media_tag = False
    has_variant_indicator = False

    for raw_line in body.splitlines():
        if raw_line.startswith(_MASTER_INDICATORS):
            has_master_indicator = True
            break
        if raw_line.startswith("#EXT-X-MEDIA:"):
            has_media_tag = True
        elif raw_line.startswith(_VARIANT_INDICATORS):
            has_variant_indicator = True

    if has_master_indicator or (has_media_tag and not has_variant_indicator):
        return ManifestKind.MASTER
    if has_variant_indicator:
        return ManifestKind.VARIANT
    return ManifestKind.UNKNOWN


def rewrite(
    body: str,
    base_url: str,
    config: RewriteConfig,
    *,
    track: str | None = None,
    hints: VariantHints | None = None,
) -> str:
    kind = classify(body)
    if kind == ManifestKind.UNKNOWN:
        return body

    if kind == ManifestKind.VARIANT and track is None:
        return _synthesize_master(base_url, config, hints)

    lines = body.splitlines(keepends=True)
    result: list[str] = []
    expect_uri: str | None = None

    for line in lines:
        stripped = line.rstrip("\r\n")

        if not stripped or (stripped.startswith("#") and not stripped.startswith("#EXT")):
            result.append(line)
            continue

        if expect_uri is not None and not stripped.startswith("#"):
            ending = line[len(stripped) :]
            abs_url = _resolve(stripped, base_url)
            result.append(_proxy_url(config, expect_uri, abs_url, track=track) + ending)
            expect_uri = None
            continue

        if kind == ManifestKind.MASTER:
            if stripped.startswith("#EXT-X-STREAM-INF:"):
                expect_uri = "m3u8"
                result.append(line)
                continue
            if stripped.startswith(
                (
                    "#EXT-X-MEDIA:",
                    "#EXT-X-I-FRAME-STREAM-INF:",
                    "#EXT-X-SESSION-DATA:",
                )
            ):
                result.append(_rewrite_uri_attr(line, base_url, config, "m3u8"))
                continue

        elif kind == ManifestKind.VARIANT:
            if stripped.startswith("#EXTINF:"):
                expect_uri = "media"
                result.append(line)
                continue
            if stripped.startswith("#EXT-X-MAP:"):
                result.append(_rewrite_uri_attr(line, base_url, config, "init", track=track))
                continue
            if stripped.startswith("#EXT-X-PART:"):
                result.append(_rewrite_uri_attr(line, base_url, config, "part", track=track))
                continue
            if stripped.startswith("#EXT-X-PRELOAD-HINT:"):
                result.append(
                    _rewrite_uri_attr(
                        line, base_url, config, _preload_hint_kind(stripped), track=track
                    )
                )
                continue
            if stripped.startswith("#EXT-X-RENDITION-REPORT:"):
                result.append(_rewrite_uri_attr(line, base_url, config, "m3u8"))
                continue
            if stripped.startswith(_PREFETCH_TAG):
                ending = line[len(stripped) :]
                url = stripped[len(_PREFETCH_TAG) :]
                abs_url = _resolve(url, base_url)
                result.append(
                    _PREFETCH_TAG + _proxy_url(config, "prefetch", abs_url, track=track) + ending
                )
                continue

        result.append(line)

    return "".join(result)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


def _resolve(url: str, base_url: str) -> str:
    if url.startswith(("http://", "https://")):
        return url
    return urljoin(base_url, url)


def _proxy_url(
    config: RewriteConfig,
    kind: str,
    upstream: str,
    *,
    track: str | None = None,
) -> str:
    encoded = quote(upstream, safe="")
    if kind == "m3u8":
        url = f"{config.proxy_base}/m3u8?u={encoded}"
        if track:
            url += f"&track={track}"
        return url
    url = f"{config.proxy_base}/s?u={encoded}&k={kind}"
    if track:
        url += f"&track={track}"
    return url


def _rewrite_uri_attr(
    line: str,
    base_url: str,
    config: RewriteConfig,
    kind: str,
    *,
    track: str | None = None,
) -> str:
    stripped = line.rstrip("\r\n")
    ending = line[len(stripped) :]
    m = _URI_ATTR_RE.search(stripped)
    if m is None:
        return line
    old_url = m.group(1)
    abs_url = _resolve(old_url, base_url)
    proxy_url = _proxy_url(config, kind, abs_url, track=track)
    return stripped[: m.start(1)] + proxy_url + stripped[m.end(1) :] + ending


def _synthesize_master(
    upstream_url: str,
    config: RewriteConfig,
    hints: VariantHints | None,
) -> str:
    encoded = quote(upstream_url, safe="")
    audio_uri = f"{config.proxy_base}/m3u8?u={encoded}&track=audio"
    video_uri = f"{config.proxy_base}/m3u8?u={encoded}&track=video"

    codecs = _safe_codecs(hints.codecs if hints else None)
    bandwidth = hints.bandwidth if hints and hints.bandwidth else _DEFAULT_BANDWIDTH
    resolution_attr = ""
    if hints and hints.resolution and _is_valid_resolution(hints.resolution):
        resolution_attr = f",RESOLUTION={hints.resolution}"

    return (
        "#EXTM3U\n"
        "#EXT-X-VERSION:6\n"
        f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Audio",'
        f'DEFAULT=YES,AUTOSELECT=YES,URI="{audio_uri}"\n'
        f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth}"
        f'{resolution_attr},CODECS="{codecs}",AUDIO="aac"\n'
        f"{video_uri}\n"
    )


def _safe_codecs(codecs: str | None) -> str:
    if not codecs:
        return _DEFAULT_CODECS
    if not _CODEC_CHARS_RE.match(codecs):
        return _DEFAULT_CODECS
    return codecs


def _is_valid_resolution(value: str) -> bool:
    parts = value.split("x")
    if len(parts) != 2:
        return False
    return parts[0].isdigit() and parts[1].isdigit()


def _preload_hint_kind(stripped: str) -> str:
    m = _TYPE_ATTR_RE.search(stripped)
    if m is not None and m.group(1).upper() == "MAP":
        return "init"
    return "part"
