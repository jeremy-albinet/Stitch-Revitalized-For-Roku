"""fmp4-demux-proxy: HLS/fMP4 proxy that demuxes Twitch muxed fMP4 HLS streams for Roku playback."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("fmp4-demux-proxy")
except PackageNotFoundError:
    __version__ = "0.0.0.dev0"
