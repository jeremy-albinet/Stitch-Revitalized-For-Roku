"""Shared outbound HTTP client for fetching upstream Twitch content."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Final
from urllib.parse import urlparse

import aiohttp
from aiohttp import web

from fmp4_demux_proxy.config import Config

SESSION_KEY: Final[web.AppKey[aiohttp.ClientSession]] = web.AppKey(
    "upstream_session", aiohttp.ClientSession
)
CONFIG_KEY: Final[web.AppKey[Config]] = web.AppKey("config", Config)

_ALLOWED_SCHEMES: Final[frozenset[str]] = frozenset({"http", "https"})


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


def validate_upstream_url(url: str, allowlist: tuple[str, ...]) -> None:
    """Raise HTTPBadRequest if `url` fails scheme/host allowlist checks.

    Used both on the inbound ``u=`` query param and on the final URL after
    redirects, to prevent open-proxy / SSRF abuse (e.g. redirect to an
    internal service or cloud metadata endpoint).

    An empty allowlist means "no host restriction" — scheme is still enforced.
    Entries are matched as domain suffixes (``ttvnw.net`` matches
    ``foo.ttvnw.net`` and ``ttvnw.net`` but not ``evilttvnw.net``).
    """
    if not url:
        raise web.HTTPBadRequest(text="empty upstream url")

    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise web.HTTPBadRequest(text=f"disallowed upstream scheme: {scheme or '<empty>'}")

    host = (parsed.hostname or "").lower()
    if not host:
        raise web.HTTPBadRequest(text="missing upstream host")

    if not allowlist:
        return

    for suffix in allowlist:
        if host == suffix or host.endswith("." + suffix):
            return

    raise web.HTTPBadRequest(text=f"disallowed upstream host: {host}")
