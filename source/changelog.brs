' Changelog entries keyed by version string ("major.minor.build").
' Add a new entry here with every release.
' Versions are displayed in ascending order; multiple versions are shown when the user skipped an update.
function getChangelog() as object
    return {
        "2.8.0": [
            "New: The app now renders in full 1080p - sharper, less zoomed, and more content per row",
            "New: Video player and chat are laid out for the full screen",
            "New: Settings redesigned - full width, floating focus, current value shown for choice settings, readable checkmarks",
            "New: Redesigned login page with a larger code and a sharper QR",
            "Improved: Thinner focus border and a smaller LIVE badge",
            "Fix: Search results no longer overlap the keyboard",
            "Fix: Round avatars are round again"
        ],
        "2.7.0": [
            "New: Enhanced Broadcasting streams can now play without a proxy server. Pick Turn On and Play when asked, or turn on Settings > Built-in Enhanced Broadcasting Splitter",
            "New: The built-in splitter was contributed by a community member. Thank you!",
            "Fix: Streams no longer restart 16 seconds after changing quality",
            "Fix: Picking a quality from the menu on a proxied stream now stays on the proxy",
            "Fix: Proxied streams now get the right bitrate and resolution"
        ],
        "2.6.0": [
            "New: Recently Watched sidebar now shows a live indicator — a red dot appears on streamers who are currently live",
            "Improved: Top bar and left sidebar are now smaller, giving more screen space to content",
            "Improved: Stream category and streamer name are now on the same line in stream cards"
        ],
        "2.5.1": [
            "Fix: Streams no longer buffer every 30-40 seconds after the v2.5 latency update",
            "Fix: Removed the brief spinner flash that appeared right after a stream started",
            "Improved: Smarter live-edge correction — skipped when the stream already starts near the live edge"
        ],
        "2.5.0": [
            "New: Reduced stream latency — streams now start closer to real-time, though zero-delay streaming isn't possible on Roku",
            "New: Donate via Buy Me a Coffee — find the QR code in Settings",
            "Fix: Focus highlight now visible on channel pages and all grid views",
            "Fix: Error tracking now includes more detail to help diagnose crashes faster"
        ],
        "2.4.0": [
            "New: Following + Browse — simpler 2-tab layout (was 4 tabs)",
            "New: Recently Watched sidebar — quickly rejoin streams you've been to",
            "New: Sign in with a QR code — scan with your phone instead of typing the device code",
            "New: Search tab in the top menu — dedicated destination for finding channels and games",
            "New: Streams now auto-reconnect after ad breaks instead of freezing",
            "New: Settings → Log Out",
            "New: Optional anonymous analytics to help catch bugs (opt-out in Settings)",
            "Fix: Chat connection now closes properly when leaving a stream",
            "Fix: Several crashes on scene transitions and network failures"
        ]
    }
end function

' Returns a sorted list of version strings present in the changelog AA,
' ordered from oldest to newest (ascending semver).
function getSortedChangelogVersions(changelog as object) as object
    versions = []
    for each v in changelog
        versions.push(v)
    end for

    ' Bubble sort ascending by semver
    n = versions.count()
    for i = 0 to n - 2
        for j = 0 to n - 2 - i
            if compareVersions(versions[j], versions[j + 1]) > 0
                tmp = versions[j]
                versions[j] = versions[j + 1]
                versions[j + 1] = tmp
            end if
        end for
    end for

    return versions
end function

' Returns -1 / 0 / 1 for a < b / a = b / a > b.
function compareVersions(a as string, b as string) as integer
    pa = parseVersion(a)
    pb = parseVersion(b)
    if pa.major <> pb.major then return sgn(pa.major - pb.major)
    if pa.minor <> pb.minor then return sgn(pa.minor - pb.minor)
    if pa.build <> pb.build then return sgn(pa.build - pb.build)
    return 0
end function

function parseVersion(v as string) as object
    parts = v.tokenize(".")
    major = 0
    minor = 0
    build = 0
    if parts.count() > 0 then major = parts[0].toInt()
    if parts.count() > 1 then minor = parts[1].toInt()
    if parts.count() > 2 then build = parts[2].toInt()
    return { major: major, minor: minor, build: build }
end function
