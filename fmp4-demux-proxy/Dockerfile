# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: builder -- install dependencies with uv (reproducible from lock)
# ---------------------------------------------------------------------------
FROM python:3.14-slim AS builder

# Pinned by digest for reproducible builds; Dependabot watches the `:TAG` part.
# Tag: 0.11.7
COPY --from=ghcr.io/astral-sh/uv:0.11.7@sha256:240fb85ab0f263ef12f492d8476aa3a2e4e1e333f7d67fbdd923d00a506a516a /uv /bin/uv

WORKDIR /build

# Install deps from lock file first (cacheable layer — only busts on lock change)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-editable

# Copy source and install the project itself
COPY src/ src/
COPY README.md README.md
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-editable

# ---------------------------------------------------------------------------
# Stage 2: runtime -- minimal image, non-root user
# ---------------------------------------------------------------------------
FROM python:3.14-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/tree/main/fmp4-demux-proxy" \
      org.opencontainers.image.description="HLS/fMP4 proxy that demuxes Twitch EB streams for Roku playback"

RUN groupadd --gid 1000 fmp4demux \
    && useradd --uid 1000 --gid fmp4demux --shell /bin/false fmp4demux

COPY --from=builder /build/.venv /app/.venv

WORKDIR /app

ENV PATH="/app/.venv/bin:$PATH"
ENV PORT=8080

USER fmp4demux

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "-m", "fmp4_demux_proxy"]
