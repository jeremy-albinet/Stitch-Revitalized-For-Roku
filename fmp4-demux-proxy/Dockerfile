# syntax=docker/dockerfile:1

# Refresh once for both stages; tag and multiarch index verified on 2026-10-25.
FROM python:3.15.1-slim-trixie@sha256:533b0b2f9b5d46fd097091cf826f27902f1d6c3bca714b6dc74551356aa97a51 AS base

COPY src/fmp4_demux_proxy/ca_trust.py /usr/local/bin/check-ca-trust.py
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && update-ca-certificates --fresh \
    && python /usr/local/bin/check-ca-trust.py \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Stage 1: builder -- install dependencies with uv (reproducible from lock)
# ---------------------------------------------------------------------------
FROM base AS builder

# Pinned by digest for reproducible builds; Dependabot watches the `:TAG` part.
# Tag/digest verified against GHCR; Dependabot maintains the pin.
COPY --from=ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff /uv /bin/uv

WORKDIR /build

ENV UV_LINK_MODE=copy

# Install deps from lock file first (cacheable layer — only busts on lock change)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-editable --no-dev

# Copy source and install the project itself
COPY src/ src/
COPY README.md README.md
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-editable --no-dev

# ---------------------------------------------------------------------------
# Stage 2: runtime -- minimal image, non-root user
# ---------------------------------------------------------------------------
FROM base AS runtime

LABEL org.opencontainers.image.source="https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/tree/main/fmp4-demux-proxy" \
      org.opencontainers.image.description="HLS/fMP4 proxy that demuxes Twitch EB streams for Roku playback"

RUN groupadd --gid 1000 fmp4demux \
    && useradd --uid 1000 --gid fmp4demux --shell /bin/false fmp4demux

COPY --from=builder /build/.venv /app/.venv

WORKDIR /app

ENV PATH="/app/.venv/bin:$PATH"
ENV PORT=8080
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

USER fmp4demux

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=2)"]

CMD ["python", "-m", "fmp4_demux_proxy"]
