"""Rotating signed rendition URLs retain a strictly approved adaptive master."""

from __future__ import annotations

import asyncio
import json
import socket
from copy import deepcopy
from types import SimpleNamespace
from typing import Any
from urllib.parse import parse_qs, urlsplit

import pytest
from aiohttp import web
from aiohttp.abc import ResolveResult
from multidict import MultiDict
from yarl import URL

from fmp4_demux_proxy import manifest as mf
from fmp4_demux_proxy import upstream as upstream_module
from fmp4_demux_proxy.fmp4 import extract_track_map
from fmp4_demux_proxy.routes import m3u8_route
from fmp4_demux_proxy.upstream import UpstreamData
from tests._fixtures import make_init_segment, make_split_media_segment
from tests.test_regressions import FakeCDN, mdat
from tests.test_regressions import cdn as cdn
from tests.test_regressions import proxy_factory as proxy_factory

HIGH = {
    "BANDWIDTH": "8042999",
    "CODECS": "avc1.4D401F,mp4a.40.2",
    "RESOLUTION": "1920x1080",
    "FRAME-RATE": "60.000",
    "VIDEO": "1080p60",
}
LOW = {
    "BANDWIDTH": "1327200",
    "CODECS": "avc1.4D401F,mp4a.40.2",
    "RESOLUTION": "852x480",
    "FRAME-RATE": "30.000",
    "VIDEO": "480p30",
}


def declaration(tag: str, attrs: dict[str, str]) -> str:
    unquoted = {"BANDWIDTH", "AVERAGE-BANDWIDTH", "RESOLUTION", "FRAME-RATE"}
    return tag + ",".join(
        f"{key}={value}" if key in unquoted else f'{key}="{value}"' for key, value in attrs.items()
    )


def master(
    entries: list[tuple[dict[str, str], str]], media: list[dict[str, str]] | None = None
) -> bytes:
    lines = ["#EXTM3U"]
    lines.extend(declaration("#EXT-X-MEDIA:", item) for item in media or [])
    for attrs, uri in entries:
        lines.extend([declaration("#EXT-X-STREAM-INF:", attrs), uri])
    return ("\n".join(lines) + "\n").encode()


