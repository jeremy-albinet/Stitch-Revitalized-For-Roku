[![stars - Stitch-Revitalized-For-Roku](https://img.shields.io/github/stars/jeremy-albinet/Stitch-Revitalized-For-Roku?style=social)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku)
[![forks - Stitch-Revitalized-For-Roku](https://img.shields.io/github/forks/jeremy-albinet/Stitch-Revitalized-For-Roku?style=social)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku)
[![GitHub release](https://img.shields.io/github/release/jeremy-albinet/Stitch-Revitalized-For-Roku?include_prereleases=&sort=semver&color=blue)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/)
[![License](https://img.shields.io/badge/License-Unlicense-blue)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/blob/main/LICENSE)
![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/jeremy-albinet/Stitch-Revitalized-For-Roku?utm_source=oss&utm_medium=github&utm_campaign=jeremy-albinet%2FStitch-Revitalized-For-Roku&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)
[![issues - Stitch-Revitalized-For-Roku](https://img.shields.io/github/issues/jeremy-albinet/Stitch-Revitalized-For-Roku)](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues)

![Roku](https://img.shields.io/badge/roku-6f1ab1?style=for-the-badge&logo=roku&logoColor=white)
![Twitch](https://img.shields.io/badge/Twitch-9347FF?style=for-the-badge&logo=twitch&logoColor=white)

# Stitch Revitalized (for Roku)
Stitch Revitalized is a Roku channel that aims to provide an actively maintained, reasonably feature-complete Twitch experience while respecting Twitch's business model (ads, monetization, and the like). This channel is based on the now archived Stitch channel https://github.com/Narehood/Stitch-Revitalized-For-Roku (Jul 29, 2025) that was based on https://github.com/0xW1sKy/Stitch-For-Roku (Nov 24, 2024).

## Installation

You can add the channel using this link: https://my.roku.com/account/add/TwitchRevitalized

## Side Loading
If the link is not loading or you otherwise want to sideload this you can do so by doing the following (this is not a full tutorial, I may make one at some point). There may be a better way to do this, but this was what I was able to figure out without any previous instruction/documentation.

Easy: 

- Download the ZIP here: [Stitch Revitalized Download](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/releases/download/v2.1/Stitch-Revitalized-For-Roku.zip)
- Enable/Configure Dev mode on your Roku
- Upload the ZIP file to your Roku through a web browser

Manual Compiling:

- Download this repo
- Install Visual Studio Code
- Install the required extensions/software: BrightScript Function Comment, BrightScript Language, nodejs, and anything else it requires; it should prompt you
- Enable Dev mode on your Roku
- Modify the bsconfig.json by entering your Rokus IP address and the password you set (you can also access the Roku through telnet or web browser once this is enabled
- Click on Run > Start Debugging and it will install the app on your device
- You may need to run a 'npm install' command in the terminal of Visual Studio Code

## Contributing

If you are comfortable using the GitHub interface, you can report bugs or request features by opening a [GitHub Issue](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku/issues). (Please check to see if your issue has already been reported before opening a new one.)


In addition to issues, Pull Requests are welcome. All contributions must be made [under the Unlicense](./LICENSE).

## Data Collection

I do not collect any data from this app, but Roku and Twitch may do so. If this is a concern you should read their policies on data collection. The data Roku collects may be in whole or in part accessible by myself, but I, nor anyone working with me or on my behalf will use this data for any purpose except for fixing bugs/errors if they are reported.


## Authorship and License

Stitch Revitalized exists because Twitch does not presently have any official channel for Roku, despite [Roku being the most popular smart TV platform, with (as of early 2022), a 39% market share in North America and a 31% market share worldwide](https://seekingalpha.com/article/4547471-the-sleeping-giant-in-streaming-turning-roku-into-a-huge-2023-winner). If Stitch becomes active or Twitch makes an official app, this project will no longer be maintained.

Stitch (and now Stitch Revitalized) began as a hard fork of [Twoku](https://github.com/worldreboot/twitch-reloaded-roku), due to that application's apparent abandonment. Since then Stitch has been almost completely rewritten.

Twoku was released without an explicit license, but, as a non-cleanroom rewrite, all subsequent contributions to Stitch are released [under the Unlicense](./LICENSE).

If license encumbrance is an issue for you, you can compare [the final upstream commit to this repository](https://github.com/0xW1sKy/Stitch-For-Roku/commit/268187c63e1eaf3922f577a2dab6ccb6a2e089f8) to see what code is unclearly licensed.

While removing any residual upstream code is not a priority for Stitch, Pull Requests replacing unclearly licensed code with unencumbered code are welcome.

Stitch Revitalized is released on a non-commercial basis and derives no revenue. If you work for Twitch, please feel free to use the license-unencumbered portions of this repository as the basis for an official Twitch app.
