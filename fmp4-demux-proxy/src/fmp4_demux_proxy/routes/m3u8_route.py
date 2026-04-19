"""HLS manifest proxy route: GET /m3u8?u=<upstream_url>"""

from __future__ import annotations

import logging
from typing import Final

import aiohttp
from aiohttp import web

from fmp4_demux_proxy import manifest as mf
from fmp4_demux_proxy.upstream import CONFIG_KEY, SESSION_KEY, validate_upstream_url

logger = logging.getLogger(__name__)

_MANIFEST_CONTENT_TYPE: Final[str] = "application/vnd.apple.mpegurl"


def _proxy_base_from_request(request: web.Request) -> str:
    scheme = request.headers.get("X-Forwarded-Proto", request.scheme)
    host = request.headers.get("X-Forwarded-Host", request.host)
    return f"{scheme}://{host}"


def _parse_hints(request: web.Request) -> mf.VariantHints | None:
    codecs = request.query.get("codecs") or None
    resolution = request.query.get("res") or None
    bandwidth_raw = request.query.get("bw")
    bandwidth: int | None = None
    if bandwidth_raw:
        try:
            parsed = int(bandwidth_raw)
        except ValueError:
            parsed = 0
        if parsed > 0:
            bandwidth = parsed
    if codecs is None and resolution is None and bandwidth is None:
        return None
    return mf.VariantHints(codecs=codecs, bandwidth=bandwidth, resolution=resolution)


async def m3u8_handler(request: web.Request) -> web.Response:
    session: aiohttp.ClientSession = request.app[SESSION_KEY]
    cfg = request.app[CONFIG_KEY]

    upstream = request.query.get("u")
    if not upstream:
        raise web.HTTPBadRequest(text="missing query param: u")

    validate_upstream_url(upstream, cfg.upstream_host_allowlist)

    try:
        async with session.get(upstream, allow_redirects=True) as resp:
            final_url = str(resp.url)
            validate_upstream_url(final_url, cfg.upstream_host_allowlist)
            if resp.status != 200:
                logger.warning("upstream m3u8 returned %s for %s", resp.status, upstream)
                raise web.HTTPBadGateway(text=f"upstream status {resp.status}")
            body_bytes = await resp.read()
    except aiohttp.ClientError as exc:
        logger.error("upstream m3u8 fetch failed for %s: %s", upstream, exc)
        raise web.HTTPBadGateway(text=f"upstream fetch failed: {exc}") from exc

    try:
        body_text = body_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise web.HTTPBadGateway(text=f"upstream body not utf-8: {exc}") from exc

    proxy_base = cfg.proxy_public_url or _proxy_base_from_request(request)
    rewrite_cfg = mf.RewriteConfig(proxy_base=proxy_base)
    raw_track = request.query.get("track")
    if raw_track in (None, ""):
        track = None
    elif raw_track in {"video", "audio"}:
        track = raw_track
    else:
        raise web.HTTPBadRequest(text="invalid query param: track")

    hints = _parse_hints(request)
    rewritten = mf.rewrite(
        body_text, base_url=final_url, config=rewrite_cfg, track=track, hints=hints
    )

    return web.Response(
        body=rewritten.encode("utf-8"),
        content_type=_MANIFEST_CONTENT_TYPE,
        headers={"Cache-Control": "no-store"},
    )
