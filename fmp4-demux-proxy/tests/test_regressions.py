"""End-to-end regressions for request order, HLS relationships and resource/security bounds."""

from __future__ import annotations

import asyncio
import json
import socket
from collections import Counter
from contextlib import asynccontextmanager
from dataclasses import dataclass, field, replace
from types import SimpleNamespace
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse

import pytest
from aiohttp import web
from aiohttp.abc import AbstractResolver, ResolveResult
from aiohttp.test_utils import TestClient, TestServer
from yarl import URL

from fmp4_demux_proxy.app import create_app
from fmp4_demux_proxy.config import get_config
from fmp4_demux_proxy.fmp4 import extract_track_map, iter_top_level_boxes
from fmp4_demux_proxy.routes.segment_route import STORE_KEY, _fetch_cached
from fmp4_demux_proxy.upstream import (
    SESSION_KEY,
    PublicResolver,
    validate_upstream_url,
)
from tests._fixtures import make_init_segment, make_split_media_segment
from tests.conftest import make_test_config


@dataclass
class FakeCDN:
    bodies: dict[str, bytes] = field(default_factory=dict)
    redirects: dict[str, str] = field(default_factory=dict)
    statuses: dict[str, int] = field(default_factory=dict)
    hits: Counter[str] = field(default_factory=Counter)
    ranges: list[str] = field(default_factory=list)
    queries: list[dict[str, str]] = field(default_factory=list)
    delay: float = 0
    chunked: bool = False
    active: int = 0
    peak: int = 0
    started: asyncio.Event = field(default_factory=asyncio.Event)
    gate: asyncio.Event | None = None
    server: TestServer | None = None

    def url(self, path: str) -> str:
        assert self.server is not None
        return str(self.server.make_url(path))

    async def handler(self, request: web.Request) -> web.StreamResponse:
        self.hits[request.path] += 1
        self.queries.append(dict(request.query))
        self.active += 1
        self.peak = max(self.peak, self.active)
        self.started.set()
        try:
            if self.gate is not None:
                await self.gate.wait()
            if self.delay:
                await asyncio.sleep(self.delay)
            if request.path in self.redirects:
                raise web.HTTPFound(self.redirects[request.path])
            status = self.statuses.get(request.path, 200)
            data = self.bodies.get(request.path, b"missing")
            headers: dict[str, str] = {}
            if request.headers.get("Range"):
                value = request.headers["Range"]
                self.ranges.append(value)
                start, end = map(int, value.removeprefix("bytes=").split("-"))
                headers["Content-Range"] = f"bytes {start}-{end}/{len(data)}"
                data = data[start : end + 1]
                status = 206
            if self.chunked:
                response = web.StreamResponse(status=status, headers=headers)
                await response.prepare(request)
                try:
                    for index in range(0, len(data), 16):
                        await response.write(data[index : index + 16])
                    await response.write_eof()
                except ConnectionResetError:
                    pass
                return response
            return web.Response(body=data, status=status, headers=headers, content_type="video/mp4")
        finally:
            self.active -= 1


@pytest.fixture
async def cdn(aiohttp_server: Any) -> FakeCDN:
    state = FakeCDN()
    app = web.Application()
    app.router.add_get("/{path:.*}", state.handler)
    state.server = await aiohttp_server(app)
    return state


@pytest.fixture
def proxy_factory(aiohttp_client: Any) -> Any:
    async def factory(**overrides: Any) -> TestClient:
        cfg = replace(make_test_config(), **overrides)
        return await aiohttp_client(create_app(cfg))

    return factory


def media_request(cdn: FakeCDN, path: str, init: str, track: str = "video") -> str:
    return "/s?" + urlencode({"u": cdn.url(path), "i": cdn.url(init), "k": "media", "track": track})


