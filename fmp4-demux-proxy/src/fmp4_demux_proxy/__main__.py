"""Entrypoint for running fmp4-demux-proxy via ``python -m fmp4_demux_proxy``."""

import logging

from aiohttp import web

from fmp4_demux_proxy.app import create_app
from fmp4_demux_proxy.config import get_config


def main() -> None:
    """Create and run the aiohttp application."""
    cfg = get_config()
    logging.basicConfig(
        level=cfg.log_level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    app = create_app(config=cfg)
    web.run_app(app, host="0.0.0.0", port=cfg.port)


if __name__ == "__main__":
    main()
