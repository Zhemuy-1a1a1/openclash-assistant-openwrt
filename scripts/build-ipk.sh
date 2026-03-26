#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$ROOT_DIR/luci-app-openclash-assistant"
MAKEFILE="$PKG_DIR/Makefile"
DIST_DIR="$ROOT_DIR/dist"

if [[ ! -f "$MAKEFILE" ]]; then
  echo "Makefile not found: $MAKEFILE" >&2
  exit 1
fi

pkg_name="$(sed -n 's/^PKG_NAME:=//p' "$MAKEFILE" | head -n 1)"
version="$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE" | head -n 1)"
release="$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE" | head -n 1)"
license="$(sed -n 's/^PKG_LICENSE:=//p' "$MAKEFILE" | head -n 1)"
maintainer="$(sed -n 's/^PKG_MAINTAINER:=//p' "$MAKEFILE" | head -n 1)"
title="$(sed -n 's/^LUCI_TITLE:=//p' "$MAKEFILE" | head -n 1)"
depends_raw="$(sed -n 's/^LUCI_DEPENDS:=//p' "$MAKEFILE" | head -n 1)"
pkg_arch="$(sed -n 's/^LUCI_PKGARCH:=//p' "$MAKEFILE" | head -n 1)"

depends="$(printf '%s\n' "$depends_raw" | tr ' ' '\n' | sed -n 's/^+//p' | paste -sd ', ' -)"
pkg_version="${version}-${release}"
artifact_name="${pkg_name}_${pkg_version}_${pkg_arch}.ipk"
artifact_path="$DIST_DIR/$artifact_name"
release_dir="$DIST_DIR/release/openclash-assistant-istoreos-v${version}-r${release}"

mkdir -p "$DIST_DIR" "$release_dir"

python3 - "$PKG_DIR" "$artifact_path" "$pkg_name" "$pkg_version" "$pkg_arch" "$license" "$maintainer" "$title" "$depends" <<'PY'
import gzip
import io
import pathlib
import sys
import tarfile

pkg_dir = pathlib.Path(sys.argv[1])
artifact_path = pathlib.Path(sys.argv[2])
pkg_name = sys.argv[3]
pkg_version = sys.argv[4]
pkg_arch = sys.argv[5]
license_name = sys.argv[6]
maintainer = sys.argv[7]
title = sys.argv[8]
depends = sys.argv[9]

root_dir = pkg_dir / "root"
htdocs_dir = pkg_dir / "htdocs"

control_files = {
    "control": f"""Package: {pkg_name}
Version: {pkg_version}
Depends: {depends}
Source: local
Section: luci
Priority: optional
Architecture: {pkg_arch}
Maintainer: {maintainer}
License: {license_name}
Description: {title}
 LuCI helper plugin for OpenClash with unified streaming/AI access checks,
 DNS tools, auto-switch guidance, and subscription conversion helpers.
""".encode(),
    "conffiles": b"/etc/config/openclash-assistant\n",
    "postinst": b"""#!/bin/sh
set -eu
chmod +x /usr/libexec/openclash-assistant/diag.sh 2>/dev/null || true
chmod +x /etc/uci-defaults/90_luci-openclash-assistant 2>/dev/null || true
/etc/uci-defaults/90_luci-openclash-assistant >/dev/null 2>&1 || true
uci -q commit openclash-assistant || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
exit 0
""",
    "postrm": b"""#!/bin/sh
set -eu
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
exit 0
""",
}

def dir_entries(base: pathlib.Path, prefix: str):
    dirs = set()
    for path in sorted(base.rglob("*")):
        rel = path.relative_to(base)
        parts = rel.parts[:-1] if path.is_file() else rel.parts
        current = prefix
        for part in parts:
            current = f"{current}/{part}" if current else part
            dirs.add(current)
    return sorted(dirs)

def add_bytes_file(tf: tarfile.TarFile, name: str, data: bytes, mode: int):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mtime = 0
    tf.addfile(info, io.BytesIO(data))

def add_dir(tf: tarfile.TarFile, name: str):
    info = tarfile.TarInfo(name=name)
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mtime = 0
    tf.addfile(info)

def build_control_tar() -> bytes:
    bio = io.BytesIO()
    with gzip.GzipFile(fileobj=bio, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tf:
            for name in ["control", "conffiles", "postinst", "postrm"]:
                mode = 0o755 if name in {"postinst", "postrm"} else 0o644
                add_bytes_file(tf, name, control_files[name], mode)
    return bio.getvalue()

def build_data_tar() -> bytes:
    bio = io.BytesIO()
    with gzip.GzipFile(fileobj=bio, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tf:
            for d in dir_entries(root_dir, ""):
                add_dir(tf, d)
            for path in sorted(root_dir.rglob("*")):
                rel = path.relative_to(root_dir).as_posix()
                if path.is_dir():
                    continue
                data = path.read_bytes()
                mode = path.stat().st_mode & 0o777
                add_bytes_file(tf, rel, data, mode)

            for d in dir_entries(htdocs_dir, "www"):
                add_dir(tf, d)
            for path in sorted(htdocs_dir.rglob("*")):
                rel = path.relative_to(htdocs_dir).as_posix()
                if path.is_dir():
                    continue
                data = path.read_bytes()
                mode = path.stat().st_mode & 0o777
                add_bytes_file(tf, f"www/{rel}", data, mode)
    return bio.getvalue()

control_tar = build_control_tar()
data_tar = build_data_tar()
debian_binary = b"2.0\n"

outer = io.BytesIO()
with gzip.GzipFile(fileobj=outer, mode="wb", mtime=0) as gz:
    with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        add_bytes_file(tf, "debian-binary", debian_binary, 0o644)
        add_bytes_file(tf, "control.tar.gz", control_tar, 0o644)
        add_bytes_file(tf, "data.tar.gz", data_tar, 0o644)

artifact_path.write_bytes(outer.getvalue())
artifact_path.chmod(0o644)
PY

shasum -a 256 "$artifact_path" > "$artifact_path.sha256"
cp "$artifact_path" "$release_dir/"
cp "$artifact_path.sha256" "$release_dir/"

printf '%s\n' "$artifact_path"