def descriptor(attrs: dict[str, str], groups: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {"attributes": attrs, "groups": groups if groups is not None else []}


def selection_params(cdn: FakeCDN, selections: list[dict[str, Any]]) -> dict[str, str]:
    return {"u": cdn.url("/master?token=fixture%2Bvalue"), "selections": json.dumps(selections)}


def add_variant(cdn: FakeCDN, path: str, tracks: list[tuple[int, bytes]] | None) -> None:
    if tracks is None:
        cdn.bodies[path] = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nmedia.ts\n"
    else:
        cdn.bodies[path] = (
            f'#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="{path}-init"\n'
            f"#EXTINF:2,\n{path}-media\n"
        ).encode()
        cdn.bodies[path + "-init"] = make_init_segment(tracks)


async def test_rotating_master_preserves_all_approved_qualities_and_real_split_media(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    first = master([(HIGH, "/old/high?sig=fixture-old"), (LOW, "/old/low?sig=fixture-old")])
    old_urls = tuple(
        entry[1] for entry in mf.master_entries(first.decode(), cdn.url("/master")).values()
    )
    fresh_high = "/new/high?sig=fixture%2Bnew&extra=a%3Db"
    fresh_low = "/different/low?sig=fixture-new"
    rogue = {**HIGH, "CODECS": "hvc1.2.4.L153.B0,mp4a.40.2"}
    cdn.bodies["/master"] = master([(LOW, fresh_low), (rogue, "/unapproved"), (HIGH, fresh_high)])
    add_variant(cdn, "/new/high", [(1, b"soun"), (2, b"vide")])
    add_variant(cdn, "/different/low", [(1, b"soun"), (2, b"vide")])
    cdn.bodies["/new/high-media"] = make_split_media_segment(1, b"PICTURE", b"SOUND", 2, 1)
    client = await proxy_factory()
    legacy = await client.get(
        "/m3u8", params={"u": cdn.url("/master"), "variants": json.dumps(old_urls)}
    )
    assert legacy.status == 502 and "does not appear" in await legacy.text()
    selected = await client.get(
        "/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH), descriptor(LOW)])
    )
    assert selected.status == 200 and selected.headers["Cache-Control"] == "no-store"
    output = await selected.text()
    entries = mf.master_entries(output, str(client.make_url("/")))
    assert len(entries) == 2 and output.count("#EXT-X-MEDIA:TYPE=AUDIO") == 2
    assert "hvc1" not in output and "fixture-old" not in output
    assert cdn.hits["/unapproved"] == 0
    high = next(entry for entry in entries.values() if entry[2]["RESOLUTION"] == "1920x1080")
    assert parse_qs(urlsplit(high[1]).query)["u"] == [cdn.url(fresh_high)]
    assert cdn.queries[1] == {"token": "fixture+value"}
    audio = next(
        mf.attributes(line)["URI"]
        for line in output.splitlines()
        if line.startswith("#EXT-X-MEDIA:") and mf.attributes(line)["GROUP-ID"] == high[2]["AUDIO"]
    )
    for link, expected, track in [(high[1], b"PICTURE", "video"), (audio, b"SOUND", "audio")]:
        child = await client.get(URL(link).relative())
        assert child.status == 200
        body = await child.text()
        init = mf.attributes(
            next(line for line in body.splitlines() if line.startswith("#EXT-X-MAP:"))
        )["URI"]
        response = await client.get(URL(init).relative())
        assert response.status == 200 and extract_track_map(await response.read()) == {1: track}
        media = next(line for line in body.splitlines() if line.startswith("http"))
        response = await client.get(URL(media).relative())
        assert response.status == 200 and mdat(await response.read()) == expected


@pytest.mark.parametrize(
    "key,value",
    [
        ("CODECS", "avc1.640032,mp4a.40.2"),
        ("CODECS", "hvc1.1.6.L150.B0,mp4a.40.2"),
        ("CODECS", "av01.0.08M.08,mp4a.40.2"),
        ("CODECS", "avc1.4D401F,mp4a.40.5"),
        ("RESOLUTION", "2560x1440"),
        ("FRAME-RATE", "120.000"),
        ("BANDWIDTH", "9042999"),
        ("AVERAGE-BANDWIDTH", "7000000"),
        ("VIDEO-RANGE", "PQ"),
        ("STABLE-VARIANT-ID", "different"),
        ("VIDEO", "source"),
    ],
)
async def test_any_declared_metadata_change_fails_before_child_fetch(
    cdn: FakeCDN, proxy_factory: Any, key: str, value: str
) -> None:
    cdn.bodies["/master"] = master([({**HIGH, key: value}, "/fresh")])
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 502 and "missing or ambiguous" in await response.text()
    assert cdn.hits == {"/master": 1}


@pytest.mark.parametrize("change", ["missing", "ambiguous", "same-url", "absent-attribute"])
async def test_missing_ambiguous_or_nondistinct_selection_cannot_drop_or_expand_ladder(
    cdn: FakeCDN, proxy_factory: Any, change: str
) -> None:
    entries = [(HIGH, "/high"), (LOW, "/low")]
    if change == "missing":
        entries.pop()
    elif change == "ambiguous":
        entries.append((HIGH, "/second-high"))
    elif change == "same-url":
        entries[1] = (LOW, "/high")
    else:
        entries[0] = ({key: value for key, value in HIGH.items() if key != "FRAME-RATE"}, "/high")
    cdn.bodies["/master"] = master(entries)
    client = await proxy_factory()
    response = await client.get(
        "/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH), descriptor(LOW)])
    )
    assert response.status == 502 and cdn.hits == {"/master": 1}


@pytest.mark.parametrize("tracks", [None, [(1, b"vide")], [(1, b"soun"), (2, b"vide")]])
async def test_fresh_transport_is_inspected_even_with_identical_codec_declarations(
    cdn: FakeCDN, proxy_factory: Any, tracks: list[tuple[int, bytes]] | None
) -> None:
    cdn.bodies["/master"] = master([(HIGH, "/fresh")])
    add_variant(cdn, "/fresh", tracks)
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 200 and cdn.hits["/fresh"] == 1
    output = await response.text()
    bundled = tracks is not None and len(tracks) == 2
    assert ("track=video" in output) == bundled
    assert ("#EXT-X-MEDIA:TYPE=AUDIO" in output) == bundled
    if not bundled:
        assert "mode=passthrough" in output


async def test_group_multisets_preserve_external_audio_subtitles_and_empty_uri_presence(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    attrs = {**HIGH, "AUDIO": "sounds", "SUBTITLES": "subs", "CLOSED-CAPTIONS": "NONE"}
    english = {
        "TYPE": "AUDIO",
        "GROUP-ID": "sounds",
        "NAME": "English",
        "CHANNELS": "2",
        "URI": "/fresh-audio",
    }
    spanish = {"TYPE": "AUDIO", "GROUP-ID": "sounds", "NAME": "Spanish", "URI": ""}
    subs = {"TYPE": "SUBTITLES", "GROUP-ID": "subs", "NAME": "Subtitles", "URI": "/fresh-subs"}
    groups = [
        {"attributes": {key: value for key, value in item.items() if key != "URI"}, "hasUri": True}
        for item in [subs, spanish, english]
    ]
    cdn.bodies["/master"] = master(
        [(dict(reversed(list(attrs.items()))), "/video")], [spanish, english, subs]
    )
    add_variant(cdn, "/video", [(1, b"soun"), (2, b"vide")])
    client = await proxy_factory()
    response = await client.get(
        "/m3u8/selected", params=selection_params(cdn, [descriptor(attrs, groups)])
    )
    assert response.status == 200
    output = await response.text()
    assert 'AUDIO="sounds"' in output and 'SUBTITLES="subs"' in output
    assert "stitch-demux-" not in output and "track=video" in output
    assert output.count("#EXT-X-MEDIA:") == 3 and "fresh-audio" in output
    bad = deepcopy(groups)
    bad[1]["hasUri"] = False
    response = await client.get(
        "/m3u8/selected", params=selection_params(cdn, [descriptor(attrs, bad)])
    )
    assert response.status == 502


@pytest.mark.parametrize("change", ["channels", "language", "uri-presence", "duplicate", "type"])
async def test_group_identity_and_multiplicity_are_significant(
    cdn: FakeCDN, proxy_factory: Any, change: str
) -> None:
    attrs = {**HIGH, "AUDIO": "sound"}
    media = {
        "TYPE": "AUDIO",
        "GROUP-ID": "sound",
        "NAME": "English",
        "CHANNELS": "2",
        "URI": "/audio",
    }
    group = {
        "attributes": {key: value for key, value in media.items() if key != "URI"},
        "hasUri": True,
    }
    changed = dict(media)
    if change == "channels":
        changed["CHANNELS"] = "6"
    elif change == "language":
        changed["LANGUAGE"] = "es"
    elif change == "uri-presence":
        changed.pop("URI")
    elif change == "type":
        changed["TYPE"] = "VIDEO"
    cdn.bodies["/master"] = master(
        [(attrs, "/video")], [changed, changed] if change == "duplicate" else [changed]
    )
    client = await proxy_factory()
    response = await client.get(
        "/m3u8/selected", params=selection_params(cdn, [descriptor(attrs, [group])])
    )
    assert response.status == 502 and cdn.hits == {"/master": 1}


def invalid_payloads() -> list[str]:
    valid = descriptor(HIGH)
    invalid = [[], {}, None, [valid, valid], [valid] * 33]
    for key, value in [
        ("CODECS", 1),
        ("URL", "https://fixture.invalid"),
        ("URI", "/arbitrary"),
        ("url", "/arbitrary"),
        ("SEPARATE-AUDIO", "false"),
        ("x", "lowercase"),
        ("X" * 129, "long"),
        ("X", "x" * 4097),
    ]:
        invalid.append([descriptor({**HIGH, key: value})])
    invalid += [[descriptor({f"X-{i}": "x" for i in range(65)})]]
    for group in [
        {"attributes": {}, "hasUri": 1},
        {"attributes": {}, "hasUri": "true"},
        {"attributes": {}, "hasUri": None},
        {"attributes": {}},
        {"attributes": {"URI": "/url"}, "hasUri": True},
        {"attributes": {}, "hasUri": True, "other": "field"},
    ]:
        invalid.append([descriptor(HIGH, [group])])
    invalid += [[descriptor(HIGH, [{"attributes": {}, "hasUri": False}] * 65)]]
    invalid += [[{**valid, "other": "field"}], [{"attributes": HIGH}], [descriptor(HIGH, {})]]
    result = [json.dumps(value) for value in invalid]
    result += [
        '[{"attributes":{},"attributes":{},"groups":[]}]',
        '[{"attributes":{"CODECS":"avc1","CODECS":"hvc1"},"groups":[]}]',
        '[{"attributes":{},"groups":[{"attributes":{},"hasUri":true,"hasUri":false}]}]',
        "[" * 1500 + "]" * 1500,
        "{",
        " " * 32769,
        json.dumps([descriptor({"X": "é" * 4096})] * 5, ensure_ascii=False),
    ]
    return result


INVALID_PAYLOADS = invalid_payloads()


@pytest.mark.parametrize(
    "payload", INVALID_PAYLOADS, ids=[f"invalid-{i}" for i in range(len(INVALID_PAYLOADS))]
)
async def test_invalid_selection_rejected_before_any_upstream_io(
    cdn: FakeCDN, proxy_factory: Any, payload: str
) -> None:
    client = await proxy_factory()
    response = await client.get(
        "/m3u8/selected", params={"u": cdn.url("/master"), "selections": payload}
    )
    assert response.status == 400 and not cdn.hits


@pytest.mark.parametrize(
    "key", ["variant", "variants", "demuxVariants", "mode", "track", "codecs", "unexpected"]
)
async def test_legacy_or_unknown_query_fields_cannot_override_selection(
    cdn: FakeCDN, proxy_factory: Any, key: str
) -> None:
    client = await proxy_factory()
    params = {**selection_params(cdn, [descriptor(HIGH)]), key: "fixture"}
    response = await client.get("/m3u8/selected", params=params)
    assert response.status == 400 and not cdn.hits


@pytest.mark.parametrize("key", ["u", "selections", "_HLS_msn"])
async def test_duplicate_query_keys_are_rejected_before_fetch(
    cdn: FakeCDN, proxy_factory: Any, key: str
) -> None:
    client = await proxy_factory()
    params = [*selection_params(cdn, [descriptor(HIGH)]).items(), (key, "1"), (key, "2")]
    response = await client.get("/m3u8/selected", params=params)
    assert response.status == 400 and not cdn.hits


@pytest.mark.parametrize("body", [b"not HLS", b"\xff", b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n"])
async def test_selected_endpoint_requires_utf8_master(
    cdn: FakeCDN, proxy_factory: Any, body: bytes
) -> None:
    cdn.bodies["/master"] = body
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 502 and cdn.hits == {"/master": 1}


async def test_fresh_rendition_redirect_is_validated_before_connect(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = master([(HIGH, "/fresh")])
    cdn.redirects["/fresh"] = "https://blocked.example.invalid/arbitrary?sig=fixture"
    client = await proxy_factory(upstream_host_allowlist=("127.0.0.1",))
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 400 and "disallowed" in await response.text()
    assert cdn.hits == {"/master": 1, "/fresh": 1}


@pytest.mark.parametrize(
    "uri", ["ftp://fixture.invalid/playlist", "https://blocked.example.invalid/playlist"]
)
async def test_fresh_url_is_validated_before_variant_fetch(
    cdn: FakeCDN, proxy_factory: Any, uri: str
) -> None:
    cdn.bodies["/master"] = master([(HIGH, uri)])
    client = await proxy_factory(upstream_host_allowlist=("127.0.0.1",))
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 400 and cdn.hits == {"/master": 1}


def test_approved_group_count_above_bound_never_expands_or_matches() -> None:
    attrs = {**HIGH, "AUDIO": "large"}
    members = [{"TYPE": "AUDIO", "GROUP-ID": "large", "NAME": str(i)} for i in range(65)]
    with pytest.raises(mf.ManifestError, match="missing or ambiguous"):
        mf.selected_master_urls(
            master([(attrs, "/video")], members).decode(),
            "https://fixture.invalid/master",
            mf.parse_selections([descriptor(attrs)]),
        )


async def test_one_approved_uri_cannot_include_an_unapproved_entry_sharing_that_uri(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = master(
        [(HIGH, "/shared"), ({**HIGH, "CODECS": "hvc1.2.4.L153.B0"}, "/shared")]
    )
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 502 and "multiple master entries" in await response.text()
    assert cdn.hits == {"/master": 1}


@pytest.mark.parametrize("missing", ["u", "selections"])
async def test_required_query_fields_fail_before_fetch(
    cdn: FakeCDN, proxy_factory: Any, missing: str
) -> None:
    params = selection_params(cdn, [descriptor(HIGH)])
    params.pop(missing)
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=params)
    assert response.status == 400 and not cdn.hits


def test_decoded_payload_byte_boundary_is_checked_by_handler_parser() -> None:
    raw = json.dumps([descriptor(HIGH)])
    exact = raw + " " * (32768 - len(raw.encode()))
    request = SimpleNamespace(
        query=MultiDict({"u": "https://fixture.invalid/master", "selections": exact})
    )
    assert len(m3u8_route._parse_selections(request)) == 1
    request.query["selections"] = exact + " "
    with pytest.raises(web.HTTPBadRequest) as rejected:
        m3u8_route._parse_selections(request)
    assert "oversized" in rejected.value.text
    unicode = json.dumps(
        [descriptor({"X": str(i) + "é" * 4000}) for i in range(5)], ensure_ascii=False
    )
    assert len(unicode) < 32768 < len(unicode.encode())
    request.query["selections"] = unicode
    with pytest.raises(web.HTTPBadRequest) as rejected:
        m3u8_route._parse_selections(request)
    assert "oversized" in rejected.value.text


def test_individual_descriptor_boundaries_allow_exact_maxima() -> None:
    attrs = {f"X-{i}": "" for i in range(63)}
    attrs["A" * 128] = "x" * 4096
    assert len(mf.parse_selections([descriptor(attrs)])[0].attributes) == 64
    selections = [descriptor({"NAME": str(i)}) for i in range(32)]
    assert len(mf.parse_selections(selections)) == 32
    group = {"attributes": {"TYPE": "AUDIO", "GROUP-ID": "g"}, "hasUri": False}
    assert len(mf.parse_selections([descriptor(HIGH, [group] * 64)])[0].groups) == 64


@pytest.mark.parametrize(
    "payload",
    INVALID_PAYLOADS,
    ids=[f"handler-invalid-{i}" for i in range(len(INVALID_PAYLOADS))],
)
def test_handler_parser_rejects_malformed_contract_beyond_http_line_limits(payload: str) -> None:
    request = SimpleNamespace(
        query=MultiDict({"u": "https://fixture.invalid/master", "selections": payload})
    )
    with pytest.raises(web.HTTPBadRequest):
        m3u8_route._parse_selections(request)


@pytest.mark.parametrize(
    "tracks",
    [
        [],
        [(1, b"soun")],
        [(1, b"vide"), (2, b"vide")],
        [(1, b"vide"), (2, b"soun"), (3, b"soun")],
        [(1, b"vide"), (2, b"meta")],
    ],
    ids=["empty", "audio-only", "two-video", "two-audio", "unknown"],
)
async def test_selected_video_declarations_cannot_authorize_missing_or_unknown_init_tracks(
    cdn: FakeCDN, proxy_factory: Any, tracks: list[tuple[int, bytes]]
) -> None:
    cdn.bodies["/master"] = master([(HIGH, "/fresh")])
    add_variant(cdn, "/fresh", tracks)
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 502
    assert cdn.hits == {"/master": 1, "/fresh": 1, "/fresh-init": 1}


@pytest.mark.parametrize("reload", ["_HLS_msn", "_HLS_part", "_HLS_skip"])
async def test_invalid_reload_values_fail_before_fetch(
    cdn: FakeCDN, proxy_factory: Any, reload: str
) -> None:
    client = await proxy_factory()
    params = {**selection_params(cdn, [descriptor(HIGH)]), reload: "-1"}
    response = await client.get("/m3u8/selected", params=params)
    assert response.status == 400 and not cdn.hits


async def test_valid_reload_fields_and_fresh_signed_queries_survive(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = master([(HIGH, "/fresh?sig=fixture%2Bvalue&x=a%3Db")])
    add_variant(cdn, "/fresh", None)
    client = await proxy_factory()
    params = {
        **selection_params(cdn, [descriptor(HIGH)]),
        "_HLS_msn": "12",
        "_HLS_part": "3",
        "_HLS_skip": "v2",
    }
    response = await client.get("/m3u8/selected", params=params)
    assert response.status == 200
    assert cdn.queries == [
        {"token": "fixture+value", "_HLS_msn": "12", "_HLS_part": "3", "_HLS_skip": "v2"},
        {"sig": "fixture+value", "x": "a=b"},
    ]


@pytest.mark.parametrize(
    "uri",
    [
        "http://127.0.0.1/playlist",
        "http://169.254.169.254/metadata",
        "http://[::ffff:127.0.0.1]/playlist",
    ],
)
async def test_selected_private_literals_never_reach_a_fetch(
    proxy_factory: Any, monkeypatch: Any, uri: str
) -> None:
    client = await proxy_factory(
        allow_unsafe_upstream=False,
        upstream_host_allowlist=(
            "example.invalid",
            "127.0.0.1",
            "169.254.169.254",
            "::ffff:127.0.0.1",
        ),
    )
    calls = []

    async def fetch(app: Any, url: str, **kwargs: Any) -> UpstreamData:
        calls.append(url)
        return UpstreamData(master([(HIGH, uri)]), url, "application/vnd.apple.mpegurl")

    monkeypatch.setattr(m3u8_route, "fetch_upstream", fetch)
    response = await client.get(
        "/m3u8/selected",
        params={
            "u": "https://origin.example.invalid/master",
            "selections": json.dumps([descriptor(HIGH)]),
        },
    )
    assert response.status == 400 and len(calls) == 1
    assert "Private" in await response.text()


async def test_selected_fresh_hostname_blocks_private_dns_before_connection(
    proxy_factory: Any, monkeypatch: Any
) -> None:
    client = await proxy_factory(
        allow_unsafe_upstream=False, upstream_host_allowlist=("example.invalid",)
    )
    original_fetch = m3u8_route.fetch_upstream
    master_url = "https://origin.example.invalid/master"
    uri = "http://cdn.example.invalid/fresh"
    calls = []

    async def fetch(app: Any, url: str, **kwargs: Any) -> UpstreamData:
        if url == master_url:
            return UpstreamData(master([(HIGH, uri)]), url, "application/vnd.apple.mpegurl")
        return await original_fetch(app, url, **kwargs)

    async def resolve(
        self: Any, host: str, port: int = 0, family: Any = socket.AF_INET
    ) -> list[ResolveResult]:
        calls.append(host)
        return [
            ResolveResult(
                hostname=host, host="127.0.0.1", port=port, family=family, proto=0, flags=0
            )
        ]

    monkeypatch.setattr(m3u8_route, "fetch_upstream", fetch)
    monkeypatch.setattr(upstream_module.aiohttp.ThreadedResolver, "resolve", resolve)
    response = await client.get(
        "/m3u8/selected", params={"u": master_url, "selections": json.dumps([descriptor(HIGH)])}
    )
    assert response.status == 502 and calls == ["cdn.example.invalid"]
    assert await response.text() == "Upstream request failed or timed out"


async def test_selected_inspections_respect_shared_concurrency_limit(
    proxy_factory: Any, monkeypatch: Any
) -> None:
    client = await proxy_factory(max_upstream_concurrency=2)
    attrs = [{**HIGH, "VIDEO": str(i)} for i in range(5)]
    master_url = "https://fixture.invalid/master"
    entries = [(item, f"https://fixture.invalid/{i}") for i, item in enumerate(attrs)]
    active = peak = master_hits = 0

    async def fetch(app: Any, url: str, **kwargs: Any) -> UpstreamData:
        nonlocal active, peak, master_hits
        if url == master_url:
            master_hits += 1
            return UpstreamData(master(entries), url, "application/vnd.apple.mpegurl")
        active += 1
        peak = max(peak, active)
        try:
            await asyncio.sleep(0.005)
            return UpstreamData(
                b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n", url, "application/vnd.apple.mpegurl"
            )
        finally:
            active -= 1

    monkeypatch.setattr(m3u8_route, "fetch_upstream", fetch)
    response = await client.get(
        "/m3u8/selected",
        params={"u": master_url, "selections": json.dumps([descriptor(item) for item in attrs])},
    )
    assert response.status == 200 and peak == 2 and active == 0 and master_hits == 1
    assert len(mf.master_entries(await response.text(), str(client.make_url("/")))) == 5


@pytest.mark.parametrize("failure", ["deadline", "bad-variant"])
async def test_failed_selected_inspection_cancels_and_awaits_all_siblings(
    proxy_factory: Any, monkeypatch: Any, failure: str, caplog: Any
) -> None:
    client = await proxy_factory(upstream_total_timeout=0.03)
    attrs = [{**HIGH, "VIDEO": str(i)} for i in range(3)]
    master_url = "https://fixture.invalid/master?token=fixture-secret"
    entries = [
        (item, f"https://fixture.invalid/{i}?sig=fixture-secret") for i, item in enumerate(attrs)
    ]
    started = set()
    cancelled = set()
    gate = asyncio.Event()

    async def fetch(app: Any, url: str, **kwargs: Any) -> UpstreamData:
        if url == master_url:
            return UpstreamData(master(entries), url, "application/vnd.apple.mpegurl")
        started.add(url)
        try:
            if failure == "bad-variant" and url == entries[0][1]:
                await asyncio.sleep(0)
                return UpstreamData(b"not HLS", url, "text/plain")
            await gate.wait()
        except asyncio.CancelledError:
            cancelled.add(url)
            raise
        raise AssertionError("The blocked inspection should have been cancelled")

    monkeypatch.setattr(m3u8_route, "fetch_upstream", fetch)
    response = await client.get(
        "/m3u8/selected",
        params={"u": master_url, "selections": json.dumps([descriptor(item) for item in attrs])},
    )
    assert response.status == (504 if failure == "deadline" else 502)
    expected = {entry[1] for entry in entries[1:]} if failure == "bad-variant" else started
    assert expected and cancelled == expected
    assert "fixture-secret" not in await response.text() and "fixture-secret" not in caplog.text


async def test_selected_bundled_encrypted_media_still_fails_before_segment_fetch(
    cdn: FakeCDN, proxy_factory: Any
) -> None:
    cdn.bodies["/master"] = master([(HIGH, "/fresh")])
    add_variant(cdn, "/fresh", [(1, b"soun"), (2, b"vide")])
    cdn.bodies["/fresh"] += b'#EXT-X-KEY:METHOD=AES-128,URI="encrypted-key"\n'
    client = await proxy_factory()
    response = await client.get("/m3u8/selected", params=selection_params(cdn, [descriptor(HIGH)]))
    assert response.status == 200
    entries = mf.master_entries(await response.text(), str(client.make_url("/")))
    child = await client.get(URL(next(iter(entries.values()))[1]).relative())
    assert child.status == 502 and "Encrypted fragments" in await child.text()
    assert cdn.hits["/fresh-media"] == cdn.hits["/encrypted-key"] == 0
