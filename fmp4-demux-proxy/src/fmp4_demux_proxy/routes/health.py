"""Health-check endpoint."""

from aiohttp import web

from fmp4_demux_proxy import __version__


async def health_handler(request: web.Request) -> web.Response:
    """Return 200 with service status and version.

    Response body::

        {"status": "ok", "version": "0.3.2", "selected_master_version": 1}
    """
    return web.json_response({"status": "ok", "version": __version__, "selected_master_version": 1})
