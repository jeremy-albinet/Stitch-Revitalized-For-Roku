"""HLS rewriting that preserves rendition relationships and exact init/range identity."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum
from urllib.parse import quote, urljoin

from fmp4_demux_proxy.upstream import ByteRange

_DEFAULT_BANDWIDTH = 4_000_000
_CODEC_CHARS_RE = re.compile(r"^[A-Za-z0-9.,_\-]+$")
_ATTR_RE = re.compile(r'([A-Z0-9-]+)\s*=\s*("[^"]*"|[^,]*)')
_URI_ATTR_RE = re.compile(r'URI\s*=\s*"([^"]*)"')
_PREFETCH_TAG = "#EXT-X-TWITCH-PREFETCH:"


class ManifestError(ValueError):
    """Malformed or unsupported addressing must never produce corrupt media."""


class _Output(list[str]):
    """Bound expansion before repeated init URLs can accumulate a huge playlist."""

    def __init__(self, limit: int) -> None:
        super().__init__()
        self.limit = limit
        self.size = 0

    def append(self, line: str) -> None:
        self.size += len(line.encode("utf-8"))
        if self.size > self.limit:
            raise ManifestError("Rewritten playlist exceeds size limit")
        super().append(line)


class ManifestKind(StrEnum):
    MASTER = "master"
    VARIANT = "variant"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class RewriteConfig:
    proxy_base: str
    max_output_bytes: int = 8 * 1024 * 1024

    def __post_init__(self) -> None:
        object.__setattr__(self, "proxy_base", self.proxy_base.rstrip("/"))


@dataclass(frozen=True)
class VariantHints:
    codecs: str | None = None
    bandwidth: int | None = None
    resolution: str | None = None


type AttributeIdentity = tuple[tuple[str, str], ...]


@dataclass(frozen=True, order=True)
class GroupSelection:
    attributes: AttributeIdentity
    has_uri: bool


@dataclass(frozen=True)
class VariantSelection:
    attributes: AttributeIdentity
    groups: tuple[GroupSelection, ...]


def _selection_attributes(value: object) -> AttributeIdentity:
    if not isinstance(value, dict) or len(value) > 64:
        raise ManifestError("Invalid selection attribute map")
    for key, member in value.items():
        if (
            not isinstance(key, str)
            or not re.fullmatch(r"[A-Z0-9-]{1,128}", key)
            or key in {"URL", "URI", "SEPARATE-AUDIO"}
            or not isinstance(member, str)
            or len(member) > 4096
        ):
            raise ManifestError("Invalid selection attribute name or value")
    return tuple(sorted(value.items()))


def parse_selections(value: object) -> tuple[VariantSelection, ...]:
    """Validate the URL-free caller contract before fetching any upstream resource."""
    if not isinstance(value, list) or not 1 <= len(value) <= 32:
        raise ManifestError("Expected 1-32 rendition selections")
    selections = []
    for item in value:
        if not isinstance(item, dict) or set(item) != {"attributes", "groups"}:
            raise ManifestError("Invalid rendition selection fields")
        groups = item["groups"]
        if not isinstance(groups, list) or len(groups) > 64:
            raise ManifestError("Invalid rendition group list")
        members = []
        for group in groups:
            if (
                not isinstance(group, dict)
                or set(group) != {"attributes", "hasUri"}
                or type(group["hasUri"]) is not bool
            ):
                raise ManifestError("Invalid rendition group fields")
            members.append(
                GroupSelection(_selection_attributes(group["attributes"]), group["hasUri"])
            )
        selections.append(
            VariantSelection(_selection_attributes(item["attributes"]), tuple(sorted(members)))
        )
    if len(set(selections)) != len(selections):
        raise ManifestError("Duplicate rendition selections")
    return tuple(selections)


def selected_master_urls(
    body: str, base_url: str, selections: tuple[VariantSelection, ...]
) -> tuple[str, ...]:
    """Resolve strict identities only to unique entries in this freshly fetched master."""
    media: dict[tuple[str, str], list[GroupSelection]] = {}
    for line in body.splitlines():
        if not line.startswith("#EXT-X-MEDIA:"):
            continue
        member = attributes(line)
        kind, group_id = member.get("TYPE"), member.get("GROUP-ID")
        if kind is not None and group_id is not None:
            media.setdefault((kind, group_id), []).append(
                GroupSelection(
                    tuple(sorted((key, value) for key, value in member.items() if key != "URI")),
                    "URI" in member,
                )
            )
    identities: dict[VariantSelection, list[str]] = {}
    url_counts: dict[str, int] = {}
    for _, uri, attrs in master_entries(body, base_url).values():
        url_counts[uri] = url_counts.get(uri, 0) + 1
        groups = []
        for kind in ("AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS"):
            group_id = attrs.get(kind)
            if group_id is not None and group_id != "NONE":
                members = media.get((kind, group_id), [])
                if len(groups) + len(members) > 64:
                    # Cannot match the bounded caller contract; avoid expanding a huge group.
                    break
                groups.extend(members)
        else:
            identity = VariantSelection(tuple(sorted(attrs.items())), tuple(sorted(groups)))
            identities.setdefault(identity, []).append(uri)
    selected = []
    for selection in selections:
        matches = identities.get(selection, [])
        if len(matches) != 1:
            raise ManifestError(
                "Selected rendition metadata is missing or ambiguous; refresh playback"
            )
        if url_counts[matches[0]] != 1:
            raise ManifestError("Selected rendition URL identifies multiple master entries")
        selected.append(matches[0])
    if len(set(selected)) != len(selected):
        raise ManifestError("Selected rendition URLs are not distinct")
    return tuple(selected)


def attributes(line: str) -> dict[str, str]:
    return {
        match[1]: match[2].strip().strip('"') for match in _ATTR_RE.finditer(line.split(":", 1)[-1])
    }


def classify(body: str) -> ManifestKind:
    lines = body.splitlines()
    if any(line.startswith(("#EXT-X-STREAM-INF:", "#EXT-X-I-FRAME-STREAM-INF:")) for line in lines):
        return ManifestKind.MASTER
    if any(
        line.startswith(
            (
                "#EXTINF:",
                "#EXT-X-MAP:",
                "#EXT-X-TARGETDURATION:",
                "#EXT-X-PART:",
                "#EXT-X-PRELOAD-HINT:",
                "#EXT-X-RENDITION-REPORT:",
                _PREFETCH_TAG,
            )
        )
        for line in lines
    ):
        return ManifestKind.VARIANT
    if any(line.startswith("#EXT-X-MEDIA:") for line in lines):
        return ManifestKind.MASTER
    return ManifestKind.UNKNOWN


def _proxy_url(
    config: RewriteConfig,
    kind: str,
    upstream: str,
    *,
    track: str | None = None,
    mode: str = "demux",
    init: str | None = None,
    byte_range: ByteRange | None = None,
    init_range: ByteRange | None = None,
) -> str:
    path = "m3u8" if kind == "m3u8" else "s"
    params = [("u", upstream)]
    if path == "s":
        params.append(("k", kind))
    if track:
        params.append(("track", track))
    if mode != "demux":
        params.append(("mode", mode))
    if init:
        params.append(("i", init))
    if byte_range:
        params.append(("r", byte_range.query))
    if init_range:
        params.append(("ir", init_range.query))
    return (
        config.proxy_base
        + "/"
        + path
        + "?"
        + "&".join(key + "=" + quote(value, safe="") for key, value in params)
    )


def _replace_uri(line: str, uri: str) -> str:
    match = _URI_ATTR_RE.search(line)
    if not match:
        raise ManifestError("Expected a quoted URI attribute")
    return line[: match.start(1)] + uri + line[match.end(1) :]


def _remove_attr(line: str, name: str) -> str:
    stripped = line.rstrip("\r\n")
    prefix, raw_attrs = stripped.split(":", 1)
    remaining = [match[0] for match in _ATTR_RE.finditer(raw_attrs) if match[1] != name]
    return prefix + ":" + ",".join(remaining) + line[len(stripped) :]


def _range(
    raw: str | None, url: str, previous: tuple[str, ByteRange] | None = None
) -> ByteRange | None:
    if raw is None:
        return None
    if len(raw) > 64 or not re.fullmatch(r"[0-9]+(?:@[0-9]+)?", raw):
        raise ManifestError("Invalid playlist byte range")
    fields = raw.split("@")
    length = int(fields[0])
    if len(fields) == 2:
        offset = int(fields[1])
    elif previous is not None and previous[0] == url:
        offset = previous[1].offset + previous[1].length
    else:
        raise ManifestError("Implicit byte range needs the previous range on the same resource")
    try:
        return ByteRange(offset, length)
    except ValueError as exc:
        raise ManifestError("Invalid playlist byte range") from exc


def first_init(body: str, base_url: str) -> tuple[str, ByteRange | None] | None:
    for line in body.splitlines():
        if line.startswith("#EXT-X-MAP:"):
            attrs = attributes(line)
            if not attrs.get("URI"):
                raise ManifestError("Init map is missing its URI")
            uri = urljoin(base_url, attrs["URI"])
            return uri, _range(attrs.get("BYTERANGE"), uri)
    return None


def rewrite(
    body: str,
    base_url: str,
    config: RewriteConfig,
    *,
    track: str | None = None,
    hints: VariantHints | None = None,
    mode: str = "demux",
    variants: tuple[str, ...] | None = None,
    demux_variants: tuple[str, ...] = (),
) -> str:
    kind = classify(body)
    if kind == ManifestKind.UNKNOWN:
        return body
    for line in body.splitlines():
        if line.startswith("#EXT-X-VERSION:"):
            value = line.split(":", 1)[1].strip()
            if not value.isdigit() or len(value) > 8 or int(value) < 1:
                raise ManifestError("Invalid playlist version")
    if kind == ManifestKind.MASTER:
        return _rewrite_master(
            body, base_url, config, mode=mode, variants=variants, demux_variants=demux_variants
        )
    if variants is not None:
        raise ManifestError("Variant selection requires a master playlist")
    if mode == "demux" and track is None:
        return _synthesize_master(base_url, config, hints)
    return _rewrite_variant(body, base_url, config, track=track, mode=mode)


def master_entries(
    body: str, base_url: str, variants: tuple[str, ...] | None = None
) -> dict[int, tuple[int, str, dict[str, str]]]:
    lines = body.splitlines(keepends=True)
    # Bind each STREAM-INF to its next non-comment URI. Discard orphan declarations.
    entries: dict[int, tuple[int, str, dict[str, str]]] = {}
    for index, line in enumerate(lines):
        if not line.startswith("#EXT-X-STREAM-INF:"):
            continue
        for uri_index in range(index + 1, len(lines)):
            uri_line = lines[uri_index].strip()
            if uri_line.startswith("#EXT-X-STREAM-INF:"):
                break
            if uri_line and not uri_line.startswith("#"):
                uri = urljoin(base_url, uri_line)
                if variants is None or uri in variants:
                    entries[index] = (uri_index, uri, attributes(line))
                break
    if variants is not None:
        found = {entry[1] for entry in entries.values()}
        if not found or found != set(variants):
            raise ManifestError("Selected variant URL does not appear in the upstream master")
    return entries


def _rewrite_master(
    body: str,
    base_url: str,
    config: RewriteConfig,
    *,
    mode: str,
    variants: tuple[str, ...] | None,
    demux_variants: tuple[str, ...],
) -> str:
    lines = body.splitlines(keepends=True)
    entries = master_entries(body, base_url, variants)
    if not set(demux_variants) <= {entry[1] for entry in entries.values()}:
        raise ManifestError("Demux selection is not a subset of selected variants")
    referenced = {
        value
        for _, _, attrs in entries.values()
        for name, value in attrs.items()
        if name in {"AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS"}
    }
    external_audio = {
        attributes(line).get("GROUP-ID")
        for line in lines
        if line.startswith("#EXT-X-MEDIA:")
        and attributes(line).get("TYPE") == "AUDIO"
        and attributes(line).get("URI")
    }
    existing_groups = {
        attributes(line).get("GROUP-ID") for line in lines if line.startswith("#EXT-X-MEDIA:")
    }
    result = _Output(config.max_output_bytes)
    skip_uris: set[int] = set()
    added_audio = False
    for index, line in enumerate(lines):
        if index in skip_uris:
            continue
        if line.startswith("#EXT-X-STREAM-INF:"):
            if index not in entries:
                # Skip the omitted entry's URI but retain comments and global tags.
                for uri_index in range(index + 1, len(lines)):
                    if lines[uri_index].startswith("#EXT-X-STREAM-INF:"):
                        break
                    if lines[uri_index].strip() and not lines[uri_index].startswith("#"):
                        skip_uris.add(uri_index)
                        break
                continue
            uri_index, uri, attrs = entries[index]
            skip_uris.add(uri_index)
            ending = "\r\n" if line.endswith("\r\n") else "\n"
            uri_ending = lines[uri_index][len(lines[uri_index].rstrip("\r\n")) :]
            # CODECS describes elementary streams, not whether they use TS or CMAF.
            bundled = mode != "passthrough" and uri in demux_variants
            if bundled:
                added_audio = True
                if attrs.get("AUDIO") in external_audio:
                    result.append(line)
                    result.append(_proxy_url(config, "m3u8", uri, track="video") + uri_ending)
                    continue
                group = f"stitch-demux-{index}"
                while group in existing_groups:
                    group += "-x"
                audio_uri = _proxy_url(config, "m3u8", uri, track="audio")
                result.append(
                    f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="{group}",NAME="Audio",'
                    f'DEFAULT=YES,AUTOSELECT=YES,URI="{audio_uri}"' + ending
                )
                info = _remove_attr(line.rstrip("\r\n"), "AUDIO") + f',AUDIO="{group}"'
                result.append(info + ending)
                result.append(_proxy_url(config, "m3u8", uri, track="video") + uri_ending)
            else:
                result.append(line)
                result.append(_proxy_url(config, "m3u8", uri, mode="passthrough") + uri_ending)
            continue
        if line.startswith("#EXT-X-MEDIA:"):
            attrs = attributes(line)
            if variants is not None and attrs.get("GROUP-ID") not in referenced:
                continue
            if attrs.get("URI"):
                line = _replace_uri(
                    line,
                    _proxy_url(config, "m3u8", urljoin(base_url, attrs["URI"]), mode="passthrough"),
                )
        elif line.startswith("#EXT-X-I-FRAME-STREAM-INF:"):
            if variants is not None:
                continue
            attrs = attributes(line)
            if attrs.get("URI"):
                line = _replace_uri(
                    line,
                    _proxy_url(config, "m3u8", urljoin(base_url, attrs["URI"]), mode="passthrough"),
                )
        elif line.startswith(("#EXT-X-SESSION-DATA:", "#EXT-X-SESSION-KEY:")):
            attrs = attributes(line)
            if attrs.get("URI"):
                line = _replace_uri(line, urljoin(base_url, attrs["URI"]))
        result.append(line)
    if added_audio:
        for index, line in enumerate(result):
            if line.startswith("#EXT-X-VERSION:"):
                try:
                    version = int(line.split(":", 1)[1].strip())
                except ValueError as exc:
                    raise ManifestError("Invalid playlist version") from exc
                if version < 6:
                    ending = "\r\n" if line.endswith("\r\n") else "\n"
                    result[index] = "#EXT-X-VERSION:6" + ending
                break
        else:
            ending = "\r\n" if body.startswith("#EXTM3U\r\n") else "\n"
            result.insert(1, "#EXT-X-VERSION:6" + ending)
    return "".join(result)


def _rewrite_variant(
    body: str, base_url: str, config: RewriteConfig, *, track: str | None, mode: str
) -> str:
    result = _Output(config.max_output_bytes)
    init: str | None = None
    init_range: ByteRange | None = None
    pending_range: str | None = None
    previous_media: tuple[str, ByteRange] | None = None
    previous_part: tuple[str, ByteRange] | None = None
    for line in body.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped) :]
        if stripped.startswith("#EXT-X-BYTERANGE:"):
            pending_range = stripped.split(":", 1)[1]
            continue  # Upstream ranges no longer describe the separately served output.
        if stripped.startswith("#EXT-X-KEY:"):
            attrs = attributes(stripped)
            if mode == "demux" and attrs.get("METHOD") != "NONE":
                raise ManifestError("Encrypted fragments cannot be demuxed")
            if attrs.get("URI"):
                line = _replace_uri(
                    line,
                    _proxy_url(config, "key", urljoin(base_url, attrs["URI"]), mode="passthrough"),
                )
        elif stripped.startswith("#EXT-X-MAP:"):
            attrs = attributes(stripped)
            if not attrs.get("URI"):
                raise ManifestError("Init map is missing its URI")
            init = urljoin(base_url, attrs["URI"])
            init_range = _range(attrs.get("BYTERANGE"), init)
            line = _remove_attr(line, "BYTERANGE")
            line = _replace_uri(
                line,
                _proxy_url(config, "init", init, track=track, mode=mode, byte_range=init_range),
            )
        elif stripped.startswith(("#EXT-X-PART:", "#EXT-X-PRELOAD-HINT:")):
            attrs = attributes(stripped)
            if not attrs.get("URI"):
                raise ManifestError("Part or preload is missing its URI")
            uri = urljoin(base_url, attrs["URI"])
            kind = "init" if attrs.get("TYPE") == "MAP" else "part"
            raw_range = attrs.get("BYTERANGE")
            if "BYTERANGE-START" in attrs:
                if "BYTERANGE-LENGTH" not in attrs:
                    raise ManifestError("Open-ended preload byte ranges are unsupported")
                raw_range = attrs["BYTERANGE-LENGTH"] + "@" + attrs["BYTERANGE-START"]
            byte_range = _range(raw_range, uri, previous_part)
            if kind == "part":
                previous_part = (uri, byte_range) if byte_range else None
            for name in ("BYTERANGE", "BYTERANGE-START", "BYTERANGE-LENGTH"):
                line = _remove_attr(line, name)
            line = _replace_uri(
                line,
                _proxy_url(
                    config,
                    kind,
                    uri,
                    track=track,
                    mode=mode,
                    byte_range=byte_range,
                    init=init if kind != "init" else None,
                    init_range=init_range if kind != "init" else None,
                ),
            )
        elif stripped.startswith("#EXT-X-RENDITION-REPORT:"):
            attrs = attributes(stripped)
            if attrs.get("URI"):
                line = _replace_uri(
                    line,
                    _proxy_url(
                        config, "m3u8", urljoin(base_url, attrs["URI"]), track=track, mode=mode
                    ),
                )
        elif stripped.startswith(_PREFETCH_TAG):
            uri = urljoin(base_url, stripped[len(_PREFETCH_TAG) :])
            line = (
                _PREFETCH_TAG
                + _proxy_url(
                    config,
                    "prefetch",
                    uri,
                    track=track,
                    mode=mode,
                    init=init,
                    init_range=init_range,
                )
                + ending
            )
        elif stripped and not stripped.startswith("#"):
            uri = urljoin(base_url, stripped)
            byte_range = _range(pending_range, uri, previous_media)
            previous_media = (uri, byte_range) if byte_range else None
            pending_range = None
            line = (
                _proxy_url(
                    config,
                    "media",
                    uri,
                    track=track,
                    mode=mode,
                    init=init,
                    init_range=init_range,
                    byte_range=byte_range,
                )
                + ending
            )
        result.append(line)
    if pending_range is not None:
        raise ManifestError("Byte range has no following media URI")
    return "".join(result)


def _synthesize_master(upstream_url: str, config: RewriteConfig, hints: VariantHints | None) -> str:
    codecs = hints.codecs if hints else None
    # CODECS is optional in HLS. Unknown metadata must not mislabel HEVC as AVC.
    codec_attr = f',CODECS="{codecs}"' if codecs and _CODEC_CHARS_RE.fullmatch(codecs) else ""
    bandwidth = hints.bandwidth if hints and hints.bandwidth else _DEFAULT_BANDWIDTH
    resolution = (
        f",RESOLUTION={hints.resolution}"
        if hints and hints.resolution and re.fullmatch(r"[0-9]+x[0-9]+", hints.resolution)
        else ""
    )
    audio_uri = _proxy_url(config, "m3u8", upstream_url, track="audio")
    video_uri = _proxy_url(config, "m3u8", upstream_url, track="video")
    return (
        "#EXTM3U\n#EXT-X-VERSION:6\n"
        f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Audio",'
        f'DEFAULT=YES,AUTOSELECT=YES,URI="{audio_uri}"\n'
        f'#EXT-X-STREAM-INF:BANDWIDTH={bandwidth}{resolution}{codec_attr},AUDIO="aac"\n'
        f"{video_uri}\n"
    )
