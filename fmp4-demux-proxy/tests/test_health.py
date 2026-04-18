"""Tests for the /health endpoint."""

from aiohttp.test_utils import TestClient


async def test_health_returns_200_with_status_and_version(client: TestClient) -> None:
    resp = await client.get("/health")
    assert resp.status == 200
    body = await resp.json()
    assert body["status"] == "ok"
    assert "version" in body
