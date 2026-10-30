"""Bounded outbound requests with validation before every connection/redirect."""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import re
import socket
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Final
from urllib.parse import urljoin, urlsplit

import aiohttp
from aiohttp import web
from aiohttp.abc import AbstractResolver, ResolveResult

from fmp4_demux_proxy.config import Config

logger = logging.getLogger(__name__)
SESSION_KEY: Final = web.AppKey("upstream_session", aiohttp.ClientSession)
CONFIG_KEY: Final = web.AppKey("config", Config)
FETCH_SLOTS_KEY: Final = web.AppKey("fetch_slots", asyncio.Semaphore)
INSPECTION_SLOTS_KEY: Final = web.AppKey("inspection_slots", asyncio.Semaphore)
_MAX_REDIRECTS = 5


@dataclass(frozen=True)
class ByteRange:
    offset: int
    length: int

    def __post_init__(self) -> None:
        if self.offset < 0 or self.length <= 0:
            raise ValueError("Invalid byte range")

    @property
    def header(self) -> str:
        return f"bytes={self.offset}-{self.offset + self.length - 1}"

    @property
    def query(self) -> str:
        return f"{self.length}@{self.offset}"


def parse_byte_range(value: str | None) -> ByteRange | None:
    if value is None:
        return None
    if len(value) > 64 or not re.fullmatch(r"[0-9]+@[0-9]+", value):
        raise web.HTTPBadRequest(text="Invalid explicit input byte range")
    length, offset = map(int, value.split("@"))
    try:
        return ByteRange(offset, length)
    except ValueError as exc:
        raise web.HTTPBadRequest(text="Invalid explicit input byte range") from exc


@dataclass(frozen=True)
class UpstreamData:
    body: bytes
    final_url: str
    content_type: str


def _is_public_address(host: str) -> bool:
    address = ipaddress.ip_address(host)
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    return address.is_global


def validate_upstream_url(
    url: str, allowlist: tuple[str, ...], *, allow_unsafe: bool = False
) -> None:
    """Check names and literal IPs; the connector validates actual DNS answers."""
    try:
        parsed = urlsplit(url)
        host = (parsed.hostname or "").lower().rstrip(".")
        port = parsed.port
    except ValueError as exc:
        raise web.HTTPBadRequest(text="Invalid upstream URL") from exc
    if (
        parsed.scheme not in {"http", "https"}
        or not host
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or (port is not None and not 1 <= port <= 65535)
        or any(c.isspace() or c == "\\" for c in url)
    ):
        raise web.HTTPBadRequest(text="Invalid upstream URL scheme, host or credentials")
    if allowlist and not any(host == s or host.endswith("." + s) for s in allowlist):
        raise web.HTTPBadRequest(text="disallowed upstream host")
    if not allowlist and not allow_unsafe:
        raise web.HTTPBadRequest(text="Upstream allowlist required")
    if not allow_unsafe:
        try:
            public = _is_public_address(host)
        except ValueError:
            pass
        else:
            if not public:
                raise web.HTTPBadRequest(text="Private upstream addresses are prohibited")


class PublicResolver(AbstractResolver):
    """Validate the exact DNS addresses consumed by TCPConnector (no second lookup)."""

    def __init__(self, resolver: AbstractResolver | None = None) -> None:
        self._resolver = resolver if resolver is not None else aiohttp.ThreadedResolver()

    async def resolve(
        self, host: str, port: int = 0, family: socket.AddressFamily = socket.AF_INET
    ) -> list[ResolveResult]:
        records = await self._resolver.resolve(host, port, family)
        if not records or any(not _is_public_address(record["host"]) for record in records):
            raise OSError("Upstream DNS contains a private or non-global address")
        return records

    async def close(self) -> None:
        await self._resolver.close()


