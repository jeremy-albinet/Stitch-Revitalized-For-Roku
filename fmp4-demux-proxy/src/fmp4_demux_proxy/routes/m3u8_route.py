"""HLS endpoint with filtered ladders and explicit reverse-proxy addressing."""

from __future__ import annotations

import asyncio
import json
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from aiohttp import web

from fmp4_demux_proxy import fmp4
from fmp4_demux_proxy import manifest as mf
from fmp4_demux_proxy.config import validate_proxy_base
from fmp4_demux_proxy.routes.segment_route import _track_map
from fmp4_demux_proxy.upstream import (
    CONFIG_KEY,
    INSPECTION_SLOTS_KEY,
    fetch_upstream,
    validate_upstream_url,
)


def _proxy_base_from_request(request: web.Request) -> str:
    # Forwarded headers are untrusted. Reverse-proxy operators set PROXY_PUBLIC_URL.
    try:
        return validate_proxy_base(f"{request.scheme}://{request.host}")
    except ValueError as exc:
        raise web.HTTPBadRequest(text="Invalid proxy host; configure PROXY_PUBLIC_URL") from exc


def _parse_hints(request: web.Request) -> mf.VariantHints | None:
    codecs = request.query.get("codecs") or None
    resolution = request.query.get("res") or None
    raw = request.query.get("bw")
    bandwidth = int(raw) if raw and raw.isdigit() and len(raw) < 12 else None
    if codecs is None and resolution is None and bandwidth is None:
        return None
    return mf.VariantHints(codecs=codecs, bandwidth=bandwidth, resolution=resolution)


def _parse_variants(request: web.Request) -> tuple[str, ...] | None:
    single = request.query.get("variant")
    raw = request.query.get("variants")
    if single and raw:
        raise web.HTTPBadRequest(text="Use variant or variants, not both")
    if single:
        selected = [single]
    elif raw:
        if len(raw.encode("utf-8")) > 32 * 1024:
            raise web.HTTPBadRequest(text="Variant selection exceeds 32 KiB")
        try:
            selected = json.loads(raw)
        except ValueError as exc:
            raise web.HTTPBadRequest(text="Invalid variants JSON") from exc
    else:
        return None
    if (
        not isinstance(selected, list)
        or not 1 <= len(selected) <= 32
        or any(
            not isinstance(value, str) or not value.startswith(("http://", "https://"))
            for value in selected
        )
        or len(set(selected)) != len(selected)
    ):
        raise web.HTTPBadRequest(text="Expected 1-32 distinct absolute variant URLs")
    return tuple(selected)


def _reload_url(upstream: str, request: web.Request) -> str:
    reload_params: dict[str, str] = {}
    for name in ("_HLS_msn", "_HLS_part", "_HLS_skip"):
        value = request.query.get(name)
        if value is None:
            continue
        valid = (
            value in {"YES", "v2"} if name == "_HLS_skip" else (value.isdigit() and len(value) < 20)
        )
        if not valid:
            raise web.HTTPBadRequest(text="Invalid HLS reload parameter")
        reload_params[name] = value
    if not reload_params:
        return upstream
    parts = urlsplit(upstream)
    params = [
        (key, value)
        for key, value in parse_qsl(parts.query, keep_blank_values=True)
        if key not in reload_params
    ]
    params.extend(reload_params.items())
    return urlunsplit(parts._replace(query=urlencode(params)))


def _parse_demux_variants(request: web.Request) -> tuple[str, ...] | None:
    raw = request.query.get("demuxVariants")
    if raw is None:
        return None
    if len(raw.encode("utf-8")) > 32 * 1024:
        raise web.HTTPBadRequest(text="Demux selection exceeds 32 KiB")
    try:
        selected = json.loads(raw)
    except ValueError as exc:
        raise web.HTTPBadRequest(text="Invalid demuxVariants JSON") from exc
    if (
        not isinstance(selected, list)
        or len(selected) > 32
        or any(
            not isinstance(value, str) or not value.startswith(("http://", "https://"))
            for value in selected
        )
        or len(set(selected)) != len(selected)
    ):
        raise web.HTTPBadRequest(text="Expected 0-32 distinct absolute demux variant URLs")
    return tuple(selected)


async def _inspect_master_variants(
    request: web.Request,
    entries: dict[int, tuple[int, str, dict[str, str]]],
    *,
    strict: bool = False,
) -> tuple[str, ...]:
    cfg = request.app[CONFIG_KEY]
    if len(entries) > 32:
        raise mf.ManifestError("Master has too many variants to inspect; specify a selection")

    async def inspect_body(uri: str) -> str | None:
        result = await fetch_upstream(request.app, uri, limit=cfg.max_manifest_bytes)
        try:
            variant = result.body.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise mf.ManifestError("Variant playlist is not UTF-8") from exc
        if not variant.startswith("#EXTM3U") or mf.classify(variant) != mf.ManifestKind.VARIANT:
            raise mf.ManifestError("Master entry is not a media playlist")
        init = mf.first_init(variant, result.final_url)
        if init is None:
            return None
        tracks = await _track_map(request.app, *init)
        # Fresh video declarations cannot authorize an unknown or audio-only current init.
        if strict and (
            sum(value == "video" for value in tracks.values()) != 1
            or sum(value == "audio" for value in tracks.values()) > 1
            or any(value not in {"video", "audio"} for value in tracks.values())
        ):
            raise mf.ManifestError(
                "Selected rendition init requires one video and at most one audio"
            )
        return (
            uri
            if (
                sum(value == "video" for value in tracks.values()) == 1
                and sum(value == "audio" for value in tracks.values()) == 1
            )
            else None
        )

    async def inspect(uri: str) -> str | None:
        async with request.app[INSPECTION_SLOTS_KEY]:
            return await inspect_body(uri)

    tasks = [asyncio.create_task(inspect(entry[1])) for entry in entries.values()]
    try:
        results = await asyncio.gather(*tasks)
    finally:
        # gather does not cancel siblings on a failed fetch. Do not leave detached
        # inspections running after their request has failed or timed out.
        for task in tasks:
            if not task.done():
                task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
    return tuple(uri for uri in results if uri is not None)


