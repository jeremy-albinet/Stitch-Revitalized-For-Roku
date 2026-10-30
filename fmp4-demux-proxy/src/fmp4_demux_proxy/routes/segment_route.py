"""Track-separated media with exact init identity and bounded shared fetches."""

from __future__ import annotations

import asyncio
import logging
from collections import OrderedDict
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Final

from aiohttp import web

from fmp4_demux_proxy import fmp4
from fmp4_demux_proxy.upstream import (
    CONFIG_KEY,
    ByteRange,
    UpstreamData,
    fetch_upstream,
    parse_byte_range,
    validate_upstream_url,
)

logger = logging.getLogger(__name__)
type FetchKey = tuple[str, ByteRange | None]
_MAX_CACHE_ENTRIES = 50
_MAX_TRACK_MAPS = 100


@dataclass
class SegmentStore:
    cache: OrderedDict[FetchKey, UpstreamData] = field(default_factory=OrderedDict)
    track_maps: OrderedDict[FetchKey, dict[int, fmp4.TrackKind]] = field(
        default_factory=OrderedDict
    )
    pending: dict[FetchKey, asyncio.Task[UpstreamData]] = field(default_factory=dict)
    cached_bytes: int = 0


STORE_KEY: Final = web.AppKey("segment_store", SegmentStore)


async def segment_store_cleanup_ctx(app: web.Application) -> AsyncIterator[None]:
    yield
    tasks = list(app[STORE_KEY].pending.values())
    for task in tasks:
        task.cancel()
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)


async def _fetch_cached(
    app: web.Application, upstream: str, byte_range: ByteRange | None
) -> UpstreamData:
    store = app[STORE_KEY]
    cfg = app[CONFIG_KEY]
    key = (upstream, byte_range)
    if key in store.cache:
        store.cache.move_to_end(key)
        return store.cache[key]
    task = store.pending.get(key)
    if task is None:
        if len(store.pending) >= cfg.max_inflight_requests:
            raise web.HTTPServiceUnavailable(text="Proxy is busy; retry shortly")

        async def fetch_and_cache() -> UpstreamData:
            try:
                result = await fetch_upstream(
                    app, upstream, limit=cfg.max_segment_bytes, byte_range=byte_range
                )
                if len(result.body) <= cfg.segment_cache_bytes:
                    store.cache[key] = result
                    store.cached_bytes += len(result.body)
                    while (
                        len(store.cache) > _MAX_CACHE_ENTRIES
                        or store.cached_bytes > cfg.segment_cache_bytes
                    ):
                        _, evicted = store.cache.popitem(last=False)
                        store.cached_bytes -= len(evicted.body)
                return result
            finally:
                store.pending.pop(key, None)

        task = asyncio.create_task(fetch_and_cache())
        # A disconnected client must not leave an unobserved failed task exception.
        task.add_done_callback(lambda done: done.exception() if not done.cancelled() else None)
        store.pending[key] = task
    return await asyncio.shield(task)


async def _track_map(
    app: web.Application, init_url: str, init_range: ByteRange | None
) -> dict[int, fmp4.TrackKind]:
    store = app[STORE_KEY]
    identity = (init_url, init_range)
    cached = store.track_maps.get(identity)
    if cached is not None:
        store.track_maps.move_to_end(identity)
        return cached
    init = await _fetch_cached(app, init_url, init_range)
    tracks = fmp4.extract_track_map(init.body)
    if not tracks:
        raise fmp4.Fmp4Error("Init segment contains no valid tracks")
    store.track_maps[identity] = tracks
    store.track_maps.move_to_end(identity)
    if len(store.track_maps) > _MAX_TRACK_MAPS:
        store.track_maps.popitem(last=False)
    return tracks


async def segment_handler(request: web.Request) -> web.Response:
    cfg = request.app[CONFIG_KEY]
    upstream = request.query.get("u")
    kind = request.query.get("k")
    track = request.query.get("track")
    mode = request.query.get("mode", "demux")
    if not upstream or kind not in {"init", "media", "part", "prefetch", "key"}:
        raise web.HTTPBadRequest(text="Missing or invalid segment URL/kind")
    if mode not in {"demux", "passthrough"}:
        raise web.HTTPBadRequest(text="Invalid segment mode")
    if mode == "demux" and track not in {"video", "audio"}:
        raise web.HTTPBadRequest(text="Missing or invalid segment track")
    validate_upstream_url(
        upstream, cfg.upstream_host_allowlist, allow_unsafe=cfg.allow_unsafe_upstream
    )
    input_range = parse_byte_range(request.query.get("r"))
    init_range = parse_byte_range(request.query.get("ir"))
    init_url = upstream if kind == "init" else request.query.get("i")
    if mode == "demux":
        if not init_url:
            raise web.HTTPBadRequest(text="Media requires an exact init segment reference")
        validate_upstream_url(
            init_url, cfg.upstream_host_allowlist, allow_unsafe=cfg.allow_unsafe_upstream
        )

    try:
        if mode == "passthrough":
            result = await _fetch_cached(request.app, upstream, input_range)
            rewritten = result.body
            content_type = result.content_type
        else:
            keep: fmp4.TrackKind = "video" if track == "video" else "audio"
            tracks = await _track_map(
                request.app, init_url, input_range if kind == "init" else init_range
            )
            if sum(value == keep for value in tracks.values()) != 1:
                raise fmp4.Fmp4Error("Init segment must contain exactly one requested track")
            result = await _fetch_cached(request.app, upstream, input_range)
            rewritten = (
                fmp4.split_moov(result.body, tracks, keep)
                if kind == "init"
                else fmp4.split_moof_mdat(result.body, tracks, keep)
            )
            content_type = "video/mp4" if keep == "video" else "audio/mp4"
    except fmp4.Fmp4Error as exc:
        logger.warning("fmp4 demux failed (kind=%s): %s", kind, exc)
        raise web.HTTPBadGateway(text=f"fmp4 demux failed: {exc}") from exc
    headers = {"Cache-Control": "no-store", "Accept-Ranges": "bytes"}
    status = 200
    if request.headers.get("Range"):
        try:
            requested = request.http_range
            if requested.start is not None and requested.start >= len(rewritten):
                raise ValueError("Out of bounds")
            start, end, _ = requested.indices(len(rewritten))
            if start >= end:
                raise ValueError("Empty range")
        except ValueError as exc:
            raise web.HTTPRequestRangeNotSatisfiable(
                headers={"Content-Range": f"bytes */{len(rewritten)}"}
            ) from exc
        headers["Content-Range"] = f"bytes {start}-{end - 1}/{len(rewritten)}"
        rewritten = rewritten[start:end]
        status = 206
    return web.Response(body=rewritten, content_type=content_type, headers=headers, status=status)
