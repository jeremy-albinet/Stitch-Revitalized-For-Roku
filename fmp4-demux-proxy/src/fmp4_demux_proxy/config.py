"""Environment-based configuration for fmp4-demux-proxy."""

import os
from dataclasses import dataclass

_DEFAULT_UPSTREAM_CONNECT_TIMEOUT = 5.0
_DEFAULT_UPSTREAM_READ_TIMEOUT = 30.0


@dataclass(frozen=True)
class Config:
    port: int
    log_level: str
    proxy_public_url: str | None
    upstream_connect_timeout: float
    upstream_read_timeout: float


def get_config() -> Config:
    port = int(os.environ.get("PORT", "8080"))
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    raw_url = os.environ.get("PROXY_PUBLIC_URL", "").strip()
    proxy_public_url = raw_url.rstrip("/") if raw_url else None
    upstream_connect_timeout = float(
        os.environ.get("UPSTREAM_CONNECT_TIMEOUT", str(_DEFAULT_UPSTREAM_CONNECT_TIMEOUT))
    )
    upstream_read_timeout = float(
        os.environ.get("UPSTREAM_READ_TIMEOUT", str(_DEFAULT_UPSTREAM_READ_TIMEOUT))
    )

    return Config(
        port=port,
        log_level=log_level,
        proxy_public_url=proxy_public_url,
        upstream_connect_timeout=upstream_connect_timeout,
        upstream_read_timeout=upstream_read_timeout,
    )