async def upstream_session_cleanup_ctx(app: web.Application) -> AsyncIterator[None]:
    cfg = app[CONFIG_KEY]
    resolver = None if cfg.allow_unsafe_upstream else PublicResolver()
    connector = aiohttp.TCPConnector(
        resolver=resolver, limit=cfg.max_upstream_concurrency, ttl_dns_cache=30
    )
    session = aiohttp.ClientSession(
        connector=connector,
        timeout=aiohttp.ClientTimeout(
            connect=cfg.upstream_connect_timeout,
            total=cfg.upstream_total_timeout,
            sock_read=cfg.upstream_read_timeout,
        ),
        headers={"Accept-Encoding": "identity"},
        auto_decompress=False,
        trust_env=False,
        cookie_jar=aiohttp.DummyCookieJar(),
    )
    app[SESSION_KEY] = session
    try:
        yield
    finally:
        await session.close()
        if resolver is not None:
            await resolver.close()


async def fetch_upstream(
    app: web.Application, url: str, *, limit: int, byte_range: ByteRange | None = None
) -> UpstreamData:
    cfg = app[CONFIG_KEY]
    validate_upstream_url(url, cfg.upstream_host_allowlist, allow_unsafe=cfg.allow_unsafe_upstream)
    if byte_range is not None and byte_range.length > limit:
        raise web.HTTPBadGateway(text="Input byte range exceeds upstream response limit")
    session = app[SESSION_KEY]
    headers = {"Range": byte_range.header} if byte_range is not None else {}
    try:
        # Includes queueing, the entire redirect chain, and reading the complete body.
        async with asyncio.timeout(cfg.upstream_total_timeout), app[FETCH_SLOTS_KEY]:
            current = url
            for hop in range(_MAX_REDIRECTS + 1):
                validate_upstream_url(
                    current, cfg.upstream_host_allowlist, allow_unsafe=cfg.allow_unsafe_upstream
                )
                async with session.get(current, allow_redirects=False, headers=headers) as response:
                    if response.status in {301, 302, 303, 307, 308}:
                        location = response.headers.get("Location")
                        if not location or hop == _MAX_REDIRECTS:
                            raise web.HTTPBadGateway(text="Invalid or excessive upstream redirects")
                        current = urljoin(str(response.url), location)
                        continue
                    expected = 206 if byte_range is not None else 200
                    if response.status != expected:
                        raise web.HTTPBadGateway(
                            text=f"Unexpected upstream status {response.status}"
                        )
                    if response.headers.get("Content-Encoding", "identity") != "identity":
                        raise web.HTTPBadGateway(text="Unsupported upstream content encoding")
                    if byte_range is not None:
                        content_range = response.headers.get("Content-Range", "")
                        match = re.fullmatch(r"bytes ([0-9]+)-([0-9]+)/([0-9]+|\*)", content_range)
                        if (
                            not match
                            or int(match[1]) != byte_range.offset
                            or int(match[2]) != byte_range.offset + byte_range.length - 1
                        ):
                            raise web.HTTPBadGateway(
                                text="Upstream returned an incorrect byte range"
                            )
                    if response.content_length is not None and response.content_length > limit:
                        raise web.HTTPBadGateway(text="Upstream response exceeds size limit")
                    body = bytearray()
                    async for chunk in response.content.iter_chunked(64 * 1024):
                        if len(body) + len(chunk) > limit:
                            raise web.HTTPBadGateway(text="Upstream response exceeds size limit")
                        body.extend(chunk)
                    if byte_range is not None and len(body) != byte_range.length:
                        raise web.HTTPBadGateway(text="Truncated upstream byte range")
                    if not body:
                        raise web.HTTPBadGateway(text="Upstream returned an empty body")
                    return UpstreamData(bytes(body), str(response.url), response.content_type)
    except (aiohttp.ClientError, OSError, TimeoutError) as exc:
        # Exception messages often contain signed URLs. Log only the class.
        logger.warning("Upstream fetch failed (%s)", type(exc).__name__)
        raise web.HTTPBadGateway(text="Upstream request failed or timed out") from exc
    raise web.HTTPBadGateway(text="Upstream request failed")
