"""Exercise container CA policy with real public roots in isolated SSL contexts."""

import os
import ssl
import subprocess
from pathlib import Path
from unittest.mock import Mock

import pytest

from fmp4_demux_proxy import ca_trust

FIXTURES = Path(__file__).parent / "fixtures" / "ca-trust"
HASHED_ROOT_NAMES = {"emsign-g3.pem": "14bc7599.0", "comodo-aaa.pem": "ee64a828.0"}


@pytest.fixture
def isolated_store(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> ssl.SSLContext:
    # Never load or mutate the host's trust store.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.load_verify_locations(cafile=str(FIXTURES / "unaffected-roots.pem"))
    monkeypatch.setattr(ssl, "create_default_context", lambda: context)
    paths = ssl.get_default_verify_paths()._replace(
        capath=str(tmp_path), openssl_capath=str(tmp_path)
    )
    monkeypatch.delenv(paths.openssl_capath_env, raising=False)
    monkeypatch.setattr(ssl, "get_default_verify_paths", lambda: paths)
    return context


@pytest.mark.parametrize("root", ["emsign-g3.pem", "comodo-aaa.pem"])
def test_rejects_distrusted_active_root(isolated_store: ssl.SSLContext, root: str) -> None:
    isolated_store.load_verify_locations(cafile=str(FIXTURES / root))
    with pytest.raises(RuntimeError, match=r"Distrusted CA.*(emSign|AAA)"):
        ca_trust.verify_active_roots()


@pytest.mark.parametrize("root", ["emsign-g3.pem", "comodo-aaa.pem"])
def test_rejects_root_only_in_lazy_capath(
    isolated_store: ssl.SSLContext, tmp_path: Path, root: str
) -> None:
    # get_ca_certs() alone cannot see roots not yet loaded from OpenSSL's CApath.
    before = isolated_store.cert_store_stats()["x509_ca"]
    (tmp_path / HASHED_ROOT_NAMES[root]).write_bytes((FIXTURES / root).read_bytes())
    assert isolated_store.cert_store_stats()["x509_ca"] == before
    with pytest.raises(RuntimeError, match="Distrusted CA"):
        ca_trust.verify_active_roots()


@pytest.fixture
def real_default_store(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    """Use actual OpenSSL environment lookup and CPython path filtering."""
    # Match Linux's default-context sources without reading the Windows OS store.
    if hasattr(ssl.SSLContext, "_load_windows_store_certs"):
        monkeypatch.setattr(ssl.SSLContext, "_load_windows_store_certs", lambda *_: None)
    paths = ssl.get_default_verify_paths()
    monkeypatch.setenv(paths.openssl_cafile_env, str(FIXTURES / "unaffected-roots.pem"))
    empty = tmp_path / "empty"
    empty.mkdir()
    monkeypatch.setenv(paths.openssl_capath_env, str(empty))
    return empty


@pytest.mark.parametrize("root", HASHED_ROOT_NAMES)
def test_rejects_root_in_second_raw_ca_directory(
    real_default_store: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path, root: str
) -> None:
    stale = tmp_path / "stale"
    stale.mkdir()
    (stale / HASHED_ROOT_NAMES[root]).write_bytes((FIXTURES / root).read_bytes())
    paths = ssl.get_default_verify_paths()
    monkeypatch.setenv(
        paths.openssl_capath_env, os.pathsep.join([str(real_default_store), str(stale)])
    )
    # Both calls are real: a list is filtered out, and its roots remain lazy.
    assert ssl.get_default_verify_paths().capath is None
    assert len(ssl.create_default_context().get_ca_certs()) == 4
    with pytest.raises(RuntimeError, match="Distrusted CA"):
        ca_trust.verify_active_roots()


def test_accepts_good_raw_ca_directory_list(
    real_default_store: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    good = tmp_path / "good"
    good.mkdir()
    # First certificate is ISRG Root X1 (subject hash 4042bcee); all are public CAs.
    (good / "4042bcee.0").write_bytes((FIXTURES / "unaffected-roots.pem").read_bytes())
    paths = ssl.get_default_verify_paths()
    monkeypatch.setenv(paths.openssl_cafile_env, str(tmp_path / "absent-cafile"))
    monkeypatch.setenv(
        paths.openssl_capath_env, os.pathsep.join([str(real_default_store), str(good)])
    )
    assert ssl.get_default_verify_paths().capath is None
    assert ssl.create_default_context().get_ca_certs() == []
    assert ca_trust.verify_active_roots() == 4


def test_uses_compiled_ca_directory_when_override_is_unset(
    isolated_store: ssl.SSLContext, tmp_path: Path
) -> None:
    assert ssl.get_default_verify_paths().openssl_capath_env not in os.environ
    (tmp_path / HASHED_ROOT_NAMES["emsign-g3.pem"]).write_bytes(
        (FIXTURES / "emsign-g3.pem").read_bytes()
    )
    with pytest.raises(RuntimeError, match="Distrusted CA"):
        ca_trust.verify_active_roots()


def test_empty_override_does_not_use_compiled_ca_directory(
    isolated_store: ssl.SSLContext, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    paths = ssl.get_default_verify_paths()
    (tmp_path / HASHED_ROOT_NAMES["emsign-g3.pem"]).write_bytes(
        (FIXTURES / "emsign-g3.pem").read_bytes()
    )
    monkeypatch.setenv(paths.openssl_capath_env, "")
    assert ca_trust.verify_active_roots() == 4


@pytest.mark.parametrize("override", ["empty", "empty-entries"])
def test_empty_raw_directories_do_not_scan_current_directory(
    real_default_store: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path, override: str
) -> None:
    (tmp_path / HASHED_ROOT_NAMES["emsign-g3.pem"]).write_bytes(
        (FIXTURES / "emsign-g3.pem").read_bytes()
    )
    monkeypatch.chdir(tmp_path)
    paths = ssl.get_default_verify_paths()
    raw = "" if override == "empty" else os.pathsep.join(["", str(real_default_store), "", ""])
    monkeypatch.setenv(paths.openssl_capath_env, raw)
    assert ssl.get_default_verify_paths().capath is None
    assert ca_trust.verify_active_roots() == 4


@pytest.mark.parametrize("invalid", ["missing", "not-a-directory", "malformed-pem"])
def test_invalid_raw_directory_fails_closed(
    real_default_store: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path, invalid: str
) -> None:
    bad = tmp_path / "bad"
    if invalid == "not-a-directory":
        bad.write_text("not a directory", encoding="ascii")
    elif invalid == "malformed-pem":
        bad.mkdir()
        (bad / "14bc7599.0").write_text("not a certificate", encoding="ascii")
    paths = ssl.get_default_verify_paths()
    monkeypatch.setenv(
        paths.openssl_capath_env, os.pathsep.join([str(real_default_store), str(bad)])
    )
    assert ssl.get_default_verify_paths().capath is None
    with pytest.raises(OSError):
        ca_trust.verify_active_roots()


def test_empty_effective_store_fails_closed(
    real_default_store: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    paths = ssl.get_default_verify_paths()
    monkeypatch.setenv(paths.openssl_cafile_env, str(tmp_path / "absent-cafile"))
    monkeypatch.setenv(paths.openssl_capath_env, "")
    assert ssl.create_default_context().get_ca_certs() == []
    with pytest.raises(RuntimeError, match="empty"):
        ca_trust.verify_active_roots()


def test_accepts_unaffected_public_roots(isolated_store: ssl.SSLContext) -> None:
    # Includes emSign C1/C3/G1: policy must not ban all eMudhra/emSign roots.
    assert ca_trust.verify_active_roots() == 4
    assert isolated_store.verify_mode == ssl.CERT_REQUIRED
    assert isolated_store.check_hostname


def test_rejects_empty_store(
    isolated_store: ssl.SSLContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        ssl, "create_default_context", lambda: ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    )
    with pytest.raises(RuntimeError, match="empty"):
        ca_trust.verify_active_roots()


@pytest.mark.parametrize("weaken", ["hostname", "verification"])
def test_rejects_disabled_tls_verification(isolated_store: ssl.SSLContext, weaken: str) -> None:
    isolated_store.check_hostname = False
    if weaken == "verification":
        isolated_store.verify_mode = ssl.CERT_NONE
    with pytest.raises(RuntimeError, match="TLS verification"):
        ca_trust.verify_active_roots()


@pytest.mark.parametrize(
    ("version", "comparison", "accepted"),
    [
        ("20250419", 1, False),
        ("20250419+deb13u1", 0, True),
        ("20250419+deb13u2", 0, True),
    ],
)
def test_enforces_debian_package_floor(
    monkeypatch: pytest.MonkeyPatch, version: str, comparison: int, accepted: bool
) -> None:
    run = Mock(
        side_effect=[
            subprocess.CompletedProcess([], 0, stdout=f"install ok installed\n{version}"),
            subprocess.CompletedProcess([], comparison),
        ]
    )
    monkeypatch.setattr(subprocess, "run", run)
    if accepted:
        assert ca_trust.verify_ca_package() == version
    else:
        with pytest.raises(RuntimeError, match=r"ca-certificates.*20250419"):
            ca_trust.verify_ca_package()
    assert run.call_args_list[-1].args[0] == [
        "dpkg",
        "--compare-versions",
        version,
        "ge",
        "20250419+deb13u1",
    ]


def test_rejects_unconfigured_ca_package(monkeypatch: pytest.MonkeyPatch) -> None:
    run = Mock(
        return_value=subprocess.CompletedProcess(
            [], 0, stdout="deinstall ok config-files\n20250419+deb13u1"
        )
    )
    monkeypatch.setattr(subprocess, "run", run)
    with pytest.raises(RuntimeError, match="not installed"):
        ca_trust.verify_ca_package()


def test_package_query_failure_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        subprocess, "run", Mock(side_effect=subprocess.CalledProcessError(1, "dpkg-query"))
    )
    with pytest.raises(subprocess.CalledProcessError):
        ca_trust.verify_ca_package()


def test_reports_package_and_active_roots(
    isolated_store: ssl.SSLContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(ca_trust, "verify_ca_package", lambda: "20250419+deb13u1")
    report = ca_trust.check_ca_trust()
    assert report["ca_certificates"] == "20250419+deb13u1"
    assert report["active_ca_count"] == 4
    assert set(report["excluded_roots"]) == {"emSign ECC Root CA - G3", "AAA Certificate Services"}
