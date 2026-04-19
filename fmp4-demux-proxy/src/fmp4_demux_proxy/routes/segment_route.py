"""fMP4 segment proxy route: GET /s?u=<upstream_url>&k=<kind>[&track=<video|audio>]"""

from __future__ import annotations

import asyncio
import logging
from collections import OrderedDict
from typing import Final
from urllib.parse import urlparse

import aiohttp
from aiohttp import web

from fmp4_demux_proxy import fmp4
from fmp4_demux_proxy.upstream import CONFIG_KEY, SESSION_KEY, validate_upstream_url

_VALID_TRACKS: Final[frozenset[str]] = frozenset({"video", "audio"})

logger = logging.getLogger(__name__)

_VALID_KINDS: Final[frozenset[str]] = frozenset({"init", "media", "part", "prefetch"})
_SEGMENT_CONTENT_TYPE: Final[str] = "video/mp4"
_MAX_CACHE: Final[int] = 50
# Cap track_maps independently — one entry per unique variant directory path.
# Bounded so long-running / multi-channel proxies don't leak memory.
_MAX_TRACK_MAPS: Final[int] = 100

TRACK_MAP_KEY: Final[web.AppKey[OrderedDict[str, dict[int, fmp4.TrackKind]]]] = web.AppKey(
    "track_maps", OrderedDict
)
SEGMENT_CACHE_KEY: Final[web.AppKey[OrderedDict[str, bytes]]] = web.AppKey(
    "segment_cache", OrderedDict
)
SEGMENT_LOCKS_KEY: Final[web.AppKey[dict[str, asyncio.Lock]]] = web.AppKey("segment_locks", dict)


def _cache_key(upstream: str) -> str:
    parsed = urlparse(upstream)
    path = parsed.path.rsplit("/", 1)[0]
    return f"{parsed.scheme}://{parsed.netloc}{path}"


async def _fetch_dedup(
    session: aiohttp.ClientSession,
    upstream: str,
    app: web.Application,
) -> bytes:
    cache = app[SEGMENT_CACHE_KEY]
    locks = app[SEGMENT_LOCKS_KEY]
    cfg = app[CONFIG_KEY]

    if upstream not in locks:
        locks[upstream] = asyncio.Lock()
    lock = locks[upstream]

    async with lock:
        if upstream in cache:
            cache.move_to_end(upstream)
            return cache[upstream]

        cached = False
        try:
            try:
                async with session.get(upstream, allow_redirects=True) as resp:
                    validate_upstream_url(str(resp.url), cfg.upstream_host_allowlist)
                    if resp.status != 200:
                        logger.warning("upstream segment returned %s for %s", resp.status, upstream)
                        raise web.HTTPBadGateway(text=f"upstream status {resp.status}")
                    data = await resp.read()
            except aiohttp.ClientError as exc:
                logger.error("upstream segment fetch failed for %s: %s", upstream, exc)
                raise web.HTTPBadGateway(text=f"upstream fetch failed: {exc}") from exc

            if not data:
                logger.warning("upstream returned empty body for %s", upstream)
                raise web.HTTPBadGateway(text="upstream returned empty segment")

            cache[upstream] = data
            cached = True
            if len(cache) > _MAX_CACHE:
                evicted, _ = cache.popitem(last=False)
                locks.pop(evicted, None)
            return data
        finally:
            # Drop the lock entry when nothing was cached (fetch failed) so that
            # a parade of bad URLs cannot grow SEGMENT_LOCKS_KEY without bound.
            if not cached:
                locks.pop(upstream, None)


async def segment_handler(request: web.Request) -> web.Response:
    session: aiohttp.ClientSession = request.app[SESSION_KEY]
    cfg = request.app[CONFIG_KEY]

    upstream = request.query.get("u")
    kind = request.query.get("k")
    track = request.query.get("track")

    if not upstream or not kind:
        raise web.HTTPBadRequest(text="missing query params: u, k")
    if kind not in _VALID_KINDS:
        raise web.HTTPBadRequest(text=f"invalid kind: {kind}")
    if not track or track not in _VALID_TRACKS:
        raise web.HTTPBadRequest(text=f"invalid or missing track: {track}")

    validate_upstream_url(upstream, cfg.upstream_host_allowlist)

    data = await _fetch_dedup(session, upstream, request.app)

    track_maps = request.app[TRACK_MAP_KEY]
    cache_key = _cache_key(upstream)
    keep: fmp4.TrackKind = "video" if track == "video" else "audio"

    try:
        if kind == "init":
            track_map = fmp4.extract_track_map(data)
            track_maps[cache_key] = track_map
            track_maps.move_to_end(cache_key)
            if len(track_maps) > _MAX_TRACK_MAPS:
                track_maps.popitem(last=False)
            rewritten = fmp4.split_moov(data, track_map, keep)
            logger.debug("init rewritten for %s; track_map=%s", cache_key, track_map)
        else:
            track_map = track_maps.get(cache_key)
            if track_map is None:
                logger.warning(
                    "no track_map cached for %s (k=%s); passing through unchanged",
                    cache_key,
                    kind,
                )
                rewritten = data
            else:
                track_maps.move_to_end(cache_key)
                rewritten = fmp4.split_moof_mdat(data, track_map, keep)
    except fmp4.Fmp4Error as exc:
        logger.warning("fmp4 demux failed for %s (k=%s): %s", upstream, kind, exc)
        raise web.HTTPBadGateway(text=f"fmp4 demux failed: {exc}") from exc

    return web.Response(
        body=rewritten,
        content_type=_SEGMENT_CONTENT_TYPE,
        headers={"Cache-Control": "no-store"},
    )
