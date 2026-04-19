"""Application factory for the fmp4-demux-proxy aiohttp server."""

from __future__ import annotations

from collections import OrderedDict

from aiohttp import web

from fmp4_demux_proxy.config import Config, get_config
from fmp4_demux_proxy.routes.health import health_handler
from fmp4_demux_proxy.routes.m3u8_route import m3u8_handler
from fmp4_demux_proxy.routes.segment_route import (
    SEGMENT_CACHE_KEY,
    SEGMENT_LOCKS_KEY,
    TRACK_MAP_KEY,
    segment_handler,
)
from fmp4_demux_proxy.upstream import CONFIG_KEY, upstream_session_cleanup_ctx


def create_app(config: Config | None = None) -> web.Application:
    app = web.Application()
    app[CONFIG_KEY] = config if config is not None else get_config()
    app[TRACK_MAP_KEY] = OrderedDict()
    app[SEGMENT_CACHE_KEY] = OrderedDict()
    app[SEGMENT_LOCKS_KEY] = {}
    app.cleanup_ctx.append(upstream_session_cleanup_ctx)
    app.router.add_get("/health", health_handler)
    app.router.add_get("/m3u8", m3u8_handler)
    app.router.add_get("/s", segment_handler)
    return app
