"""Environment-based configuration for fmp4-demux-proxy."""

import os
from dataclasses import dataclass

_DEFAULT_UPSTREAM_CONNECT_TIMEOUT = 5.0
_DEFAULT_UPSTREAM_READ_TIMEOUT = 30.0
_DEFAULT_UPSTREAM_HOST_ALLOWLIST: tuple[str, ...] = (
    "ttvnw.net",
    "twitch.tv",
    "twitchcdn.net",
)


@dataclass(frozen=True)
class Config:
    port: int
    log_level: str
    proxy_public_url: str | None
    upstream_connect_timeout: float
    upstream_read_timeout: float
    upstream_host_allowlist: tuple[str, ...]


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
    upstream_host_allowlist = _parse_host_allowlist(
        os.environ.get("UPSTREAM_HOST_ALLOWLIST")
    )

    return Config(
        port=port,
        log_level=log_level,
        proxy_public_url=proxy_public_url,
        upstream_connect_timeout=upstream_connect_timeout,
        upstream_read_timeout=upstream_read_timeout,
        upstream_host_allowlist=upstream_host_allowlist,
    )


def _parse_host_allowlist(raw: str | None) -> tuple[str, ...]:
    if raw is None:
        return _DEFAULT_UPSTREAM_HOST_ALLOWLIST
    entries = tuple(
        item.strip().lower().lstrip(".") for item in raw.split(",") if item.strip()
    )
    return entries
