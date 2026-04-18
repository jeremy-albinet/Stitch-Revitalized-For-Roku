"""Health-check endpoint."""

from aiohttp import web

from fmp4_demux_proxy import __version__


async def health_handler(request: web.Request) -> web.Response:
    """Return 200 with service status and version.

    Response body::

        {"status": "ok", "version": "0.1.0"}
    """
    return web.json_response({"status": "ok", "version": __version__})