async def m3u8_handler(request: web.Request) -> web.Response:
    cfg = request.app[CONFIG_KEY]
    upstream = request.query.get("u")
    if not upstream:
        raise web.HTTPBadRequest(text="Missing upstream playlist URL")
    raw_track = request.query.get("track")
    track = raw_track or None
    if track is not None and track not in {"video", "audio"}:
        raise web.HTTPBadRequest(text="Invalid playlist track")
    mode = request.query.get("mode", "demux")
    if mode not in {"demux", "passthrough"}:
        raise web.HTTPBadRequest(text="Invalid playlist mode")
    variants = _parse_variants(request)
    demux_variants = _parse_demux_variants(request)
    result = await fetch_upstream(
        request.app, _reload_url(upstream, request), limit=cfg.max_manifest_bytes
    )
    try:
        body = result.body.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise web.HTTPBadGateway(text="Upstream playlist is not UTF-8") from exc
    if not body.startswith("#EXTM3U") or mf.classify(body) == mf.ManifestKind.UNKNOWN:
        raise web.HTTPBadGateway(text="Upstream is not a supported HLS playlist")
    try:
        if mf.classify(body) == mf.ManifestKind.MASTER:
            entries = mf.master_entries(body, result.final_url, variants)
            if mode == "passthrough":
                if demux_variants:
                    raise mf.ManifestError("Passthrough mode cannot select demux variants")
                demux_variants = ()
            elif demux_variants is None:
                demux_variants = await _inspect_master_variants(request, entries)
        elif mode == "demux" and mf.classify(body) == mf.ManifestKind.VARIANT:
            init = mf.first_init(body, result.final_url)
            if init is None:
                if track is not None:
                    raise mf.ManifestError("Demuxed rendition requires an fMP4 init map")
                mode = "passthrough"  # TS/packed audio does not require demux.
            elif track is None:
                tracks = await _track_map(request.app, *init)
                if (
                    sum(value == "video" for value in tracks.values()) != 1
                    or sum(value == "audio" for value in tracks.values()) != 1
                ):
                    # Already-separated CMAF is retained as an ordinary media playlist.
                    mode = "passthrough"
        rewritten = mf.rewrite(
            body,
            result.final_url,
            mf.RewriteConfig(
                cfg.proxy_public_url or _proxy_base_from_request(request),
                max_output_bytes=cfg.max_manifest_bytes * 4,
            ),
            track=track,
            hints=_parse_hints(request),
            mode=mode,
            variants=variants,
            demux_variants=demux_variants or (),
        )
    except (mf.ManifestError, fmp4.Fmp4Error) as exc:
        raise web.HTTPBadGateway(text=f"Unsupported HLS input: {exc}") from exc
    return web.Response(
        body=rewritten.encode("utf-8"),
        content_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-store"},
    )


def _unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field")
        result[key] = value
    return result


def _parse_selections(request: web.Request) -> tuple[mf.VariantSelection, ...]:
    allowed = {"u", "selections", "_HLS_msn", "_HLS_part", "_HLS_skip"}
    if any(key not in allowed or len(request.query.getall(key)) != 1 for key in request.query):
        raise web.HTTPBadRequest(text="Invalid selected-master query fields")
    raw = request.query.get("selections")
    if raw is None or len(raw.encode("utf-8")) > 32 * 1024:
        raise web.HTTPBadRequest(text="Missing or oversized rendition selections")
    try:
        value = json.loads(raw, object_pairs_hook=_unique_json_object)
        return mf.parse_selections(value)
    except (ValueError, RecursionError) as exc:
        raise web.HTTPBadRequest(text="Invalid rendition selections") from exc


async def selected_m3u8_handler(request: web.Request) -> web.Response:
    """Fresh master selection: old services lack this endpoint and fail closed with 404."""
    selections = _parse_selections(request)
    cfg = request.app[CONFIG_KEY]
    upstream = request.query.get("u")
    if not upstream:
        raise web.HTTPBadRequest(text="Missing upstream playlist URL")
    result = await fetch_upstream(
        request.app, _reload_url(upstream, request), limit=cfg.max_manifest_bytes
    )
    try:
        body = result.body.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise web.HTTPBadGateway(text="Upstream playlist is not UTF-8") from exc
    if not body.startswith("#EXTM3U") or mf.classify(body) != mf.ManifestKind.MASTER:
        raise web.HTTPBadGateway(text="Selected renditions require an upstream master playlist")
    try:
        variants = mf.selected_master_urls(body, result.final_url, selections)
        for uri in variants:
            validate_upstream_url(
                uri, cfg.upstream_host_allowlist, allow_unsafe=cfg.allow_unsafe_upstream
            )
        entries = mf.master_entries(body, result.final_url, variants)
        demux_variants = await _inspect_master_variants(request, entries, strict=True)
        rewritten = mf.rewrite(
            body,
            result.final_url,
            mf.RewriteConfig(
                cfg.proxy_public_url or _proxy_base_from_request(request),
                max_output_bytes=cfg.max_manifest_bytes * 4,
            ),
            variants=variants,
            demux_variants=demux_variants,
        )
    except (mf.ManifestError, fmp4.Fmp4Error) as exc:
        raise web.HTTPBadGateway(text=f"Unsupported HLS input: {exc}") from exc
    return web.Response(
        body=rewritten.encode("utf-8"),
        content_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-store"},
    )
