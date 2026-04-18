"""Shared pytest fixtures for fmp4-demux-proxy tests."""

from collections.abc import AsyncIterator

import pytest
from aiohttp.test_utils import TestClient

from fmp4_demux_proxy.app import create_app
from fmp4_demux_proxy.config import Config


def make_test_config(port: int = 0) -> Config:
    return Config(
        port=port,
        log_level="WARNING",
        proxy_public_url=None,
        upstream_connect_timeout=1.0,
        upstream_read_timeout=2.0,
    )


@pytest.fixture
async def client(aiohttp_client: pytest.fixture) -> AsyncIterator[TestClient]:
    app = create_app(config=make_test_config())
    return await aiohttp_client(app)
