[![CI](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/actions/workflows/ci.yml/badge.svg)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/release/jeremy-albinet/Stitch-Revitalized-For-Roku?include_prereleases=&sort=semver&color=blue)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/)
[![Discord](https://img.shields.io/discord/1563625177164546261?logo=discord&logoColor=white&label=Discord&color=5865F2)](https://discord.gg/tZFrCAMxnB)

# Stitch Revitalized

A feature-complete Twitch client for Roku.

| Cumulative installs | New installs (Mar 2025) | Avg daily viewers | Avg session | Hours streamed (Mar 2025) |
|---|---|---|---|---|
| 694,449 | 93,163 | 16,598 | ~2h | 971,218 |

## Features

- Browse live streams by category, search, or followed channels
- Live chat beside the video or over full-size video, with four corner positions and adjustable background opacity
- Separate Pinned and Live sidebar sections, per-profile pins and individual local removal
- VOD and clip playback
- Auto-reconnect after mid-roll ads
- Respects Twitch's business model: ads and monetization work as intended
- Anonymous browsing without login; sign in to access followed channels and chat

## Modernized interface and playback

This checkout integrates the 3.1.0 interface, playback and chat work from [Narehood's fork](https://github.com/Narehood/Stitch-Revitalized-For-Roku), retaining this project's support links and release history. Build the checkout to test these changes before they appear in a published release.

- Choose a preferred startup resolution with a lower playable fallback.
- Open a streamer's channel, pin/unpin, and check Follow/Unfollow status from player Channel actions.
- Display Unicode emoji, highlighted mentions, provider emotes and pinned author badges. Compatible devices animate one visible BTTV/7TV emote or eligible Twitch subscriber GIF at a time; static images or titles remain available as fallbacks.
- Choose synchronized or live chat timing. Hype Trains, pinned messages and experimental Twitch watch credit are separate opt-in settings.
- Use clearer Settings choices, scroll indicators, player hints and bounded playback recovery. Lower live latency remains experimental and off by default.

## Support Stitch

Stitch remains free and community-built. Open **Settings > Support Stitch** to scan the existing Buy Me a Coffee QR, or visit [jeremyalbinet on Buy Me a Coffee](https://www.buymeacoffee.com/jeremyalbinet).

## Installation

**Channel Store (recommended)**

Add the channel directly from Roku's channel store:
[https://my.roku.com/account/add/TwitchRevitalized](https://my.roku.com/account/add/TwitchRevitalized)

**Sideload (manual)**

1. [Download the latest release ZIP](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/latest)
2. Enable Developer Mode on your Roku (Settings > System > Advanced System Settings > Developer Mode)
3. Open `http://<your-roku-ip>` in a browser and upload the ZIP

## Known Limitations

### Twitch Enhanced Broadcasting (1440p / multi-track HLS)

Streams using **Twitch Enhanced Broadcasting** deliver audio and video as two separate tracks bundled into a single HLS rendition (one segment file containing both an audio `traf` and a video `traf`, with audio listed first). Roku's Media Player implements fMP4 HLS as CMAF, which expects one elementary stream per HLS rendition (audio declared as a separate `EXT-X-MEDIA:TYPE=AUDIO` rendition). EB's single-rendition-with-two-tracks packaging therefore fails to load on Roku (error 970) or plays silent video.

Roku has officially confirmed they will not support this packaging shape. Twitch is aware but does not plan a server-side change. Affected streams are visible as "Enhanced Broadcasting" on the broadcaster's dashboard. Regular (non-EB) streams are unaffected.

**Playback options:** the built-in audio splitter handles eligible live streams and recordings on the Roku. The optional self-hosted [`fmp4-demux-proxy`](./fmp4-demux-proxy/README.md) splits bundled segments into separate audio and video HLS renditions; configure it under **Settings > Proxy URL**. Codec and device limits still apply. Mixed MPEG-TS ads inside separated proxy CMAF remain unsupported; ordinary native TS playback is preserved. See [issue #14](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues/14) for the full investigation and current status.

## Contributing

Found a bug or have a feature request? Open a [GitHub Issue](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues). Check for duplicates first.

Pull requests are welcome. All contributions must be submitted under the [Unlicense](./LICENSE).

## Privacy

The app collects no personal data. Anonymous, opt-out analytics are available in Settings. Roku and Twitch collect data independently under their own privacy policies. Optional Twitch watch credit sends signed-in viewing reports directly to Twitch, defaults to off, and is separate from anonymous diagnostics.

## License & Credits

Released under the [Unlicense](./LICENSE).

This project exists because Twitch has no official Roku channel, despite [Roku holding ~39% of the North American smart TV market](https://seekingalpha.com/article/4547471-the-sleeping-giant-in-streaming-turning-roku-into-a-huge-2023-winner).
