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

version="$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE" | head -n 1)"
release="$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE" | head -n 1)"

if [[ -z "$version" || -z "$release" ]]; then
  echo "Failed to parse PKG_VERSION/PKG_RELEASE from $MAKEFILE" >&2
  exit 1
fi

artifact_name="openclash-assistant-istoreos-v${version}-r${release}.run"
artifact_path="$DIST_DIR/$artifact_name"
release_dir="$DIST_DIR/release/openclash-assistant-istoreos-v${version}-r${release}"
release_tarball="$DIST_DIR/openclash-assistant-istoreos-v${version}-r${release}-release.tar.gz"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$DIST_DIR" "$tmpdir/payload"
cp -R "$PKG_DIR/root" "$tmpdir/payload/root"
cp -R "$PKG_DIR/htdocs" "$tmpdir/payload/htdocs"

payload_tar="$tmpdir/payload.tar.gz"
tar -C "$tmpdir/payload" -czf "$payload_tar" root htdocs

cat > "$artifact_path" <<'SH'
#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  sh openclash-assistant-*.run [--uninstall]

Actions:
  default      install/update OpenClash Assistant
  --uninstall  remove installed OpenClash Assistant files
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root." >&2
    exit 1
  fi
}

restart_services() {
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

install_payload() {
  local tmpdir payload_line payload_tar
  tmpdir="$(mktemp -d /tmp/openclash-assistant-run.XXXXXX)"
  trap 'test -n "${tmpdir:-}" && rm -rf "$tmpdir"' EXIT INT TERM

  payload_line="$(awk '/^__ARCHIVE_BELOW__$/ {print NR + 1; exit 0; }' "$0")"
  if [ -z "$payload_line" ]; then
    echo "Payload marker not found." >&2
    exit 1
  fi

  payload_tar="$tmpdir/payload.tar.gz"
  tail -n +"$payload_line" "$0" > "$payload_tar"
  tar -xzf "$payload_tar" -C "$tmpdir"

  mkdir -p /www
  tar -C "$tmpdir/root" -cf - . | tar -C / -xf -
  tar -C "$tmpdir/htdocs" -cf - . | tar -C /www -xf -

  chmod +x /usr/libexec/openclash-assistant/diag.sh 2>/dev/null || true
  chmod +x /etc/uci-defaults/90_luci-openclash-assistant 2>/dev/null || true
  /etc/uci-defaults/90_luci-openclash-assistant >/dev/null 2>&1 || true
  uci -q commit openclash-assistant || true
  restart_services

  echo "OpenClash Assistant installed."
}

uninstall_payload() {
  rm -f /etc/config/openclash-assistant
  rm -f /etc/uci-defaults/90_luci-openclash-assistant
  rm -f /usr/libexec/openclash-assistant/diag.sh
  rmdir /usr/libexec/openclash-assistant 2>/dev/null || true
  rm -f /usr/share/luci/menu.d/luci-app-openclash-assistant.json
  rm -f /usr/share/rpcd/acl.d/luci-app-openclash-assistant.json
  rm -f /www/luci-static/resources/view/openclash-assistant/overview.js
  rm -f /www/luci-static/resources/view/openclash-assistant/status.js
  rmdir /www/luci-static/resources/view/openclash-assistant 2>/dev/null || true
  restart_services
  echo "OpenClash Assistant removed."
}

main() {
  case "${1:-install}" in
    --help|-h) usage ;;
    --uninstall) require_root; uninstall_payload ;;
    install|"") require_root; install_payload ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "${1:-}"
exit 0
__ARCHIVE_BELOW__
SH

cat "$payload_tar" >> "$artifact_path"
chmod +x "$artifact_path"
shasum -a 256 "$artifact_path" > "$artifact_path.sha256"

mkdir -p "$release_dir"
cp "$artifact_path" "$release_dir/"
cp "$artifact_path.sha256" "$release_dir/"

cat > "$release_dir/INSTALL.txt" <<EOF
OpenClash Assistant for iStoreOS / OpenWrt
Version: ${version}-${release}

Install:
  chmod +x ${artifact_name}
  ./${artifact_name}

Uninstall:
  ./${artifact_name} --uninstall

What it installs:
  /etc/config/openclash-assistant
  /etc/uci-defaults/90_luci-openclash-assistant
  /usr/libexec/openclash-assistant/diag.sh
  /usr/share/luci/menu.d/luci-app-openclash-assistant.json
  /usr/share/rpcd/acl.d/luci-app-openclash-assistant.json
  /www/luci-static/resources/view/openclash-assistant/overview.js
  /www/luci-static/resources/view/openclash-assistant/status.js
EOF

cat > "$release_dir/RELEASE-NOTES.txt" <<EOF
OpenClash Assistant ${version}-${release}

Highlights:
- Unified "访问检查" panel for streaming and AI connectivity checks
- Default full-target auto checks with local card refresh
- DNS tool tab with Flush DNS action
- Auto-switch and subscription conversion pages retained

Target:
- iStoreOS / OpenWrt systems with LuCI
EOF

tar -C "$DIST_DIR/release" -czf "$release_tarball" "openclash-assistant-istoreos-v${version}-r${release}"

printf '%s\n' "$artifact_path"
