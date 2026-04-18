# fmp4-demux-proxy

A lightweight self-hosted proxy that demuxes Twitch Enhanced Broadcasting (EB) muxed fMP4 HLS streams into separate audio and video tracks — the format Roku requires for playback.

## Problem

Twitch Enhanced Broadcasting streams deliver muxed fMP4 HLS: a single media playlist containing both audio and video in the same segments. Roku devices only support demuxed HLS (separate audio and video renditions declared via `#EXT-X-MEDIA:TYPE=AUDIO`). Without demuxing, Roku either fails with error 970 or plays video with no audio.

Bug reference: [jeremy-albinet/roku-fmp4-track-order-bug](https://github.com/jeremy-albinet/roku-fmp4-track-order-bug)

## How It Works

```
                    fmp4-demux-proxy
                   +----------------------------------+
  Roku Device      |                                  |   Twitch CDN
  +-----------+    |  GET /m3u8?u=<upstream>          |  +----------+
  |           | -> |  → synthesize demuxed master     | -> |        |
  | Stitch    |    |                                  |    | usher/ |
  | Channel   |    |  GET /m3u8?u=<upstream>&track=*  |    | CF CDN |
  |           | <- |  → rewrite segment URLs          | <- |        |
  |           |    |                                  |    +--------+
  |           |    |  GET /s?u=<url>&k=*&track=video  |
  |           |    |  GET /s?u=<url>&k=*&track=audio  |
  |           | <- |  → split moof+mdat per track     |
  +-----------+    +----------------------------------+
```

The Stitch channel points `content.url` at `/m3u8?u=<upstream>`. The proxy returns a synthetic master playlist with separate video and audio renditions; Roku's HLS player fetches each independently via the `&track=` URLs, and the proxy splits the muxed fMP4 segments on the fly.

### Routes

| Route | Purpose |
|-------|---------|
| `GET /m3u8?u=<url>` | Proxy master playlist (rewrites variant URLs) or synthesize demuxed master from a variant |
| `GET /m3u8?u=<url>&track=video\|audio` | Rewrite variant playlist segment URLs with `&track=` |
| `GET /s?u=<url>&k=init\|media&track=video\|audio` | Fetch and split fMP4 init/media segments |
| `GET /health` | Health check — returns `{"status":"ok","version":"..."}` |

## Getting Started

### Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (recommended) — or pip

### Run Locally

```bash
# Install dev dependencies
uv sync

# Start the server (listens on :8080)
python -m fmp4_demux_proxy
```

### Run with Docker

```bash
# Build and start
docker compose up -d

# Tail logs
docker compose logs -f
```

The image is also published to GitHub Container Registry:

```bash
docker run -p 8080:8080 ghcr.io/jeremy-albinet/fmp4-demux-proxy:main
```

### Point the Stitch Channel at the Proxy

In the Stitch channel's **Settings → Proxy URL**, enter the proxy's address as reachable from your Roku:

```
http://192.168.1.50:8080
```

Leave empty to disable the proxy (regular Twitch streams are unaffected).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Listening port |
| `LOG_LEVEL` | `INFO` | Log verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`) |
| `PROXY_PUBLIC_URL` | *(auto)* | Public base URL of the proxy as seen by the Roku. Auto-detected from request headers for most setups. Set explicitly when running behind a reverse proxy: `http://192.168.1.50:8080` |
| `UPSTREAM_CONNECT_TIMEOUT` | `5.0` | Seconds to wait for Twitch CDN TCP connect |
| `UPSTREAM_READ_TIMEOUT` | `30.0` | Seconds to wait for Twitch CDN response bytes |

Copy `.env.example` to `.env` and adjust as needed.

## Development

```bash
# Lint
ruff check src/ tests/

# Format
ruff format src/ tests/

# Test
pytest

# Docker build
docker build -t fmp4-demux-proxy .
```

## License

See the parent repository's [LICENSE](../LICENSE).
