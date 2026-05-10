[![CI](https://github.com/awest813/Stitch-Revitalized-For-Roku/actions/workflows/pull_requests.yml/badge.svg)](https://github.com/awest813/Stitch-Revitalized-For-Roku/actions/workflows/pull_requests.yml)
[![Release](https://github.com/awest813/Stitch-Revitalized-For-Roku/actions/workflows/release.yml/badge.svg)](https://github.com/awest813/Stitch-Revitalized-For-Roku/actions/workflows/release.yml)

[![stars - Stitch-Revitalized-For-Roku](https://img.shields.io/github/stars/awest813/Stitch-Revitalized-For-Roku?style=social)](https://github.com/awest813/Stitch-Revitalized-For-Roku)
[![forks - Stitch-Revitalized-For-Roku](https://img.shields.io/github/forks/awest813/Stitch-Revitalized-For-Roku?style=social)](https://github.com/awest813/Stitch-Revitalized-For-Roku)
[![GitHub release](https://img.shields.io/github/release/awest813/Stitch-Revitalized-For-Roku?include_prereleases=&sort=semver&color=blue)](https://github.com/awest813/Stitch-Revitalized-For-Roku/releases/)
[![License](https://img.shields.io/badge/License-Unlicense-blue)](https://github.com/awest813/Stitch-Revitalized-For-Roku/blob/main/LICENSE)
![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/awest813/Stitch-Revitalized-For-Roku?utm_source=oss&utm_medium=github&utm_campaign=awest813%2FStitch-Revitalized-For-Roku&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)
[![issues - Stitch-Revitalized-For-Roku](https://img.shields.io/github/issues/awest813/Stitch-Revitalized-For-Roku)](https://github.com/awest813/Stitch-Revitalized-For-Roku/issues)

![Roku](https://img.shields.io/badge/roku-6f1ab1?style=for-the-badge&logo=roku&logoColor=white)
![Twitch](https://img.shields.io/badge/Twitch-9347FF?style=for-the-badge&logo=twitch&logoColor=white)

# Twaruto (for Roku)

Twaruto is a Roku channel that aims to provide an actively maintained, reasonably feature-complete Twitch experience while respecting Twitch’s business model (ads, monetization, and the like). It continues the lineage of the archived [Stitch Revitalized for Roku](https://github.com/Narehood/Stitch-Revitalized-For-Roku) project (Jul 29, 2025), which was based on [Stitch for Roku](https://github.com/0xW1sKy/Stitch-For-Roku) (Nov 24, 2024).

## Installation

You can add the channel using this link: https://my.roku.com/account/add/TwitchRevitalized

The Roku catalog entry may still show an older listing name; the app title on your home screen and in the channel UI is **Twaruto**.

## Side loading

If the link is not loading or you otherwise want to sideload this you can do so by doing the following (this is not a full tutorial, I may make one at some point). There may be a better way to do this, but this was what I was able to figure out without any previous instruction/documentation.

Easy:

- Download the ZIP from the [latest release](https://github.com/awest813/Stitch-Revitalized-For-Roku/releases/latest) (artifact name: `Twaruto.zip`).
- Enable or configure developer mode on your Roku.
- Upload the ZIP file to your Roku through a web browser.

Manual compiling:

- Clone this repository.
- Install Visual Studio Code.
- Install the required extensions and software: BrightScript Function Comment, BrightScript Language, Node.js, and anything else it requires; it should prompt you.
- Enable developer mode on your Roku.
- Edit `bsconfig.json` with your Roku IP address and developer password (you can also access the Roku through telnet or a web browser once developer mode is enabled). Release packages are written to `out/Twaruto.zip` when you run `npm run package`.
- Choose **Run > Start Debugging** and it will install the app on your device.
- You may need to run `npm install` in the Visual Studio Code terminal.

## Contributing

If you are comfortable using the GitHub interface, you can report bugs or request features by opening a [GitHub Issue](https://github.com/awest813/Stitch-Revitalized-For-Roku/issues). Please check whether your issue has already been reported before opening a new one.

In addition to issues, pull requests are welcome. All contributions must be made [under the Unlicense](./LICENSE).

## Data collection

I do not collect any data from this app, but Roku and Twitch may do so. If this is a concern you should read their policies on data collection. The data Roku collects may be in whole or in part accessible by myself, but neither I nor anyone working with me or on my behalf will use this data for any purpose except for fixing bugs or errors if they are reported.

## Authorship and license

Twaruto exists because Twitch does not presently have any official channel for Roku, despite [Roku being the most popular smart TV platform, with (as of early 2022), a 39% market share in North America and a 31% market share worldwide](https://seekingalpha.com/article/4547471-the-sleeping-giant-in-streaming-turning-roku-into-a-huge-2023-winner). If the historical Stitch family of channels becomes active again or Twitch ships an official app, this project may no longer be maintained.

This codebase began as a hard fork of [Twoku](https://github.com/worldreboot/twitch-reloaded-roku), due to that application’s apparent abandonment. Subsequent work through Stitch and Twaruto has rewritten almost all of it.

Twoku was released without an explicit license, but, as a non-cleanroom rewrite, all subsequent contributions are released [under the Unlicense](./LICENSE).

If license encumbrance is an issue for you, you can compare [the final upstream commit to the Stitch lineage](https://github.com/0xW1sKy/Stitch-For-Roku/commit/268187c63e1eaf3922f577a2dab6ccb6a2e089f8) to see what code is unclearly licensed.

While removing any residual upstream code is not a priority, pull requests replacing unclearly licensed code with unencumbered code are welcome.

Twaruto is released on a non-commercial basis and derives no revenue. If you work for Twitch, please feel free to use the license-unencumbered portions of this repository as the basis for an official Twitch app.