@pytest.mark.parametrize("track", ["video", "audio"])
@pytest.mark.parametrize("kind", ["media", "part", "prefetch"])
async def test_demux_renditions_refuse_transport_stream(
    cdn: FakeCDN, proxy_factory: Any, track: str, kind: str
) -> None:
    cdn.bodies["/init"] = make_init_segment([(1, b"soun"), (2, b"vide")])
    transport_stream = (b"\x47\x40\x00\x13" + b"\x00" * 184) * 3
    cdn.bodies["/ad"] = transport_stream
    client = await proxy_factory()
    params = {"u": cdn.url("/ad"), "i": cdn.url("/init"), "k": kind, "track": track}
    for headers in ({}, {"Range": "bytes=0-187"}):
        response = await client.get("/s", params=params, headers=headers)
        assert response.status == 502
        assert "fmp4 demux failed" in await response.text()


async def test_native_transport_stream_preserves_bytes_and_ranges(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    transport_stream = (b"\x47\x40\x00\x13" + b"\x00" * 184) * 3
    cdn.bodies["/ad"] = transport_stream
    cdn.bodies["/playlist"] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nad\n"
    client = await proxy_factory()
    playlist = await client.get("/m3u8", params={"u": cdn.url("/playlist")})
    assert playlist.status == 200
    body = await playlist.text()
    assert "#EXT-X-MEDIA:" not in body and "#EXT-X-MAP:" not in body
    uri = next(line for line in body.splitlines() if line.startswith("http"))
    assert parse_qs(urlparse(uri).query)["mode"] == ["passthrough"]
    link = URL(uri).relative()
    response = await client.get(link)
    assert response.status == 200
    assert await response.read() == transport_stream
    partial = await client.get(link, headers={"Range": "bytes=0-187"})
    assert partial.status == 206 and await partial.read() == transport_stream[:188]
    assert partial.headers["Content-Range"] == "bytes 0-187/564"


@pytest.mark.parametrize("track", ["video", "audio"])
async def test_cmaf_transport_discontinuity_never_returns_combined_bytes(
    cdn: FakeCDN, proxy_factory: Any, track: str
) -> None:
    cdn.bodies["/init"] = make_init_segment([(1, b"soun"), (2, b"vide")])
    cdn.bodies["/before"] = make_split_media_segment(1, b"BEFORE", b"first", 2, 1)
    cdn.bodies["/ad"] = (b"\x47\x40\x00\x13" + b"\x00" * 184) * 3
    cdn.bodies["/after"] = make_split_media_segment(2, b"AFTER", b"second", 2, 1)
    cdn.bodies["/playlist"] = (
        b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="init"\n'
        b"#EXTINF:2,\nbefore\n#EXT-X-DISCONTINUITY\n#EXTINF:2,\nad\n"
        b"#EXT-X-DISCONTINUITY\n#EXTINF:2,\nafter\n"
    )
    client = await proxy_factory()
    playlist = await client.get("/m3u8", params={"u": cdn.url("/playlist"), "track": track})
    assert playlist.status == 200
    links = [line for line in (await playlist.text()).splitlines() if line.startswith("http")]
    before, ad, after = [await client.get(URL(link).relative()) for link in links]
    assert before.status == after.status == 200
    assert mdat(await before.read()) == (b"BEFORE" if track == "video" else b"first")
    assert mdat(await after.read()) == (b"AFTER" if track == "video" else b"second")
    assert ad.status == 502 and "fmp4 demux failed" in await ad.text()


@pytest.mark.parametrize("corruption", ["sync", "truncated"])
async def test_mixed_transport_refuses_malformed_packets(
    cdn: FakeCDN, proxy_factory: Any, corruption: str
) -> None:
    cdn.bodies["/init"] = make_init_segment([(1, b"soun"), (2, b"vide")])
    data = (b"\x47\x40\x00\x13" + b"\x00" * 184) * 3
    cdn.bodies["/media"] = data[:376] + b"\x00" + data[377:] if corruption == "sync" else data[:-1]
    client = await proxy_factory()
    response = await client.get(media_request(cdn, "/media", "/init"))
    assert response.status == 502


def test_cloudfront_default_preserves_host_validation(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("UPSTREAM_HOST_ALLOWLIST", raising=False)
    allowlist = get_config().upstream_host_allowlist
    validate_upstream_url("https://example.cloudfront.net/media", allowlist)
    with pytest.raises(web.HTTPBadRequest):
        validate_upstream_url("https://example.cloudfront.net.evil.invalid/media", allowlist)
    monkeypatch.setenv("UPSTREAM_HOST_ALLOWLIST", "ttvnw.net")
    with pytest.raises(web.HTTPBadRequest):
        validate_upstream_url(
            "https://example.cloudfront.net/media", get_config().upstream_host_allowlist
        )


def mdat(data: bytes) -> bytes:
    return b"".join(
        raw[header.header_size :]
        for header, raw in iter_top_level_boxes(data)
        if header.type == b"mdat"
    )


async def test_media_first_concurrent_audio_video_fetches_once(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/maps/init"] = make_init_segment([(1, b"soun"), (2, b"vide")])
    cdn.bodies["/elsewhere/media"] = make_split_media_segment(1, b"VIDEO", b"AUDIO", 2, 1)
    cdn.delay = 0.01
    client = await proxy_factory()
    video, audio = await asyncio.gather(
        client.get(media_request(cdn, "/elsewhere/media", "/maps/init")),
        client.get(media_request(cdn, "/elsewhere/media", "/maps/init", "audio")),
    )
    assert video.status == audio.status == 200
    assert mdat(await video.read()) == b"VIDEO"
    assert mdat(await audio.read()) == b"AUDIO"
    assert audio.headers["Content-Type"] == "audio/mp4"
    assert cdn.hits == {"/maps/init": 1, "/elsewhere/media": 1}
    assert not client.app[STORE_KEY].pending


async def test_discontinuity_changes_track_ids_in_same_directory(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/init-a"] = make_init_segment([(1, b"soun"), (2, b"vide")])
    cdn.bodies["/init-b"] = make_init_segment([(1, b"vide"), (2, b"soun")])
    cdn.bodies["/a"] = make_split_media_segment(1, b"BEFORE", b"first", 2, 1)
    cdn.bodies["/b"] = make_split_media_segment(2, b"AFTER", b"second", 1, 2)
    cdn.bodies["/playlist"] = (
        b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="init-a"\n'
        b'#EXTINF:2,\na\n#EXT-X-DISCONTINUITY\n#EXT-X-MAP:URI="init-b"\n#EXTINF:2,\nb\n'
    )
    client = await proxy_factory()
    response = await client.get("/m3u8", params={"u": cdn.url("/playlist"), "track": "video"})
    assert response.status == 200
    links = [line for line in (await response.text()).splitlines() if line.startswith("http")]
    assert [parse_qs(urlparse(link).query)["i"][0] for link in links] == [
        cdn.url("/init-a"),
        cdn.url("/init-b"),
    ]
    # Fetch the later discontinuity first; no init route was requested.
    after = await client.get(URL(links[1]).relative())
    before = await client.get(URL(links[0]).relative())
    assert after.status == before.status == 200
    assert mdat(await after.read()) == b"AFTER"
    assert mdat(await before.read()) == b"BEFORE"


async def test_init_eviction_does_not_reintroduce_muxed_passthrough(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    init = make_init_segment([(1, b"vide"), (2, b"soun")])
    cdn.bodies["/old-init"] = init
    cdn.bodies["/media"] = make_split_media_segment(1, b"video", b"audio")
    client = await proxy_factory()
    link = media_request(cdn, "/media", "/old-init")
    first = await client.get(link)
    assert first.status == 200
    await first.read()
    # Exceed both independently bounded LRU stores using distinct init identities.
    for index in range(101):
        path = f"/new-init-{index}"
        cdn.bodies[path] = init
        response = await client.get(
            "/s", params={"u": cdn.url(path), "k": "init", "track": "video"}
        )
        assert response.status == 200
        await response.read()
    store = client.app[STORE_KEY]
    assert (cdn.url("/old-init"), None) not in store.track_maps
    assert (cdn.url("/old-init"), None) not in store.cache
    response = await client.get(link)
    assert response.status == 200
    assert mdat(await response.read()) == b"video"
    assert cdn.hits["/old-init"] == 2
    assert len(store.track_maps) <= 100 and len(store.cache) <= 50


async def test_missing_requested_track_and_unknown_fragment_fail_closed(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/init"] = make_init_segment([(1, b"vide")])
    cdn.bodies["/media"] = make_split_media_segment(1, b"video", b"audio", 7, 8)
    client = await proxy_factory()
    audio = await client.get(media_request(cdn, "/media", "/init", "audio"))
    video = await client.get(media_request(cdn, "/media", "/init"))
    assert audio.status == video.status == 502
    assert (await video.read()) != cdn.bodies["/media"]


async def test_ranged_vod_serves_whole_split_segments_with_correct_samples(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    init = make_init_segment([(1, b"vide"), (2, b"soun")])
    one = make_split_media_segment(1, b"ONE-video", b"ONE-audio")
    two = make_split_media_segment(2, b"TWO-video", b"TWO-audio")
    cdn.bodies["/file.mp4"] = init + one + two
    cdn.bodies["/vod"] = (
        f'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="file.mp4",BYTERANGE="{len(init)}@0"\n'
        f"#EXTINF:2,\n#EXT-X-BYTERANGE:{len(one)}@{len(init)}\nfile.mp4\n"
        f"#EXTINF:2,\n#EXT-X-BYTERANGE:{len(two)}\nfile.mp4\n#EXT-X-ENDLIST\n"
    ).encode()
    client = await proxy_factory()
    playlist = await client.get("/m3u8", params={"u": cdn.url("/vod"), "track": "audio"})
    assert playlist.status == 200
    body = await playlist.text()
    assert "BYTERANGE" not in body
    links = [line for line in body.splitlines() if line.startswith("http")]
    one_response, two_response = await asyncio.gather(
        *(client.get(URL(link).relative()) for link in links)
    )
    assert one_response.status == two_response.status == 200
    assert mdat(await one_response.read()) == b"ONE-audio"
    assert mdat(await two_response.read()) == b"TWO-audio"
    assert set(cdn.ranges) == {
        f"bytes=0-{len(init) - 1}",
        f"bytes={len(init)}-{len(init) + len(one) - 1}",
        f"bytes={len(init) + len(one)}-{len(init) + len(one) + len(two) - 1}",
    }


async def test_client_range_is_applied_to_split_output_not_muxed_input(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/init"] = make_init_segment([(1, b"vide"), (2, b"soun")])
    cdn.bodies["/media"] = make_split_media_segment(1, b"video", b"audio")
    client = await proxy_factory()
    link = media_request(cdn, "/media", "/init")
    whole = await client.get(link)
    data = await whole.read()
    partial = await client.get(link, headers={"Range": "bytes=0-7"})
    assert partial.status == 206 and await partial.read() == data[:8]
    assert partial.headers["Content-Range"] == f"bytes 0-7/{len(data)}"
    assert not cdn.ranges
    invalid = await client.get(link, headers={"Range": "bytes=999999-"})
    assert invalid.status == 416


async def test_master_filter_keeps_external_audio_and_subtitle_groups(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = (
        b'#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="en",NAME="English",URI="audio"\n'
        b'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="other",NAME="Other",URI="other-audio"\n'
        b'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Subtitles",URI="subs"\n'
        b'#EXT-X-STREAM-INF:BANDWIDTH=6000000,CODECS="hvc1.1.6.L150.B0,mp4a.40.2",'
        b'RESOLUTION=2560x1440,AUDIO="en",SUBTITLES="subs"\nvideo\n'
        b'#EXT-X-STREAM-INF:BANDWIDTH=3000000,AUDIO="other"\nother-video\n'
    )
    cdn.bodies["/audio"] = (
        b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="audio-init"\n#EXTINF:2,\naudio-media\n'
    )
    cdn.bodies["/audio-init"] = make_init_segment([(7, b"soun")])
    cdn.bodies["/video"] = (
        b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="video-init"\n#EXTINF:2,\nv\n'
    )
    cdn.bodies["/video-init"] = make_init_segment([(8, b"vide")])
    client = await proxy_factory()
    response = await client.get(
        "/m3u8", params={"u": cdn.url("/master"), "variant": cdn.url("/video")}
    )
    assert response.status == 200
    body = await response.text()
    assert 'AUDIO="en"' in body and 'SUBTITLES="subs"' in body
    assert 'GROUP-ID="other"' not in body and "stitch-demux" not in body
    audio_link = next(
        line.split('URI="')[1].split('"')[0]
        for line in body.splitlines()
        if line.startswith("#EXT-X-MEDIA:TYPE=AUDIO")
    )
    audio_response = await client.get(URL(audio_link).relative())
    assert audio_response.status == 200
    init_link = (await audio_response.text()).split('URI="')[1].split('"')[0]
    init_response = await client.get(URL(init_link).relative())
    assert init_response.status == 200
    assert extract_track_map(await init_response.read()) == {7: "audio"}  # Original single track.


async def test_bundled_master_children_are_media_playlists_not_nested_masters(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = (
        b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000,CODECS="avc1.640028,mp4a.40.2"\nv\n'
    )
    cdn.bodies["/v"] = b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="init"\n#EXTINF:2,\ns\n'
    cdn.bodies["/init"] = make_init_segment([(1, b"vide"), (2, b"soun")])
    client = await proxy_factory()
    response = await client.get("/m3u8", params={"u": cdn.url("/master")})
    body = await response.text()
    links = [line for line in body.splitlines() if line.startswith("http")]
    assert len(links) == 1 and 'AUDIO="stitch-demux-' in body
    child = await client.get(URL(links[0]).relative())
    assert child.status == 200
    media_body = await child.text()
    assert "#EXTINF:" in media_body and "#EXT-X-STREAM-INF:" not in media_body
    assert "i=" in media_body


async def test_multiple_allowed_variants_and_unknown_selection(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = (
        b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\none\n"
        b"#EXT-X-STREAM-INF:BANDWIDTH=2\ntwo\n#EXT-X-STREAM-INF:BANDWIDTH=3\nthree\n"
    )
    client = await proxy_factory()
    params = {"u": cdn.url("/master"), "variants": json.dumps([cdn.url("/one"), cdn.url("/three")])}
    params["demuxVariants"] = "[]"
    response = await client.get("/m3u8", params=params)
    assert response.status == 200
    body = await response.text()
    assert "BANDWIDTH=1" in body and "BANDWIDTH=3" in body and "BANDWIDTH=2" not in body
    invalid = await client.get(
        "/m3u8", params={"u": cdn.url("/master"), "variant": cdn.url("/unknown")}
    )
    assert invalid.status == 502


async def test_already_separated_variant_and_ts_are_not_given_fake_audio(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/init"] = make_init_segment([(5, b"vide")])
    cdn.bodies["/v"] = b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="init"\n#EXTINF:2,\ns\n'
    cdn.bodies["/ts"] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.ts\n"
    cdn.bodies["/s.ts"] = b"TS-payload"
    client = await proxy_factory()
    for path in ("/v", "/ts"):
        response = await client.get("/m3u8", params={"u": cdn.url(path)})
        assert response.status == 200
        body = await response.text()
        assert "#EXT-X-MEDIA:" not in body and "mode=passthrough" in body
    link = next(line for line in body.splitlines() if line.startswith("http"))
    segment = await client.get(URL(link).relative())
    assert await segment.read() == b"TS-payload"


@pytest.mark.parametrize("chunked", [False, True])
async def test_oversized_body_is_rejected_without_caching(
    cdn: FakeCDN, proxy_factory: Any, chunked: bool
) -> None:
    cdn.bodies["/large"] = b"x" * 256
    cdn.chunked = chunked
    client = await proxy_factory(max_segment_bytes=64)
    response = await client.get(
        "/s", params={"u": cdn.url("/large"), "k": "media", "mode": "passthrough"}
    )
    assert response.status in {502, 504}
    assert not client.app[STORE_KEY].cache and not client.app[STORE_KEY].pending


async def test_byte_cache_eviction_and_fetch_concurrency_are_bounded(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    for index in range(6):
        cdn.bodies[f"/data-{index}"] = bytes([index]) * 32
    cdn.delay = 0.01
    client = await proxy_factory(segment_cache_bytes=64, max_upstream_concurrency=2)
    responses = await asyncio.gather(
        *(
            client.get(
                "/s", params={"u": cdn.url(f"/data-{index}"), "k": "media", "mode": "passthrough"}
            )
            for index in range(6)
        )
    )
    assert all(response.status == 200 for response in responses)
    for response in responses:
        await response.read()
    store = client.app[STORE_KEY]
    assert store.cached_bytes <= 64 and len(store.cache) <= 2 and not store.pending
    assert cdn.peak <= 2


async def test_deadline_and_redacted_fetch_error(
    cdn: FakeCDN, proxy_factory: Any, caplog: Any
) -> None:
    cdn.delay = 0.1
    client = await proxy_factory(upstream_total_timeout=0.02)
    response = await client.get(
        "/m3u8",
        params={"u": cdn.url("/slow") + "?token=fixture-only-token&sig=fixture-only-signature"},
    )
    assert response.status in {502, 504}
    assert "fixture-only-token" not in caplog.text and "fixture-only-signature" not in caplog.text
    assert "fixture-only-token" not in await response.text()


async def test_cancelling_waiter_does_not_cancel_shared_fetch(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.delay = 0.02
    cdn.bodies["/data"] = b"shared"
    client = await proxy_factory()
    first = asyncio.create_task(_fetch_cached(client.app, cdn.url("/data"), None))
    await asyncio.wait_for(cdn.started.wait(), 1)
    second = asyncio.create_task(_fetch_cached(client.app, cdn.url("/data"), None))
    first.cancel()
    with pytest.raises(asyncio.CancelledError):
        await first
    assert (await second).body == b"shared"
    assert cdn.hits["/data"] == 1 and not client.app[STORE_KEY].pending


async def test_forwarded_host_is_ignored_and_explicit_base_is_used(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv\n"
    cdn.bodies["/v"] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.ts\n"
    for base in (None, "https://proxy.example.invalid/prefix"):
        client = await proxy_factory(proxy_public_url=base)
        response = await client.get(
            "/m3u8",
            params={"u": cdn.url("/master")},
            headers={"X-Forwarded-Host": "attacker.invalid", "X-Forwarded-Proto": "https"},
        )
        body = await response.text()
        assert response.status == 200 and "attacker.invalid" not in body
        if base:
            assert base + "/m3u8" in body


async def test_redirect_is_rejected_before_target_receives_request(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.redirects["/start"] = cdn.url("/target")
    client = await proxy_factory(upstream_host_allowlist=("localhost",))
    # Initial loopback access is explicitly allowed for fixtures. Redirect goes to
    # a hostname outside that allowlist, so automatic redirect following would leak.
    initial = cdn.url("/start").replace("127.0.0.1", "localhost")
    response = await client.get("/m3u8", params={"u": initial})
    assert response.status == 400
    assert cdn.hits["/start"] == 1 and cdn.hits["/target"] == 0


async def test_production_redirect_to_private_literal_never_connects(
    proxy_factory: Any, monkeypatch: Any
) -> None:
    client = await proxy_factory(
        allow_unsafe_upstream=False, upstream_host_allowlist=("ttvnw.net", "169.254.169.254")
    )
    calls: list[str] = []

    @asynccontextmanager
    async def get(url: str, **kwargs: Any) -> Any:
        calls.append(url)
        yield SimpleNamespace(
            status=302, url=URL(url), headers={"Location": "http://169.254.169.254/metadata"}
        )

    monkeypatch.setattr(client.app[SESSION_KEY], "get", get)
    response = await client.get("/m3u8", params={"u": "https://edge.ttvnw.net/start"})
    assert response.status == 400 and calls == ["https://edge.ttvnw.net/start"]


class StubResolver(AbstractResolver):
    def __init__(self, addresses: list[str]) -> None:
        self.addresses = addresses

    async def resolve(
        self, host: str, port: int = 0, family: socket.AddressFamily = socket.AF_INET
    ) -> list[ResolveResult]:
        return [
            ResolveResult(hostname=host, host=address, port=port, family=family, proto=0, flags=0)
            for address in self.addresses
        ]

    async def close(self) -> None:
        pass


@pytest.mark.parametrize(
    "address",
    [
        "127.0.0.1",
        "192.168.0.1",
        "169.254.169.254",
        "100.64.0.1",
        "::1",
        "fc00::1",
        "::ffff:192.168.1.1",
        "0.0.0.0",
    ],
)
async def test_dns_answers_never_allow_non_global_addresses(address: str) -> None:
    resolver = PublicResolver(StubResolver(["1.1.1.1", address]))
    with pytest.raises(OSError, match="non-global"):
        await resolver.resolve("edge.ttvnw.net")


async def test_public_dns_answers_are_the_exact_connector_results() -> None:
    resolver = PublicResolver(StubResolver(["1.1.1.1", "2606:4700:4700::1111"]))
    result = await resolver.resolve("edge.ttvnw.net", 443)
    assert [record["host"] for record in result] == ["1.1.1.1", "2606:4700:4700::1111"]


@pytest.mark.parametrize(
    "url",
    [
        "file:///tmp/segment",
        "http://user:password@edge.ttvnw.net/media",
        "https://edge.ttvnw.net\\evil.invalid/media",
        "https://edge.ttvnw.net:99999/media",
        "https://evilttvnw.net/media",
        "https://edge.ttvnw.net/media#fragment",
    ],
)
def test_invalid_upstream_urls_cannot_bypass_validation(url: str) -> None:
    with pytest.raises(web.HTTPBadRequest):
        validate_upstream_url(url, ("ttvnw.net",))


async def test_busy_requests_fail_promptly_while_health_remains_available(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.gate = asyncio.Event()
    cdn.bodies["/data"] = b"data"
    client = await proxy_factory(max_inflight_requests=1)
    first = asyncio.create_task(
        client.get("/s", params={"u": cdn.url("/data"), "k": "media", "mode": "passthrough"})
    )
    try:
        await asyncio.wait_for(cdn.started.wait(), 1)
        busy = await client.get("/m3u8", params={"u": cdn.url("/playlist")})
        assert busy.status == 503
        assert (await client.get("/health")).status == 200
    finally:
        cdn.gate.set()
    assert (await first).status == 200


async def test_reload_parameters_are_forwarded_without_dropping_existing_query(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/live"] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns\n"
    client = await proxy_factory()
    response = await client.get(
        "/m3u8",
        params={
            "u": cdn.url("/live") + "?existing=fixture",
            "mode": "passthrough",
            "_HLS_msn": "12",
            "_HLS_part": "3",
            "_HLS_skip": "v2",
        },
    )
    assert response.status == 200
    assert cdn.queries == [
        {"existing": "fixture", "_HLS_msn": "12", "_HLS_part": "3", "_HLS_skip": "v2"}
    ]
    invalid = await client.get("/m3u8", params={"u": cdn.url("/live"), "_HLS_skip": "123"})
    assert invalid.status == 400 and cdn.hits["/live"] == 1


@pytest.mark.parametrize(
    "selection", ['["x"]', '{"url":"https://example.invalid"}', "[]", "[1]", "null"]
)
async def test_malformed_variant_selection_does_not_contact_upstream(
    cdn: FakeCDN, proxy_factory: Any, selection: str
) -> None:
    client = await proxy_factory()
    response = await client.get("/m3u8", params={"u": cdn.url("/master"), "variants": selection})
    assert response.status == 400 and not cdn.hits


@pytest.mark.parametrize("value", ["-1@0", "0@0", "10", "x@0", "1@" + "1" * 65])
async def test_invalid_range_query_fails_without_fetching(
    cdn: FakeCDN, proxy_factory: Any, value: str
) -> None:
    client = await proxy_factory()
    response = await client.get(
        "/s",
        params={
            "u": cdn.url("/media"),
            "k": "media",
            "mode": "passthrough",
            "r": value,
        },
    )
    assert response.status == 400 and not cdn.hits


@pytest.mark.parametrize("explicit", [False, True])
async def test_native_ts_codecs_do_not_trigger_cmaf_audio_synthesis(
    cdn: FakeCDN, proxy_factory: Any, explicit: bool
) -> None:
    # Matches the shape verified in an anonymous public Twitch capture:
    # TS STREAM-INF still advertises both AVC and AAC.
    cdn.bodies["/master"] = (
        b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=6000000,"
        b'CODECS="avc1.64002A,mp4a.40.2",RESOLUTION=1920x1080\nnative\n'
    )
    cdn.bodies["/native"] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.ts\n"
    cdn.bodies["/s.ts"] = b"native-ts-with-video-and-audio"
    client = await proxy_factory()
    params = {"u": cdn.url("/master")}
    if explicit:
        params["demuxVariants"] = "[]"
    response = await client.get("/m3u8", params=params)
    assert response.status == 200
    body = await response.text()
    assert "#EXT-X-MEDIA:" not in body and "track=audio" not in body
    if explicit:
        assert cdn.hits["/native"] == 0  # Caller verified the format; no duplicate probing.
    child_link = next(line for line in body.splitlines() if line.startswith("http"))
    child = await client.get(URL(child_link).relative())
    assert child.status == 200
    child_body = await child.text()
    segment_link = next(line for line in child_body.splitlines() if line.startswith("http"))
    segment = await client.get(URL(segment_link).relative())
    assert segment.status == 200 and await segment.read() == b"native-ts-with-video-and-audio"


async def test_explicit_demux_selection_must_match_selected_master(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\none\n"
    client = await proxy_factory()
    response = await client.get(
        "/m3u8",
        params={
            "u": cdn.url("/master"),
            "demuxVariants": json.dumps([cdn.url("/missing")]),
        },
    )
    assert response.status == 502 and cdn.hits == {"/master": 1}


async def test_muxed_video_can_be_split_while_preserving_external_audio(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = (
        b'#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="external",NAME="Audio",URI="audio"\n'
        b'#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028,mp4a.40.2",AUDIO="external"\nvideo\n'
    )
    cdn.bodies["/video"] = (
        b'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="muxed-init"\n#EXTINF:2,\nmedia\n'
    )
    cdn.bodies["/muxed-init"] = make_init_segment([(7, b"vide"), (8, b"soun")])
    client = await proxy_factory()
    response = await client.get("/m3u8", params={"u": cdn.url("/master")})
    assert response.status == 200
    body = await response.text()
    assert 'AUDIO="external"' in body and body.count("#EXT-X-MEDIA:") == 1
    video_link = next(line for line in body.splitlines() if line.startswith("http"))
    video = await client.get(URL(video_link).relative())
    init_link = (await video.text()).split('URI="')[1].split('"')[0]
    init = await client.get(URL(init_link).relative())
    assert init.status == 200 and extract_track_map(await init.read()) == {1: "video"}
