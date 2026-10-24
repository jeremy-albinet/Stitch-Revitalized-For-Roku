# TODO

## Medium

- [ ] Hard-coded FHD geometry in CustomVideo/StitchVideo brs (1480/1800/1660/940 etc.) should read constants.
- [ ] With chat on, player controls/time labels stay centered on 1920 instead of the 1600 video; thumbnail clamp also ignores chat.
- [ ] FHD texture memory not measured on 512 MB devices (r2d2_bitmaps / chanperf).

## Low

- [ ] Settings titles use 3 leading spaces as padding (LabelList ignores textHorizOffset). Proper fix: custom item component.
- [ ] CustomVideo and StitchVideo carry duplicated overlay edits; consolidate.
- [ ] "LIVE" badge text is not via tr() and its color is a literal.
- [ ] AGENTS.md mentions FollowedStreamsBar (now RecentlyWatchedBar).
