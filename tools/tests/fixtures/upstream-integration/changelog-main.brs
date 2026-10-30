sub main()
    entries = getChangelog()
    versions = getSortedChangelogVersions(entries)
    pending = []
    for each version in versions
        if compareVersions(version, "2.9.0") > 0 and compareVersions(version, "3.2.1") <= 0
            pending.push(version)
        end if
    end for
    print "UPSTREAM_CHANGELOG_JSON:"; FormatJson({ entries: entries, versions: versions, pending: pending })
end sub
