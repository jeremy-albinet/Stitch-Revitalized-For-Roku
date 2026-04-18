# AGENTS.md -- fmp4-demux-proxy

## Overview

This directory contains `fmp4-demux-proxy`, a Python/aiohttp HLS/fMP4 proxy that demuxes Twitch Enhanced Broadcasting (EB) muxed fMP4 HLS streams into separate audio and video tracks for Roku playback.

Twitch EB streams deliver a single muxed HLS variant containing both audio and video. Roku requires demuxed HLS (`#EXT-X-MEDIA:TYPE=AUDIO` with separate renditions). This proxy synthesizes a demuxed master playlist and splits fMP4 segments on the fly.

Bug reference: https://github.com/jeremy-albinet/roku-fmp4-track-order-bug

**The parent repo is a Roku BrightScript project. This subdirectory is Python. Do NOT apply BrightScript conventions here.**

## Relationship to Main Repo

`fmp4-demux-proxy` is shipped alongside the Roku channel but is logically separable. It runs as a standalone Docker service. The Roku device calls into it at runtime when playing Enhanced Broadcasting streams. The channel is configured with the proxy URL via **Settings → Proxy URL**.

## Build, Lint, Test, Format

All commands run from inside `fmp4-demux-proxy/`.

```bash
uv sync                        # install dev dependencies
ruff check src/ tests/         # lint
ruff format src/ tests/        # format
pytest                         # test
docker build -t fmp4-demux-proxy .   # Docker image
docker compose up -d           # run via Compose
```

## Conventions

- **Python 3.12** minimum. Use modern syntax (`X | Y` unions, `match`, PEP 695 type aliases).
- **Type hints required** on all function signatures.
- **Async-first**: no synchronous I/O in the request path. Use `aiohttp.ClientSession` for outbound HTTP.
- **Line length**: 100 characters.
- **Linter/Formatter**: ruff (configured in `pyproject.toml`). No mypy, black, or isort.
- **Testing**: pytest + pytest-aiohttp. Use the `client` fixture from `conftest.py` for integration tests.
- **`src/` layout**: all production code under `src/fmp4_demux_proxy/`. Tests in `tests/`.

## Architecture

### URL Scheme

```
GET /m3u8?u=<upstream_url>
    → if upstream is a variant playlist: synthesize a demuxed master playlist
      with separate video stream + audio rendition, both pointing back through
      /m3u8?u=<upstream>&track=video|audio
    → if upstream is a master playlist: proxy it, rewriting variant URLs

GET /m3u8?u=<upstream_url>&track=video|audio
    → proxy the variant playlist, rewriting all segment/init/part URLs to
      /s?u=<seg_url>&k=<kind>&track=video|audio

GET /s?u=<seg_url>&k=init|media&track=video|audio
    → fetch the muxed fMP4 segment from Twitch CDN (with async dedup cache)
    → split: return only the moov/moof+mdat for the requested track
    → track IDs are remapped to 1 for Roku compatibility

GET /health
    → {"status":"ok","version":"<version>"}
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `app.py` | aiohttp application factory |
| `config.py` | Environment-based configuration |
| `fmp4.py` | Pure fMP4 box parsing and splitting (`split_moov`, `split_moof_mdat`) |
| `manifest.py` | HLS manifest rewriting and master playlist synthesis |
| `upstream.py` | Shared outbound `aiohttp.ClientSession` lifecycle |
| `routes/m3u8_route.py` | `/m3u8` handler |
| `routes/segment_route.py` | `/s` handler with async dedup cache |
| `routes/health.py` | `/health` handler |

### Segment Cache

`segment_route.py` maintains an LRU cache (50 entries) + per-URL `asyncio.Lock` to deduplicate concurrent requests for the same segment. Both video and audio tracks fetch the same upstream URL; the lock ensures the upstream is fetched once and the result shared.

## Security

- NEVER reference or hardcode any Twitch or Roku credentials in code or tests.
- No authentication layer. For public deployments, use firewall IP allowlists or a reverse proxy with auth.
