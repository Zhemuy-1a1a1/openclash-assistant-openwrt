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

say() {
  printf '%s\n' "$1"
}

section() {
  printf '\n== %s ==\n' "$1"
}

fatal() {
  printf '[错误] %s\n' "$1" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_local_subconverter() {
  if ! have_cmd docker; then
    say "[提示] 未检测到 Docker，跳过本地订阅转换后端部署。"
    return 0
  fi

  section "部署本地订阅转换后端"
  if docker inspect openclash-assistant-subconverter >/dev/null 2>&1; then
    docker start openclash-assistant-subconverter >/dev/null 2>&1 || true
    say "[已满足] 本地 subconverter 容器已存在"
  else
    say "[部署] 正在拉取并启动本地 subconverter 后端..."
    if docker pull tindy2013/subconverter:latest >/dev/null 2>&1 && \
       docker run -d --restart unless-stopped --name openclash-assistant-subconverter -p 25500:25500 tindy2013/subconverter:latest >/dev/null 2>&1; then
      say "[完成] 本地 subconverter 后端已启动在 25500 端口"
    else
      say "[提示] 本地 subconverter 后端部署失败，订阅转换仍可手动指定其他后端。"
      return 0
    fi
  fi
}

pkg_installed() {
  opkg status "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  local label="$2"

  if pkg_installed "$pkg"; then
    printf '[已满足] %s\n' "$label"
    return 0
  fi

  printf '[自动补装] 缺少 %s，正在安装 %s ...\n' "$label" "$pkg"
  opkg update >/dev/null 2>&1 || {
    printf '[失败] 无法更新 opkg 软件源，安装 %s 失败。\n' "$pkg" >&2
    return 1
  }
  opkg install "$pkg" >/dev/null 2>&1 || {
    printf '[失败] 无法安装依赖包：%s\n' "$pkg" >&2
    return 1
  }
  printf '[已安装] %s\n' "$label"
}

check_runtime_env() {
  section "安装前环境检测"
  say "目标系统：iStoreOS / OpenWrt"

  if ! have_cmd uci; then
    fatal "缺少 uci，当前系统看起来不是标准 OpenWrt / iStoreOS 环境。"
  fi

  if [ ! -x /etc/init.d/rpcd ] || [ ! -x /etc/init.d/uhttpd ]; then
    fatal "缺少 rpcd 或 uhttpd 服务脚本，LuCI 运行环境不完整。"
  fi

  if [ ! -d /www/luci-static ] && [ ! -d /usr/lib/lua/luci ]; then
    fatal "未检测到 LuCI 文件，请先安装 LuCI。"
  fi

  if ! have_cmd opkg; then
    fatal "缺少 opkg，无法自动补装依赖。"
  fi

  section "自动补装依赖"
  ensure_pkg bash "bash 运行环境"
  ensure_pkg curl "curl 访问检查依赖"

  section "建议项检查"
  if [ -x /etc/init.d/openclash ] || [ -f /etc/config/openclash ]; then
    say "[已满足] 检测到 OpenClash"
  else
    say "[提示] 未检测到 OpenClash。插件可以安装，但核心功能默认面向 OpenClash 使用场景。"
  fi

  if pkg_installed dnsmasq-full; then
    say "[已满足] 检测到 dnsmasq-full"
  else
    say "[提示] 未检测到 dnsmasq-full。部分 DNS 检查与刷新能力可能受限。"
  fi
}

restart_services() {
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

clear_luci_cache() {
  rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
}

install_payload() {
  local tmpdir payload_line payload_tar
  check_runtime_env
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
  ensure_local_subconverter
  clear_luci_cache
  restart_services

  section "安装完成"
  say "[完成] OpenClash Assistant 已安装。"
  say "LuCI 入口：服务 -> OpenClash Assistant"
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
  rm -rf /www/luci-static/openclash-assistant/sub-web-modify
  docker rm -f openclash-assistant-subconverter >/dev/null 2>&1 || true
  rmdir /www/luci-static/resources/view/openclash-assistant 2>/dev/null || true
  clear_luci_cache
  restart_services
  section "卸载完成"
  say "[完成] OpenClash Assistant 已移除。"
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
  /www/luci-static/openclash-assistant/sub-web-modify/

Installer behavior:
  - checks LuCI / rpcd / uhttpd / uci
  - auto-installs bash and curl if missing
  - warns if OpenClash or dnsmasq-full are missing
EOF

cat > "$release_dir/RELEASE-NOTES.txt" <<EOF
OpenClash Assistant ${version}-${release}

Highlights:
- Unified "访问检查" panel for streaming and AI connectivity checks
- Default full-target auto checks with local card refresh
- DNS tool tab with Flush DNS action
- Built-in sub-web-modify frontend for subscription conversion

Target:
- iStoreOS / OpenWrt systems with LuCI
EOF

tar -C "$DIST_DIR/release" -czf "$release_tarball" "openclash-assistant-istoreos-v${version}-r${release}"

printf '%s\n' "$artifact_path"
