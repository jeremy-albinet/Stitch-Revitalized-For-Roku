# Changelog

All notable changes to `fmp4-demux-proxy` are documented here.

## [0.3.0] - Unreleased

### Fixed
- Preserve filtered adaptive qualities when Twitch rotates rendition URLs between master requests. A separate `/m3u8/selected` endpoint matches complete URL-free rendition and referenced-group descriptions, selects only fresh approved URLs and inspects their current tracks.
- Reject changed, missing, ambiguous or shared-URL selections before serving media. Preserve existing exact-URL contracts, DNS/redirect protections, limits and signed query strings; older services return 404 for the new endpoint.
- Add 126 selection/schema/security/resource regressions, bringing the proxy suite to 309 tests on Python 3.12 and 3.14. Client-produced request interoperability is also verified.

## [0.2.0] - Unreleased

- Resolve exact init URL/range for every media request; coalesce audio/video fetches and fail closed on missing tracks or unsupported sample addressing.
- Preserve sample bytes and offsets through discontinuities, out-of-order requests and cache eviction. Support verified source byte ranges and independent output ranges.
- Filter single/automatic variants while preserving external audio/subtitles; generate real audio/video child media playlists for bundled CMAF masters.
- Classify containers from verified caller information or bounded variant/init inspection, never CODECS alone; preserve ordinary AVC+AAC TS ladders.
- Omit unknown codec hints rather than mislabeling HEVC as AVC. Preserve rendition-report tracks and bounded HLS reload parameters.
- Validate every redirect before connecting and enforce non-global-address checks on the DNS records actually used by the connector.
- Bound deadlines, body sizes, cache bytes, request admission and concurrent fetches. Omit signed URLs from logs and ignore untrusted forwarded headers.
- Update aiohttp to 3.14.4, yarl to 1.25.1, patched multidict to 6.9.1, and the verified digest-pinned uv image to 0.12.23.
- Harden Compose and document direct Python execution as an alternative to Docker.
- Add executable regression fixtures for media order, discontinuities, ranges, rendition relationships, malformed samples and resource/security boundaries.

## [0.1.0] - 2026-04-18

Initial release.

### Added
- HLS manifest proxy (`/m3u8`) with URL rewriting
- fMP4 segment proxy (`/s`) with on-the-fly demuxing into separate audio and video tracks
- Synthetic demuxed master playlist generation from muxed Twitch variant playlists
- `split_moov` and `split_moof_mdat` for pure-Python fMP4 box splitting without remuxing
- Async dedup cache (LRU-50 + per-URL lock) to share upstream fetches between concurrent audio/video requests
- Health check endpoint (`/health`) returning service version
- Multi-stage Docker image using uv for reproducible installs (non-root, healthcheck)
- Docker Compose configuration with `PROXY_PUBLIC_URL` passthrough
- 71 tests (pytest + pytest-aiohttp)
