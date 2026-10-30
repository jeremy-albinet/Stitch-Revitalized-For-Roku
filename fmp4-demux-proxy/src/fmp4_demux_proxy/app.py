"""Application factory with bounded request admission and shared fetch state."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Final

from aiohttp import web

from fmp4_demux_proxy.config import Config, get_config
from fmp4_demux_proxy.routes.health import health_handler
from fmp4_demux_proxy.routes.m3u8_route import m3u8_handler, selected_m3u8_handler
from fmp4_demux_proxy.routes.segment_route import (
    STORE_KEY,
    SegmentStore,
    segment_handler,
    segment_store_cleanup_ctx,
)
from fmp4_demux_proxy.upstream import (
    CONFIG_KEY,
    FETCH_SLOTS_KEY,
    INSPECTION_SLOTS_KEY,
    upstream_session_cleanup_ctx,
)


@dataclass
class RequestAdmission:
    active: int = 0


ADMISSION_KEY: Final = web.AppKey("request_admission", RequestAdmission)


@web.middleware
async def admission_middleware(
    request: web.Request, handler: Callable[[web.Request], Awaitable[web.StreamResponse]]
) -> web.StreamResponse:
    if request.path == "/health":
        return await handler(request)
    admission = request.app[ADMISSION_KEY]
    if admission.active >= request.app[CONFIG_KEY].max_inflight_requests:
        raise web.HTTPServiceUnavailable(text="Proxy is busy; retry shortly")
    admission.active += 1
    try:
        async with asyncio.timeout(request.app[CONFIG_KEY].upstream_total_timeout):
            return await handler(request)
    except TimeoutError as exc:
        raise web.HTTPGatewayTimeout(text="Proxy request timed out") from exc
    finally:
        admission.active -= 1


def create_app(config: Config | None = None) -> web.Application:
    app = web.Application(middlewares=[admission_middleware])
    cfg = config if config is not None else get_config()
    app[CONFIG_KEY] = cfg
    app[STORE_KEY] = SegmentStore()
    app[ADMISSION_KEY] = RequestAdmission()
    app[FETCH_SLOTS_KEY] = asyncio.Semaphore(cfg.max_upstream_concurrency)
    app[INSPECTION_SLOTS_KEY] = asyncio.Semaphore(cfg.max_upstream_concurrency)
    # Cleanup runs in reverse order: cancel pending fetches before closing their session.
    app.cleanup_ctx.append(upstream_session_cleanup_ctx)
    app.cleanup_ctx.append(segment_store_cleanup_ctx)
    app.router.add_get("/health", health_handler)
    app.router.add_get("/m3u8", m3u8_handler)
    app.router.add_get("/m3u8/selected", selected_m3u8_handler)
    app.router.add_get("/s", segment_handler)
    return app
