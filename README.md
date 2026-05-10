[![CI](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/actions/workflows/ci.yml/badge.svg)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/release/jeremy-albinet/Stitch-Revitalized-For-Roku?include_prereleases=&sort=semver&color=blue)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/)

# Stitch Revitalized

A feature-complete Twitch client for Roku.

| Cumulative installs | New installs (Mar 2025) | Avg daily viewers | Avg session | Hours streamed (Mar 2025) |
|---|---|---|---|---|
| 694,449 | 93,163 | 16,598 | ~2h | 971,218 |

## Features

- Browse live streams by category, search, or followed channels
- Live chat overlay while watching streams
- Recently Watched sidebar for quick access to channels you've visited
- VOD and clip playback
- Auto-reconnect after mid-roll ads
- Respects Twitch's business model: ads and monetization work as intended
- Anonymous browsing without login; sign in to access followed channels and chat

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

**Workaround:** the self-hosted [`fmp4-demux-proxy`](./fmp4-demux-proxy/README.md) splits the bundled segments into separate audio and video HLS renditions on the fly, producing a CMAF-conformant manifest Roku accepts. Configure under **Settings → Proxy URL** in the app. See [issue #14](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues/14) for the full investigation and current status.

## Contributing

Found a bug or have a feature request? Open a [GitHub Issue](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues). Check for duplicates first.

Pull requests are welcome. All contributions must be submitted under the [Unlicense](./LICENSE).

## Privacy

The app collects no personal data. Anonymous, opt-out analytics are available in Settings. Roku and Twitch collect data independently under their own privacy policies.

## License & Credits

Released under the [Unlicense](./LICENSE).

This project exists because Twitch has no official Roku channel, despite [Roku holding ~39% of the North American smart TV market](https://seekingalpha.com/article/4547471-the-sleeping-giant-in-streaming-turning-roku-into-a-huge-2023-winner).
