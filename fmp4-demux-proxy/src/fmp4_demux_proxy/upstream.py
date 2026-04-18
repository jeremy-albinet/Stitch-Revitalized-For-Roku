"""Shared outbound HTTP client for fetching upstream Twitch content."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Final

import aiohttp
from aiohttp import web

from fmp4_demux_proxy.config import Config

SESSION_KEY: Final[web.AppKey[aiohttp.ClientSession]] = web.AppKey(
    "upstream_session", aiohttp.ClientSession
)
CONFIG_KEY: Final[web.AppKey[Config]] = web.AppKey("config", Config)


async def upstream_session_cleanup_ctx(app: web.Application) -> AsyncIterator[None]:
    cfg = app[CONFIG_KEY]
    timeout = aiohttp.ClientTimeout(
        connect=cfg.upstream_connect_timeout,
        total=None,
        sock_read=cfg.upstream_read_timeout,
    )
    session = aiohttp.ClientSession(timeout=timeout)
    app[SESSION_KEY] = session
    try:
        yield
    finally:
        await session.close()
