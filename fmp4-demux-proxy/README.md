# fmp4-demux-proxy

An optional service for Stitch that separates Twitch Enhanced Broadcasting audio and video samples without transcoding. **Docker is optional.** You can run the same Python service directly on a computer reachable from your Roku.

Roku supports HLS CMAF with separate audio and video renditions; it does not support combined audio/video CMAF. The relevant Twitch streams bundle both tracks. Splitting those tracks addresses the error-970/silent-audio packaging problem while preserving video quality. Ordinary compatible streams bypass the service. The service does not make an unsupported codec playable, and 1440p/low-latency results still require Roku hardware verification.

References: [Roku streaming specification](https://developer.roku.com/dev/docs/specs/media), [upstream hardware reproduction](https://github.com/jeremy-albinet/roku-fmp4-track-order-bug), and [HLS format and byte-range rules](https://datatracker.ietf.org/doc/html/rfc8216).

## Run without Docker

From this directory, with Python 3.12+ and [uv](https://docs.astral.sh/uv/):

```bash
uv sync --locked --no-dev
uv run --locked python -m fmp4_demux_proxy
```

The server listens on port 8080. To load your configuration from a file, copy `.env.example` to `.env` and run:

```bash
uv run --locked --env-file .env python -m fmp4_demux_proxy
```

You can also install with `python -m pip install .` inside a virtual environment, then run `python -m fmp4_demux_proxy`. The uv path uses the checked-in dependency lock.

In **Stitch → Settings → Proxy URL**, enter an address reachable from the Roku, such as `http://192.168.1.50:8080`. The computer must remain running while a stream uses the service. `localhost` in the Roku setting refers to the Roku itself. Allow the listening port through the computer's local firewall.

Verify setup with `http://192.168.1.50:8080/health`; the response contains `"status":"ok"`. Leave Proxy URL empty when you do not need the service.

Use service version 0.3.0 or later with this channel update. Filtered Automatic and manual external-audio selection use the new `/m3u8/selected` endpoint, matching complete approved rendition and group descriptions against fresh Twitch URLs. Older services lack this endpoint and fail closed instead of offering an unfiltered quality ladder. Direct bundled-child splitting and older callers retain `/m3u8`.

## Run with Docker

```bash
docker compose up -d --build
docker compose logs -f
```

Compose passes supported settings from `.env` and uses a read-only filesystem, nonroot user, no Linux capabilities, and memory/process limits. The image uses Python 3.15.1 on Debian Trixie and a uv installer, both pinned by multiarch digest, with locked production dependencies.

The shared build/runtime base refreshes `ca-certificates` and regenerates the system store. Builds and container CI require Debian's patched package `20250419+deb13u1` or newer and check Python's active TLS roots, including OpenSSL's hashed CA directory. The check rejects the exact DER SHA-256 fingerprints of **emSign ECC Root CA - G3** and **AAA Certificate Services** (Debian's label: "Comodo AAA Services root"), following the [Debian security update](https://tracker.debian.org/news/1813397/accepted-ca-certificates-20250419deb13u1-source-into-stable-security/). Other eMudhra/emSign roots remain governed by Debian's trust policy; this is not a blanket issuer ban. TLS certificate and hostname verification stay enabled.

To rebuild with a fresh CA package lookup, run `docker compose build --pull --no-cache` before `docker compose up -d`. Docker's build cache can otherwise reuse an earlier successful package refresh. For an existing container, run `docker compose exec fmp4-demux-proxy python /usr/local/bin/check-ca-trust.py` to print the installed CA package version and active root count, or fail if the policy is violated. Direct Python installations use the host's trust store and must receive their host's CA security updates separately.

After publication, the versioned release image is `ghcr.io/jeremy-albinet/fmp4-demux-proxy:0.3.2`. The moving `:main` tag follows published main. Both include the CA trust checks above; build this checkout to test changes before publication.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| PORT | 8080 | Listening port |
| LOG_LEVEL | INFO | Application log level |
| PROXY_PUBLIC_URL | Request scheme and Host | Base URL reachable by Roku; set explicitly behind a reverse proxy or when port/path mapping changes it |
| UPSTREAM_HOST_ALLOWLIST | ttvnw.net,twitch.tv,twitchcdn.net,cloudfront.net | Permitted upstream domain suffixes; enforced before every redirect |
| UPSTREAM_CONNECT_TIMEOUT | 5 | Connection deadline in seconds |
| UPSTREAM_READ_TIMEOUT | 30 | Read inactivity deadline in seconds |
| UPSTREAM_TOTAL_TIMEOUT | 45 | Deadline including queueing, redirect chain and response body |
| MAX_MANIFEST_BYTES | 2097152 | Maximum upstream playlist bytes; rewritten playlists are capped at four times this |
| MAX_SEGMENT_BYTES | 33554432 | Maximum upstream segment or init bytes |
| SEGMENT_CACHE_BYTES | 134217728 | Shared upstream cache byte limit; also capped at 50 entries |
| MAX_UPSTREAM_CONCURRENCY | 8 | Concurrent upstream fetches |
| MAX_INFLIGHT_REQUESTS | 64 | Concurrent admitted requests; excess traffic receives 503 |
| ALLOW_UNSAFE_UPSTREAM | false | Explicit development-only override for private/local addresses and an empty host allowlist |

All limits must be positive and finite. Private, loopback, link-local and other non-global IPs are blocked by default, including DNS answers and IPv4-mapped IPv6 addresses. The connector uses the validated DNS results directly. `ALLOW_UNSAFE_UPSTREAM` is deliberately absent from Compose's production environment.

Forwarded Host/Proto headers are ignored. Set `PROXY_PUBLIC_URL` to the correct HTTP(S) URL when using a reverse proxy. Signed upstream URLs and query strings are omitted from application/access logs; configure your reverse proxy to omit them too.

The service has no authentication. Keep it on a trusted LAN or put authenticated access/firewall rules in front of it. A populated host allowlist limits upstream destinations, but is not access control for clients.

## Playback and API behavior

- `GET /m3u8?u=<URL>` accepts a playlist. A bundled fMP4 variant becomes a master with separate audio/video. A direct variant's init is inspected first; already-separated CMAF or TS remains an ordinary media playlist.
- Codec, bandwidth and resolution hints use `codecs`, `bw`, and `res`. Supply the original master metadata for HEVC/1440p. Unknown codec hints are omitted, rather than replaced with a guessed AVC codec/profile.
- Master playlists retain existing external audio/subtitle relationships. Verified bundled CMAF entries gain separate audio/video media playlists; a video rendition that still contains embedded audio is split while preserving any declared external audio group. CODECS alone never determines the container: native TS also advertises AVC and AAC.
- `variant=<absolute URL>` filters a master to one exact entry. `variants=<JSON array of absolute URLs>` filters an automatic ladder. Selections must match the upstream master, contain 1–32 distinct URLs, and fit within 32 KiB decoded JSON.
- `demuxVariants=<JSON array of verified bundled URLs>` identifies the selected entries requiring demux. Use `[]` for native TS. The list must be a subset of selected entries and contain at most 32 URLs / 32 KiB decoded JSON. When omitted, the service inspects selected variant/init data with bounded concurrency and a whole-request deadline; providing verified format information avoids duplicate probing.
- The server accepts request lines up to 64 KiB to accommodate signed variant lists. A reverse proxy must allow corresponding URI sizes; otherwise it may reject automatic-quality requests before they reach this service.
- Internal `/s` links carry exact init URL (`i`), source range (`r=length@offset`), and init range (`ir`). Every media request resolves its own init. Request order, directory layout, cache eviction and discontinuity track-ID changes do not determine the track map.
- Audio/video consumers coalesce upstream requests. Init and media output contain only the requested track, remapped to track ID 1. Missing tracks or unsupported sample addressing return a clear error; original combined bytes are never returned as a separated rendition.
- Explicit and valid implicit source byte ranges are fetched and verified as HTTP 206 ranges. Their playlist tags are removed because the output is a separate resource. Client Range headers apply to the rewritten output, independently of source offsets.
- LL-HLS part/preload/rendition-report links and bounded blocking-reload parameters are preserved. This does not establish Roku LL-HLS support or guarantee a lower playback delay.

## Troubleshooting and limits

A 400 response can indicate an invalid URL, host policy, track, or missing init reference. A 502 indicates upstream failure/oversized input, unavailable tracks, unsupported addressing or a malformed manifest. A 504 indicates the whole-request deadline expired. A 503 means the service is busy; try again shortly.

Do not disable the allowlist to repair a new CDN hostname. Verify the actual stream host and add only the necessary trusted hostname/suffix. Additional historical VOD CDNs still need captured-stream verification.

Demux currently supports unencrypted fragments with movie-fragment-relative addressing, explicit sample-run offsets and resolvable sample sizes. Absolute/implicit fragment addressing, encrypted combined fragments, and open-ended preload ranges fail explicitly. A CDN that ignores a requested source byte range is also rejected. These constraints need captured-stream evidence before the splitter is extended.

A demuxed CMAF stream that changes to MPEG-TS during an ad is unsupported and returns 502 for those segments. The service does not send a combined transport stream into either separated rendition. Native MPEG-TS playlists still use the ordinary passthrough path. Mixed-container transitions need track separation, matching initialization and timeline handling, and Roku ad-boundary verification before support can be enabled.

A passing health check proves the service is reachable, not that a Roku can decode a selected stream. Confirm picture, audible audio, quality changes, VOD seeking and sustained playback on the target device.

## Development

```bash
uv sync --locked --all-extras
uv run --locked ruff check src tests
uv run --locked ruff format --check src tests
uv run --locked pytest
uv export --locked --no-dev --no-emit-project --output-file runtime-requirements.txt
uvx pip-audit==2.10.1 --disable-pip --require-hashes --strict -r runtime-requirements.txt
docker build -t fmp4-demux-proxy .
```

Tests use synthetic MP4 samples and local fixture servers with explicit unsafe configuration. No Twitch/Roku credentials or signed production streams are needed. Container build/health checks run in CI; the development machine used for this modernization has no Docker CLI.

See the parent repository's [LICENSE](../LICENSE).
