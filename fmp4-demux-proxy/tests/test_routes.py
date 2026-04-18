"""Integration tests for the /m3u8 and /s routes with a fake upstream."""

from __future__ import annotations

from urllib.parse import parse_qs, quote, unquote, urlparse

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from fmp4_demux_proxy.app import create_app
from tests._fixtures import make_init_segment, make_media_segment
from tests.conftest import make_test_config


@pytest.fixture
async def upstream() -> TestServer:
    app = web.Application()
    app["master"] = b""
    app["variant"] = b""
    app["init"] = b""
    app["media"] = b""
    app["status"] = {"/master": 200, "/variant": 200, "/init.mp4": 200, "/seg-1.m4s": 200}

    async def master_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/master"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(
            body=request.app["master"], content_type="application/vnd.apple.mpegurl"
        )

    async def variant_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/variant"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(
            body=request.app["variant"], content_type="application/vnd.apple.mpegurl"
        )

    async def init_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/init.mp4"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(body=request.app["init"], content_type="video/mp4")

    async def media_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/seg-1.m4s"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(body=request.app["media"], content_type="video/mp4")

    app.router.add_get("/master", master_h)
    app.router.add_get("/variant", variant_h)
    app.router.add_get("/init.mp4", init_h)
    app.router.add_get("/seg-1.m4s", media_h)

    server = TestServer(app)
    await server.start_server()
    try:
        yield server
    finally:
        await server.close()


@pytest.fixture
async def proxy_client(aiohttp_client) -> TestClient:
    app = create_app(config=make_test_config())
    return await aiohttp_client(app)


class TestM3U8Route:
    async def test_missing_params_400(self, proxy_client: TestClient) -> None:
        resp = await proxy_client.get("/m3u8")
        assert resp.status == 400

    async def test_upstream_500_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        upstream.app["status"]["/master"] = 500
        upstream.app["master"] = b"ignored"
        upstream_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 502

    async def test_master_rewrites_variant_urls(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        variant_url = str(upstream.make_url("/variant"))
        master_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            '#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS="hev1.1.6.L150.B0"\n'
            f"{variant_url}\n"
        ).encode()
        upstream.app["master"] = master_body

        upstream_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 200
        body = await resp.text()
        assert "/m3u8?u=" in body
        assert variant_url not in body
        proxied_line = next(
            ln for ln in body.splitlines() if "/m3u8?u=" in ln and not ln.startswith("#")
        )
        qs = parse_qs(urlparse(proxied_line).query)
        assert unquote(qs["u"][0]) == variant_url

    async def test_variant_rewrites_segment_and_init(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_url = str(upstream.make_url("/init.mp4"))
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        variant_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            f'#EXT-X-MAP:URI="{init_url}"\n'
            "#EXTINF:2.000,\n"
            f"{seg_url}\n"
        ).encode()
        upstream.app["variant"] = variant_body

        upstream_url = str(upstream.make_url("/variant"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}&track=video")
        assert resp.status == 200
        body = await resp.text()

        map_line = next(ln for ln in body.splitlines() if ln.startswith("#EXT-X-MAP:"))
        seg_line = next(ln for ln in body.splitlines() if not ln.startswith("#") and "/s?" in ln)
        assert "k=init" in map_line
        assert "k=media" in seg_line
        assert init_url not in body
        assert seg_url not in body


class TestSegmentRoute:
    async def test_missing_params_400(self, proxy_client: TestClient) -> None:
        assert (await proxy_client.get("/s")).status == 400

    async def test_invalid_kind_400(self, proxy_client: TestClient, upstream: TestServer) -> None:
        upstream_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(upstream_url, safe='')}&k=garbage")
        assert resp.status == 400

    async def test_init_segment_rewritten_video_first(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        upstream.app["init"] = init_bytes

        upstream_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(upstream_url, safe='')}&k=init&track=video")
        assert resp.status == 200
        body = await resp.read()
        assert resp.headers["Content-Type"] == "video/mp4"
        from fmp4_demux_proxy.fmp4 import extract_track_map, iter_top_level_boxes

        boxes = list(iter_top_level_boxes(body))
        assert any(h.type == b"moov" for h, _ in boxes)
        tm = extract_track_map(body)
        assert tm == {1: "video"}

    async def test_media_segment_with_cached_map_rewritten(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        upstream.app["init"] = init_bytes
        init_url = str(upstream.make_url("/init.mp4"))
        init_resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert init_resp.status == 200
        await init_resp.read()

        media_bytes = make_media_segment(sequence=1, trafs=[1, 2])
        upstream.app["media"] = media_bytes
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        seg_resp = await proxy_client.get(f"/s?u={quote(seg_url, safe='')}&k=media&track=video")
        assert seg_resp.status == 200
        body = await seg_resp.read()
        assert len(body) < len(media_bytes)

    async def test_media_without_cached_map_passes_through(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        media_bytes = make_media_segment(sequence=1, trafs=[1, 2])
        upstream.app["media"] = media_bytes
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        resp = await proxy_client.get(f"/s?u={quote(seg_url, safe='')}&k=media&track=video")
        assert resp.status == 200
        body = await resp.read()
        assert body == media_bytes

    async def test_upstream_failure_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        upstream.app["status"]["/init.mp4"] = 404
        init_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert resp.status == 502
