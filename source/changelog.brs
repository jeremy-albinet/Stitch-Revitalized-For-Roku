' Changelog entries keyed by version string ("major.minor.build").
' Add a new entry here with every release.
' Versions are displayed in ascending order; multiple versions are shown when the user skipped an update.
function getChangelog() as object
    return {
        "2.4.0": [
            "New: Recently Watched sidebar — quickly rejoin streams you've watched",
            "New: Streams now auto-reconnect after ad breaks instead of freezing",
            "New: Optional anonymous analytics to help catch bugs (opt-out in Settings)",
            "Fix: Chat failing to load and IRC connection drops",
            "Fix: Clips no longer missing from search results and browse grids",
            "Fix: Several crashes on scene transitions and network failures",
        ],
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
