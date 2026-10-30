"""Validated environment configuration for the optional demux service."""

import math
import os
from dataclasses import dataclass
from urllib.parse import urlsplit

_DEFAULT_ALLOWLIST = ("ttvnw.net", "twitch.tv", "twitchcdn.net", "cloudfront.net")


@dataclass(frozen=True)
class Config:
    port: int
    log_level: str
    proxy_public_url: str | None
    upstream_connect_timeout: float
    upstream_read_timeout: float
    upstream_host_allowlist: tuple[str, ...]
    upstream_total_timeout: float = 45.0
    max_manifest_bytes: int = 2 * 1024 * 1024
    max_segment_bytes: int = 32 * 1024 * 1024
    segment_cache_bytes: int = 128 * 1024 * 1024
    max_upstream_concurrency: int = 8
    max_inflight_requests: int = 64
    allow_unsafe_upstream: bool = False

    def __post_init__(self) -> None:
        if not 0 <= self.port <= 65535:
            raise ValueError("PORT must be between 0 and 65535")
        for name in (
            "upstream_connect_timeout",
            "upstream_read_timeout",
            "upstream_total_timeout",
            "max_manifest_bytes",
            "max_segment_bytes",
            "segment_cache_bytes",
            "max_upstream_concurrency",
            "max_inflight_requests",
        ):
            value = getattr(self, name)
            if not math.isfinite(value) or value <= 0:
                raise ValueError(f"{name} must be finite and positive")
        if not self.upstream_host_allowlist and not self.allow_unsafe_upstream:
            raise ValueError("An empty upstream allowlist requires ALLOW_UNSAFE_UPSTREAM=true")
        if self.proxy_public_url:
            validate_proxy_base(self.proxy_public_url)


def validate_proxy_base(url: str) -> str:
    """Allow an explicit HTTP(S) base, never a query, credentials or header injection."""
    parsed = urlsplit(url)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or any(c.isspace() or c in '\\,"' for c in url)
    ):
        raise ValueError("Invalid proxy base URL")
    try:
        _ = parsed.port
    except ValueError as exc:
        raise ValueError("Invalid proxy base port") from exc
    return url.rstrip("/")


def get_config() -> Config:
    unsafe_raw = os.environ.get("ALLOW_UNSAFE_UPSTREAM", "false").lower()
    if unsafe_raw not in {"true", "false", "1", "0"}:
        raise ValueError("ALLOW_UNSAFE_UPSTREAM must be true or false")
    raw_allowlist = os.environ.get("UPSTREAM_HOST_ALLOWLIST")
    allowlist = (
        _DEFAULT_ALLOWLIST
        if raw_allowlist is None
        else tuple(
            item.strip().lower().strip(".") for item in raw_allowlist.split(",") if item.strip()
        )
    )
    raw_url = os.environ.get("PROXY_PUBLIC_URL", "").strip()
    return Config(
        port=int(os.environ.get("PORT", "8080")),
        log_level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        proxy_public_url=raw_url.rstrip("/") if raw_url else None,
        upstream_connect_timeout=float(os.environ.get("UPSTREAM_CONNECT_TIMEOUT", "5")),
        upstream_read_timeout=float(os.environ.get("UPSTREAM_READ_TIMEOUT", "30")),
        upstream_host_allowlist=allowlist,
        upstream_total_timeout=float(os.environ.get("UPSTREAM_TOTAL_TIMEOUT", "45")),
        max_manifest_bytes=int(os.environ.get("MAX_MANIFEST_BYTES", str(2 * 1024 * 1024))),
        max_segment_bytes=int(os.environ.get("MAX_SEGMENT_BYTES", str(32 * 1024 * 1024))),
        segment_cache_bytes=int(os.environ.get("SEGMENT_CACHE_BYTES", str(128 * 1024 * 1024))),
        max_upstream_concurrency=int(os.environ.get("MAX_UPSTREAM_CONCURRENCY", "8")),
        max_inflight_requests=int(os.environ.get("MAX_INFLIGHT_REQUESTS", "64")),
        allow_unsafe_upstream=unsafe_raw in {"true", "1"},
    )
