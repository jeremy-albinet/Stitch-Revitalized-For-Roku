# Changelog

All notable changes to `fmp4-demux-proxy` are documented here.

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
