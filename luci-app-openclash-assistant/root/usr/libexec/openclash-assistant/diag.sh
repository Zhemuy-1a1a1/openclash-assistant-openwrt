#!/bin/sh
set -eu

CONFIG_NAME="openclash-assistant"
CONFIG_SECTION="main"
SUB_INI_LIST="/usr/share/openclash/res/sub_ini.list"
MEDIA_AI_RESULT_FILE="/tmp/openclash-assistant-media-ai-results.tsv"
MEDIA_AI_RUN_PID_FILE="/tmp/openclash-assistant-media-ai-run.pid"
MEDIA_AI_PROGRESS_FILE="/tmp/openclash-assistant-media-ai-progress.tsv"
FLUSH_DNS_STATE_FILE="/tmp/openclash-assistant-flush-dns-state.tsv"
SPLIT_TUNNEL_RESULT_FILE="/tmp/openclash-assistant-split-tunnel-results.tsv"
SPLIT_TUNNEL_RUN_PID_FILE="/tmp/openclash-assistant-split-tunnel-run.pid"
SPLIT_TUNNEL_PROGRESS_FILE="/tmp/openclash-assistant-split-tunnel-progress.tsv"
OPENCLASH_STREAMING_UNLOCK="/usr/share/openclash/openclash_streaming_unlock.lua"
OPENCLASH_UNLOCK_CACHE="/etc/openclash/history/streaming_unlock_cache"

bool_uci() {
  local value
  value="$(uci -q get "$CONFIG_NAME.$CONFIG_SECTION.$1" 2>/dev/null || echo "$2")"
  case "$value" in
    1|on|true|yes|enabled) echo true ;;
    *) echo false ;;
  esac
}

bool_uci_01() {
  local value
  value="$(uci -q get "$CONFIG_NAME.$CONFIG_SECTION.$1" 2>/dev/null || echo "$2")"
  case "$value" in
    1|on|true|yes|enabled) echo 1 ;;
    *) echo 0 ;;
  esac
}

str_uci() {
  uci -q get "$CONFIG_NAME.$CONFIG_SECTION.$1" 2>/dev/null || echo "$2"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

package_installed() {
  if command_exists opkg; then
    opkg status "$1" >/dev/null 2>&1
  elif command_exists apk; then
    apk info "$1" >/dev/null 2>&1
  else
    return 1
  fi
}

count_configs() {
  if [ -d /etc/openclash/config ]; then
    find /etc/openclash/config -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | wc -l | tr -d ' '
  else
    echo 0
  fi
}

service_enabled() {
  if [ -x /etc/init.d/openclash ]; then
    /etc/init.d/openclash enabled >/dev/null 2>&1 && echo true || echo false
  else
    echo false
  fi
}

service_running() {
  if [ -x /etc/init.d/openclash ]; then
    /etc/init.d/openclash running >/dev/null 2>&1 && echo true || echo false
  else
    if pgrep -f 'openclash|clash|mihomo' >/dev/null 2>&1; then
      echo true
    else
      echo false
    fi
  fi
}

json_string() {
  printf '%s' "$1" | awk 'BEGIN{ORS=""} { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if (NR > 1) printf "\\n"; printf "%s", $0 }'
}

shell_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

sanitize_one_line() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

json_find_string() {
  local json="$1"
  local key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

json_find_number() {
  local json="$1"
  local key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n 1
}

json_find_bool() {
  local json="$1"
  local key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":[[:space:]]*\\(true\\|false\\).*/\\1/p" | head -n 1
}

first_non_empty() {
  for value in "$@"; do
    if [ -n "${value:-}" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

number_prefix() {
  local value
  value="$(printf '%s' "${1:-}" | sed -n 's/^\([0-9][0-9]*\).*$/\1/p' | head -n 1)"
  [ -n "$value" ] && printf '%s' "$value" || printf '0'
}

media_status_is_good() {
  case "${1:-}" in
    reachable|available|full_support) return 0 ;;
    *) return 1 ;;
  esac
}

media_status_is_issue() {
  case "${1:-}" in
    restricted|no_unlock|blocked|failed|other_region|homemade_only|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

advice_level_weight() {
  case "${1:-ok}" in
    fix) echo 3 ;;
    risk) echo 2 ;;
    optimize) echo 1 ;;
    *) echo 0 ;;
  esac
}

advice_reset_items() {
  ADVICE_ITEMS=''
  ADVICE_ITEM_COUNT=0
  ADVICE_TOP_LEVEL='ok'
}

advice_append_raw() {
  if [ -n "${ADVICE_ITEMS:-}" ]; then
    ADVICE_ITEMS="${ADVICE_ITEMS},\n$1"
  else
    ADVICE_ITEMS="$1"
  fi
}

advice_update_top_level() {
  if [ "$(advice_level_weight "${1:-ok}")" -gt "$(advice_level_weight "${ADVICE_TOP_LEVEL:-ok}")" ]; then
    ADVICE_TOP_LEVEL="$1"
  fi
}

advice_action_tab() {
  printf '{ "type": "tab", "tab": "%s", "label": "%s" }' \
    "$(json_string "$1")" \
    "$(json_string "$2")"
}

advice_action_command() {
  printf '{ "type": "command", "command": "%s", "label": "%s" }' \
    "$(json_string "$1")" \
    "$(json_string "$2")"
}

advice_add_item() {
  local key level title text next action_json item_json
  key="$1"
  level="$2"
  title="$3"
  text="$4"
  next="$5"
  action_json="${6:-null}"

  item_json="$(printf '    {\n      "key": "%s",\n      "level": "%s",\n      "title": "%s",\n      "text": "%s",\n      "next": "%s",\n      "action": %s\n    }' \
    "$(json_string "$key")" \
    "$(json_string "$level")" \
    "$(json_string "$title")" \
    "$(json_string "$text")" \
    "$(json_string "$next")" \
    "$action_json")"
  advice_append_raw "$item_json"
  ADVICE_ITEM_COUNT=$((ADVICE_ITEM_COUNT + 1))
  advice_update_top_level "$level"
}

iso8601_to_human() {
  printf '%s' "$1" | sed 's/T/ /; s/\..*Z$//; s/Z$//'
}

file_mtime_human() {
  local file="$1"
  local value
  [ -f "$file" ] || return 0
  value="$(stat -c '%y' "$file" 2>/dev/null || true)"
  [ -n "$value" ] || value="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null || true)"
  printf '%s' "$value" | cut -d'.' -f1
}

clash_api_port() {
  uci -q get openclash.config.cn_port 2>/dev/null || echo 9090
}

clash_api_secret() {
  uci -q get openclash.config.dashboard_password 2>/dev/null || echo ''
}

clash_api_get() {
  local path="$1"
  local port secret
  command_exists curl || return 1
  port="$(clash_api_port)"
  secret="$(clash_api_secret)"
  if [ -n "$secret" ]; then
    curl -k -sS -m 6 -H "Authorization: Bearer ${secret}" "http://127.0.0.1:${port}${path}" 2>/dev/null || true
  else
    curl -k -sS -m 6 "http://127.0.0.1:${port}${path}" 2>/dev/null || true
  fi
}

clash_controller_ready() {
  local version_json
  version_json="$(clash_api_get '/version')"
  if [ -n "$version_json" ] && printf '%s' "$version_json" | grep -q '"version"'; then
    echo true
  else
    echo false
  fi
}

clash_proxy_json() {
  local name="$1"
  clash_api_get "/proxies/$(urlencode "$name")"
}

clash_primary_group_candidates() {
  printf '%s\n' \
    '守候网络' \
    '🐟 漏网之鱼' \
    '漏网之鱼' \
    '🌏 GFWlist' \
    'PROXY' \
    'Proxy' \
    '🚀 节点选择' \
    '♻️ 自动选择' \
    'GLOBAL'
}

clash_primary_group() {
  local candidate candidate_json old_ifs
  old_ifs="$IFS"
  IFS='
'
  for candidate in $(clash_primary_group_candidates); do
    candidate_json="$(clash_proxy_json "$candidate")"
    if [ -n "$candidate_json" ] && printf '%s' "$candidate_json" | grep -q '"type":"'; then
      IFS="$old_ifs"
      printf '%s' "$candidate"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

clash_current_route_state() {
  local group group_json node node_json group_type node_type group_delay node_delay node_alive tested_at
  group="$(clash_primary_group 2>/dev/null || true)"
  [ -n "$group" ] || return 0
  group_json="$(clash_proxy_json "$group")"
  [ -n "$group_json" ] || return 0

  node="$(json_find_string "$group_json" now)"
  group_type="$(json_find_string "$group_json" type)"
  group_delay="$(json_find_number "$group_json" delay)"
  tested_at="$(iso8601_to_human "$(json_find_string "$group_json" time)")"

  node_json=''
  node_type=''
  node_delay=''
  node_alive=''
  if [ -n "$node" ]; then
    node_json="$(clash_proxy_json "$node")"
    node_type="$(json_find_string "$node_json" type)"
    node_delay="$(json_find_number "$node_json" delay)"
    node_alive="$(json_find_bool "$node_json" alive)"
    [ -n "$tested_at" ] || tested_at="$(iso8601_to_human "$(json_find_string "$node_json" time)")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$group" \
    "$group_type" \
    "$node" \
    "$node_type" \
    "$(first_non_empty "$node_delay" "$group_delay")" \
    "$node_alive" \
    "$tested_at"
}

clash_config_runtime_state() {
  local config_json
  config_json="$(clash_api_get '/configs')"
  [ -n "$config_json" ] || return 0
  printf '%s\t%s\t%s\t%s\n' \
    "$(json_find_string "$config_json" mode)" \
    "$(json_find_string "$config_json" log-level)" \
    "$(json_find_bool "$config_json" ipv6)" \
    "$(json_find_bool "$config_json" allow-lan)"
}

clash_connection_memory_mb() {
  local conn_json memory_bytes
  conn_json="$(clash_api_get '/connections')"
  memory_bytes="$(json_find_number "$conn_json" memory)"
  [ -n "$memory_bytes" ] || return 0
  awk -v value="$memory_bytes" 'BEGIN { printf "%.1f", value / 1048576 }'
}

cloudflare_trace_value() {
  local field="$1"
  local trace
  command_exists curl || return 0
  trace="$(curl -k -sS -m 8 'https://www.cloudflare.com/cdn-cgi/trace' 2>/dev/null || true)"
  printf '%s\n' "$trace" | sed -n "s/^${field}=\\(.*\\)$/\\1/p" | head -n 1
}

cpu_usage_percent() {
  top -bn1 2>/dev/null | awk -F'[% ]+' '
    /^CPU:/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "idle") {
          value = 100 - $(i - 1);
          if (value < 0) value = 0;
          printf "%d", value;
          exit;
        }
      }
    }'
}

memory_usage_percent() {
  top -bn1 2>/dev/null | awk '
    /^Mem:/ {
      used=$2; free=$4;
      gsub(/K/, "", used);
      gsub(/K/, "", free);
      total=used+free;
      if (total > 0) printf "%d", (used * 100) / total;
      exit;
    }'
}

clash_process_usage() {
  top -bn1 2>/dev/null | awk '
    NR > 4 && ($0 ~ /\/etc\/openclash\/clash/ || $0 ~ /clash_meta/ || $0 ~ /mihomo/) {
      printf "%s\t%s", $7, $6;
      exit;
    }'
}

recent_error_count() {
  local value
  if command_exists logread; then
    value="$(logread 2>/dev/null | tail -n 300 | grep -Ei 'openclash|clash|mihomo' | grep -Evi 'openclash-assistant|accepted login' | grep -Eic 'error|failed|fatal|panic|exception|warning' || true)"
    [ -n "$value" ] || value=0
    printf '%s' "$value"
  else
    echo 0
  fi
}

service_running_named() {
  local name="$1"
  if [ -x "/etc/init.d/$name" ]; then
    "/etc/init.d/$name" running >/dev/null 2>&1 && echo true || echo false
  else
    if pgrep -f "$name" >/dev/null 2>&1; then
      echo true
    else
      echo false
    fi
  fi
}

dns_chain_label() {
  local openclash_running="$1"
  local dnsmasq_running="$2"
  local smartdns_available="$3"
  local smartdns_running="$4"

  if [ "$dnsmasq_running" = true ] && [ "$smartdns_available" = true ] && [ "$smartdns_running" = true ] && [ "$openclash_running" = true ]; then
    echo 'dnsmasq -> smartdns -> OpenClash'
  elif [ "$dnsmasq_running" = true ] && [ "$smartdns_available" = true ] && [ "$smartdns_running" = true ]; then
    echo 'dnsmasq -> smartdns'
  elif [ "$dnsmasq_running" = true ] && [ "$openclash_running" = true ]; then
    echo 'dnsmasq -> OpenClash'
  elif [ "$dnsmasq_running" = true ]; then
    echo 'dnsmasq (OpenClash 未接管)'
  elif [ "$openclash_running" = true ]; then
    echo 'OpenClash 运行中（dnsmasq 未就绪）'
  else
    echo '未检测到可用 DNS 服务链路'
  fi
}

dns_diag_line() {
  local openclash_running="$1"
  local dnsmasq_running="$2"
  local smartdns_available="$3"
  local smartdns_running="$4"
  local dnsmasq_full="$5"
  local chain code level summary action

  chain="$(dns_chain_label "$openclash_running" "$dnsmasq_running" "$smartdns_available" "$smartdns_running")"
  code='chain_ok'
  level='good'
  summary='DNS 服务链路看起来正常。'
  action='如仍有解析异常，可先执行 Flush DNS，再复测访问检查。'

  if [ "$openclash_running" != true ]; then
    code='openclash_stopped'
    level='warn'
    summary='OpenClash 未运行，当前 DNS 接管可能未生效。'
    action='先启动 OpenClash，再执行 Flush DNS。'
  elif [ "$dnsmasq_running" != true ]; then
    code='dnsmasq_not_running'
    level='bad'
    summary='dnsmasq 未运行，DNS 请求链路不完整。'
    action='先恢复 dnsmasq 服务，再检查 OpenClash 日志。'
  elif [ "$dnsmasq_full" != true ]; then
    code='dnsmasq_full_missing'
    level='warn'
    summary='未检测到 dnsmasq-full，部分 DNS 能力可能受限。'
    action='安装 dnsmasq-full 后重启 OpenClash，并再次检测。'
  elif [ "$smartdns_available" = true ] && [ "$smartdns_running" = true ]; then
    code='smartdns_parallel'
    level='warn'
    summary='smartdns 与 OpenClash 同时运行，可能存在双重 DNS 接管。'
    action='如出现解析异常，请确认 LuCI 中仅保留一条主 DNS 接管链路。'
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$chain" "$code" "$level" "$summary" "$action"
}

flush_dns_state_value() {
  local field="$1"
  [ -r "$FLUSH_DNS_STATE_FILE" ] || return 0
  awk -F '\t' -v field="$field" '
    NR == 1 {
      if (field == "last_run_at") print $1;
      else if (field == "status") print $2;
      else if (field == "message") print $3;
    }' "$FLUSH_DNS_STATE_FILE"
}

write_flush_dns_state() {
  local last_run_at="$1"
  local status="$2"
  local message="$3"
  printf '%s\t%s\t%s\n' "$last_run_at" "$status" "$(sanitize_one_line "$message")" > "$FLUSH_DNS_STATE_FILE"
}

progress_state_value() {
  local file="$1"
  local field="$2"
  [ -r "$file" ] || return 0
  awk -F '\t' -v field="$field" '
    NR == 1 {
      if (field == "selected") print $1;
      else if (field == "completed") print $2;
      else if (field == "started_at") print $3;
    }' "$file"
}

write_progress_state() {
  local file="$1"
  local selected="$2"
  local completed="$3"
  local started_at="$4"
  printf '%s\t%s\t%s\n' "$selected" "$completed" "$started_at" > "$file"
}

milliseconds_from_seconds() {
  printf '%s\n' "$1" | awk 'BEGIN{value=0} { value=$1 * 1000; if (value < 1) value = 1; printf "%d", value }'
}

media_ai_target_keys() {
  printf '%s\n' netflix disney youtube prime_video hbo_max dazn paramount_plus discovery_plus tvb_anywhere bilibili openai claude gemini grok perplexity poe cursor codex
}

media_ai_target_label() {
  case "$1" in
    netflix) printf '%s' 'Netflix' ;;
    disney) printf '%s' 'Disney+' ;;
    youtube) printf '%s' 'YouTube Premium' ;;
    prime_video) printf '%s' 'Prime Video' ;;
    hbo_max) printf '%s' 'HBO Max' ;;
    dazn) printf '%s' 'DAZN' ;;
    paramount_plus) printf '%s' 'Paramount+' ;;
    discovery_plus) printf '%s' 'Discovery+' ;;
    tvb_anywhere) printf '%s' 'TVB Anywhere+' ;;
    bilibili) printf '%s' 'Bilibili' ;;
    openai) printf '%s' 'OpenAI' ;;
    claude) printf '%s' 'Claude' ;;
    gemini) printf '%s' 'Gemini' ;;
    grok) printf '%s' 'Grok' ;;
    perplexity) printf '%s' 'Perplexity' ;;
    poe) printf '%s' 'Poe' ;;
    cursor) printf '%s' 'Cursor' ;;
    codex) printf '%s' 'Codex / API' ;;
    *) printf '%s' "$1" ;;
  esac
}

media_ai_target_type() {
  case "$1" in
    netflix) printf '%s' 'Netflix' ;;
    disney) printf '%s' 'Disney Plus' ;;
    youtube) printf '%s' 'YouTube Premium' ;;
    prime_video) printf '%s' 'Amazon Prime Video' ;;
    hbo_max) printf '%s' 'HBO Max' ;;
    dazn) printf '%s' 'DAZN' ;;
    paramount_plus) printf '%s' 'Paramount Plus' ;;
    discovery_plus) printf '%s' 'Discovery Plus' ;;
    tvb_anywhere) printf '%s' 'TVB Anywhere+' ;;
    bilibili) printf '%s' 'Bilibili' ;;
    openai) printf '%s' 'OpenAI' ;;
    claude) printf '%s' 'Claude' ;;
    gemini) printf '%s' 'Gemini' ;;
    grok) printf '%s' 'Grok' ;;
    perplexity) printf '%s' 'Perplexity' ;;
    poe) printf '%s' 'Poe' ;;
    cursor) printf '%s' 'Cursor' ;;
    codex) printf '%s' 'Codex / API' ;;
    *) printf '%s' "$1" ;;
  esac
}

media_ai_target_assistant_option() {
  case "$1" in
    netflix) printf '%s' 'media_detect_netflix' ;;
    disney) printf '%s' 'media_detect_disney' ;;
    youtube) printf '%s' 'media_detect_youtube' ;;
    prime_video) printf '%s' 'media_detect_prime_video' ;;
    hbo_max) printf '%s' 'media_detect_hbo_max' ;;
    dazn) printf '%s' 'media_detect_dazn' ;;
    paramount_plus) printf '%s' 'media_detect_paramount_plus' ;;
    discovery_plus) printf '%s' 'media_detect_discovery_plus' ;;
    tvb_anywhere) printf '%s' 'media_detect_tvb_anywhere' ;;
    bilibili) printf '%s' 'media_detect_bilibili' ;;
    openai) printf '%s' 'ai_detect_openai' ;;
    claude) printf '%s' 'ai_detect_claude' ;;
    gemini) printf '%s' 'ai_detect_gemini' ;;
    grok) printf '%s' 'ai_detect_grok' ;;
    perplexity) printf '%s' 'ai_detect_perplexity' ;;
    poe) printf '%s' 'ai_detect_poe' ;;
    cursor) printf '%s' 'ai_detect_cursor' ;;
    codex) printf '%s' 'ai_detect_codex' ;;
    *) return 1 ;;
  esac
}

media_ai_target_openclash_toggle_option() {
  case "$1" in
    netflix) printf '%s' 'stream_auto_select_netflix' ;;
    disney) printf '%s' 'stream_auto_select_disney' ;;
    youtube) printf '%s' 'stream_auto_select_ytb' ;;
    prime_video) printf '%s' 'stream_auto_select_prime_video' ;;
    hbo_max) printf '%s' 'stream_auto_select_hbo_max' ;;
    dazn) printf '%s' 'stream_auto_select_dazn' ;;
    paramount_plus) printf '%s' 'stream_auto_select_paramount_plus' ;;
    discovery_plus) printf '%s' 'stream_auto_select_discovery_plus' ;;
    tvb_anywhere) printf '%s' 'stream_auto_select_tvb_anywhere' ;;
    bilibili) printf '%s' 'stream_auto_select_bilibili' ;;
    openai) printf '%s' 'stream_auto_select_openai' ;;
    *) return 1 ;;
  esac
}

media_ai_target_openclash_filter_suffix() {
  case "$1" in
    netflix) printf '%s' 'netflix' ;;
    disney) printf '%s' 'disney' ;;
    youtube) printf '%s' 'ytb' ;;
    prime_video) printf '%s' 'prime_video' ;;
    hbo_max) printf '%s' 'hbo_max' ;;
    dazn) printf '%s' 'dazn' ;;
    paramount_plus) printf '%s' 'paramount_plus' ;;
    discovery_plus) printf '%s' 'discovery_plus' ;;
    tvb_anywhere) printf '%s' 'tvb_anywhere' ;;
    bilibili) printf '%s' 'bilibili' ;;
    openai) printf '%s' 'openai' ;;
    *) return 1 ;;
  esac
}

media_ai_target_enabled() {
  local option default_value

  option="$(media_ai_target_assistant_option "$1" 2>/dev/null || true)"
  [ -n "$option" ] || {
    echo false
    return 0
  }

  default_value=0
  case "$1" in
    openai|claude|gemini|grok|perplexity|poe|cursor|codex)
      default_value=1
      ;;
  esac

  bool_uci "$option" "$default_value"
}

media_ai_target_probe_backend() {
  case "$1" in
    openai|codex|claude|gemini) printf '%s' 'official_api' ;;
    *) printf '%s' 'openclash' ;;
  esac
}

media_ai_target_probe_url() {
  case "$1" in
    netflix) printf '%s' 'https://www.netflix.com/' ;;
    disney) printf '%s' 'https://www.disneyplus.com/' ;;
    youtube) printf '%s' 'https://www.youtube.com/' ;;
    prime_video) printf '%s' 'https://www.primevideo.com/' ;;
    hbo_max) printf '%s' 'https://www.max.com/' ;;
    dazn) printf '%s' 'https://www.dazn.com/' ;;
    paramount_plus) printf '%s' 'https://www.paramountplus.com/' ;;
    discovery_plus) printf '%s' 'https://www.discoveryplus.com/' ;;
    tvb_anywhere) printf '%s' 'https://u.tvbanywhere.com/' ;;
    bilibili) printf '%s' 'https://www.bilibili.com/' ;;
    openai) printf '%s' 'https://api.openai.com/v1/models' ;;
    claude) printf '%s' 'https://api.anthropic.com/v1/messages' ;;
    gemini) printf '%s' 'https://generativelanguage.googleapis.com/v1beta/models?key=test-key' ;;
    grok) printf '%s' 'https://grok.com/' ;;
    perplexity) printf '%s' 'https://www.perplexity.ai/' ;;
    poe) printf '%s' 'https://poe.com/' ;;
    cursor) printf '%s' 'https://www.cursor.com/' ;;
    codex) printf '%s' 'https://api.openai.com/v1/models' ;;
    *) return 1 ;;
  esac
}

split_tunnel_target_keys() {
  printf '%s\n' \
    alibaba netease bytedance tencent qualcomm_cn cloudflare_cn \
    cloudflare bytedance_global discord x medium crunchyroll \
    chatgpt sora openai_web claude gemini grok anthropic perplexity \
    jsdelivr cdnjs cloudflaremirrors npm kali unpkg nodejs gitlab \
    coinbase okx
}

split_tunnel_target_label() {
  case "$1" in
    alibaba) printf '%s' '阿里云' ;;
    netease) printf '%s' '网易云音乐' ;;
    bytedance) printf '%s' '字节跳动' ;;
    tencent) printf '%s' '腾讯' ;;
    qualcomm_cn) printf '%s' '高通中国' ;;
    cloudflare_cn) printf '%s' 'Cloudflare 中国网络' ;;
    cloudflare) printf '%s' 'Cloudflare' ;;
    bytedance_global) printf '%s' '字节海外' ;;
    discord) printf '%s' 'Discord' ;;
    x) printf '%s' 'X / Twitter' ;;
    medium) printf '%s' 'Medium' ;;
    crunchyroll) printf '%s' 'Crunchyroll' ;;
    chatgpt) printf '%s' 'ChatGPT' ;;
    sora) printf '%s' 'Sora' ;;
    openai_web) printf '%s' 'OpenAI 官网' ;;
    claude) printf '%s' 'Claude' ;;
    grok) printf '%s' 'Grok' ;;
    anthropic) printf '%s' 'Anthropic' ;;
    gemini) printf '%s' 'Gemini' ;;
    perplexity) printf '%s' 'Perplexity' ;;
    jsdelivr) printf '%s' 'jsDelivr' ;;
    cdnjs) printf '%s' 'cdnjs' ;;
    cloudflaremirrors) printf '%s' 'Cloudflare 镜像' ;;
    npm) printf '%s' 'npm Registry' ;;
    kali) printf '%s' 'Kali Download' ;;
    unpkg) printf '%s' 'unpkg' ;;
    nodejs) printf '%s' 'Node.js' ;;
    gitlab) printf '%s' 'GitLab' ;;
    coinbase) printf '%s' 'Coinbase' ;;
    okx) printf '%s' 'OKX' ;;
    *) printf '%s' "$1" ;;
  esac
}

split_tunnel_target_group() {
  case "$1" in
    alibaba|netease|bytedance|tencent|qualcomm_cn|cloudflare_cn) printf '%s' '国内' ;;
    cloudflare|bytedance_global|discord|x|medium|crunchyroll) printf '%s' '国际' ;;
    chatgpt|sora|openai_web|claude|grok|anthropic|gemini|perplexity) printf '%s' 'AI' ;;
    jsdelivr|cdnjs|cloudflaremirrors|npm|kali|unpkg|nodejs|gitlab) printf '%s' '开发 / 静态' ;;
    coinbase|okx) printf '%s' '加密 / 金融' ;;
    *) printf '%s' '其他' ;;
  esac
}

split_tunnel_target_url() {
  case "$1" in
    alibaba) printf '%s' 'https://www.aliyun.com/' ;;
    netease) printf '%s' 'https://music.163.com/' ;;
    bytedance) printf '%s' 'https://www.bytedance.com/' ;;
    tencent) printf '%s' 'https://www.qq.com/' ;;
    qualcomm_cn) printf '%s' 'https://www.qualcomm.cn/' ;;
    cloudflare_cn) printf '%s' 'https://www.cloudflare-cn.com/' ;;
    cloudflare) printf '%s' 'https://www.cloudflare.com/' ;;
    bytedance_global) printf '%s' 'https://www.byteplus.com/' ;;
    discord) printf '%s' 'https://discord.com/' ;;
    x) printf '%s' 'https://x.com/' ;;
    medium) printf '%s' 'https://medium.com/' ;;
    crunchyroll) printf '%s' 'https://www.crunchyroll.com/' ;;
    chatgpt) printf '%s' 'https://chatgpt.com/' ;;
    sora) printf '%s' 'https://sora.com/' ;;
    openai_web) printf '%s' 'https://openai.com/' ;;
    claude) printf '%s' 'https://claude.ai/' ;;
    grok) printf '%s' 'https://grok.com/' ;;
    anthropic) printf '%s' 'https://www.anthropic.com/' ;;
    gemini) printf '%s' 'https://gemini.google.com/' ;;
    perplexity) printf '%s' 'https://www.perplexity.ai/' ;;
    jsdelivr) printf '%s' 'https://cdn.jsdelivr.net/npm/jquery@3.7.1/dist/jquery.min.js' ;;
    cdnjs) printf '%s' 'https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js' ;;
    cloudflaremirrors) printf '%s' 'https://cloudflaremirrors.com/' ;;
    npm) printf '%s' 'https://registry.npmjs.org/' ;;
    kali) printf '%s' 'https://kali.download/' ;;
    unpkg) printf '%s' 'https://unpkg.com/react@18/umd/react.production.min.js' ;;
    nodejs) printf '%s' 'https://nodejs.org/' ;;
    gitlab) printf '%s' 'https://gitlab.com/' ;;
    coinbase) printf '%s' 'https://www.coinbase.com/' ;;
    okx) printf '%s' 'https://www.okx.com/' ;;
    *) return 1 ;;
  esac
}

split_tunnel_trace_url() {
  case "$1" in
    cloudflare_cn) printf '%s' 'https://www.cloudflare-cn.com/cdn-cgi/trace' ;;
    cloudflare) printf '%s' 'https://www.cloudflare.com/cdn-cgi/trace' ;;
    bytedance_global) printf '%s' 'https://www.byteplus.com/cdn-cgi/trace' ;;
    discord) printf '%s' 'https://discord.com/cdn-cgi/trace' ;;
    x) printf '%s' 'https://x.com/cdn-cgi/trace' ;;
    medium) printf '%s' 'https://medium.com/cdn-cgi/trace' ;;
    chatgpt) printf '%s' 'https://chatgpt.com/cdn-cgi/trace' ;;
    sora) printf '%s' 'https://sora.com/cdn-cgi/trace' ;;
    openai_web) printf '%s' 'https://openai.com/cdn-cgi/trace' ;;
    claude) printf '%s' 'https://claude.ai/cdn-cgi/trace' ;;
    grok) printf '%s' 'https://grok.com/cdn-cgi/trace' ;;
    anthropic) printf '%s' 'https://www.anthropic.com/cdn-cgi/trace' ;;
    perplexity) printf '%s' 'https://www.perplexity.ai/cdn-cgi/trace' ;;
    cdnjs) printf '%s' 'https://cdnjs.cloudflare.com/cdn-cgi/trace' ;;
    cloudflaremirrors) printf '%s' 'https://cloudflaremirrors.com/cdn-cgi/trace' ;;
    gitlab) printf '%s' 'https://gitlab.com/cdn-cgi/trace' ;;
    okx) printf '%s' 'https://www.okx.com/cdn-cgi/trace' ;;
    *) return 1 ;;
  esac
}

extract_host_from_url() {
  local input host
  input="$(sanitize_one_line "$1")"
  input="${input#http://}"
  input="${input#https://}"
  host="${input%%/*}"
  host="${host%%\?*}"
  host="${host%%\#*}"
  printf '%s' "$host"
}

strip_www_prefix() {
  printf '%s' "$1" | sed 's/^www\.//'
}

split_route_service_meta() {
  local key
  key="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$key" in
    youtube|youtubepremium|youtube\ premium) printf '%s\t%s\t%s\t%s\t%s\n' 'YouTube Premium' 'https://www.youtube.com/premium' 'proxy' '国际视频通常更适合走代理。' 'youtube' ;;
    netflix) printf '%s\t%s\t%s\t%s\t%s\n' 'Netflix' 'https://www.netflix.com/' 'proxy' 'Netflix 更适合走代理，并单独用流媒体线路。' 'netflix' ;;
    disney|disneyplus|disney+) printf '%s\t%s\t%s\t%s\t%s\n' 'Disney+' 'https://www.disneyplus.com/' 'proxy' 'Disney+ 更适合走代理，并尽量使用流媒体地区节点。' 'disney' ;;
    tiktok) printf '%s\t%s\t%s\t%s\t%s\n' 'TikTok' 'https://www.tiktok.com/' 'proxy' 'TikTok 更适合走代理，并尽量保持地区稳定。' '' ;;
    spotify) printf '%s\t%s\t%s\t%s\t%s\n' 'Spotify' 'https://open.spotify.com/' 'proxy' 'Spotify 更适合走代理，并尽量保持地区一致。' '' ;;
    chatgpt) printf '%s\t%s\t%s\t%s\t%s\n' 'ChatGPT' 'https://chatgpt.com/' 'proxy' 'ChatGPT 建议走 AI 分组或稳定代理节点。' 'chatgpt' ;;
    openai|openaiweb|openai.com) printf '%s\t%s\t%s\t%s\t%s\n' 'OpenAI 官网' 'https://openai.com/' 'proxy' 'OpenAI 官网建议走 AI 分组或稳定代理节点。' 'openai_web' ;;
    claude) printf '%s\t%s\t%s\t%s\t%s\n' 'Claude' 'https://claude.ai/' 'proxy' 'Claude 建议走 AI 分组或稳定代理节点。' 'claude' ;;
    gemini) printf '%s\t%s\t%s\t%s\t%s\n' 'Gemini' 'https://gemini.google.com/' 'proxy' 'Gemini 建议走 AI 分组或稳定代理节点。' 'gemini' ;;
    grok) printf '%s\t%s\t%s\t%s\t%s\n' 'Grok' 'https://grok.com/' 'proxy' 'Grok 建议走代理，并优先使用国际节点。' 'grok' ;;
    perplexity) printf '%s\t%s\t%s\t%s\t%s\n' 'Perplexity' 'https://www.perplexity.ai/' 'proxy' 'Perplexity 建议走 AI 分组或稳定代理节点。' 'perplexity' ;;
    bilibili) printf '%s\t%s\t%s\t%s\t%s\n' 'Bilibili' 'https://www.bilibili.com/' 'direct' '国内站点通常更适合直连。' '' ;;
    qq|tencent) printf '%s\t%s\t%s\t%s\t%s\n' '腾讯' 'https://www.qq.com/' 'direct' '国内站点通常更适合直连。' '' ;;
    aliyun|alibaba) printf '%s\t%s\t%s\t%s\t%s\n' '阿里云' 'https://www.aliyun.com/' 'direct' '国内站点通常更适合直连。' 'alibaba' ;;
    x|twitter) printf '%s\t%s\t%s\t%s\t%s\n' 'X / Twitter' 'https://x.com/' 'proxy' '国际社交站点通常更适合走代理。' 'x' ;;
    discord) printf '%s\t%s\t%s\t%s\t%s\n' 'Discord' 'https://discord.com/' 'proxy' 'Discord 通常更适合走代理。' 'discord' ;;
    npm) printf '%s\t%s\t%s\t%s\t%s\n' 'npm Registry' 'https://registry.npmjs.org/' 'proxy' '国际开发资源通常更适合走代理。' 'npm' ;;
    nodejs) printf '%s\t%s\t%s\t%s\t%s\n' 'Node.js' 'https://nodejs.org/' 'proxy' '国际开发资源通常更适合走代理。' 'nodejs' ;;
    *) return 1 ;;
  esac
}

split_route_expected_from_host() {
  local host
  host="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$host" in
    *.cn|*.com.cn|localhost|*.lan|qq.com|*.qq.com|aliyun.com|*.aliyun.com|163.com|*.163.com|bilibili.com|*.bilibili.com|jd.com|*.jd.com)
      printf '%s\t%s\n' 'direct' '这个站点更像国内直连站点，通常不需要绕到代理。'
      ;;
    chatgpt.com|*.chatgpt.com|openai.com|*.openai.com|claude.ai|*.claude.ai|anthropic.com|*.anthropic.com|gemini.google.com|*.gemini.google.com|grok.com|*.grok.com|perplexity.ai|*.perplexity.ai|netflix.com|*.netflix.com|disneyplus.com|*.disneyplus.com|youtube.com|*.youtube.com|tiktok.com|*.tiktok.com|spotify.com|*.spotify.com|x.com|*.x.com|twitter.com|*.twitter.com|discord.com|*.discord.com|nodejs.org|*.nodejs.org|npmjs.org|*.npmjs.org|gitlab.com|*.gitlab.com)
      printf '%s\t%s\n' 'proxy' '这个站点更像国际或 AI 服务，通常更适合走代理。'
      ;;
    *)
      printf '%s\t%s\n' 'unknown' '这个站点没有预设建议，先看实际走向是否符合你的预期。'
      ;;
  esac
}

split_route_trace_url() {
  local service_key="$1"
  local host="$2"
  if [ -n "$service_key" ]; then
    split_tunnel_trace_url "$service_key" 2>/dev/null && return 0
  fi
  [ -n "$host" ] || return 1
  printf '%s' "https://${host}/cdn-cgi/trace"
}

clash_connection_lookup_host() {
  local host="$1"
  local conn_json tmp_file output_file lua_output
  [ -n "$host" ] || return 0
  command_exists lua || return 0
  conn_json="$(clash_api_get '/connections')"
  [ -n "$conn_json" ] || return 0

  tmp_file="$(mktemp /tmp/openclash-assistant-conn.XXXXXX)"
  output_file="$(mktemp /tmp/openclash-assistant-conn-out.XXXXXX)"
  printf '%s' "$conn_json" > "$tmp_file"

  lua - "$host" "$tmp_file" > "$output_file" <<'EOF'
local target = (arg[1] or ""):lower()
local path = arg[2] or ""
if target == "" then
  os.exit(0)
end

local ok, jsonc = pcall(require, "luci.jsonc")
if not ok then
  os.exit(0)
end

local file = io.open(path)
if not file then
  os.exit(0)
end

local raw = file:read("*a") or ""
file:close()
if raw == "" then
  os.exit(0)
end

local data = jsonc.parse(raw)
if type(data) ~= "table" or type(data.connections) ~= "table" then
  os.exit(0)
end

local function normalize(value)
  if value == nil then
    return ""
  end
  value = tostring(value)
  value = value:gsub("[\t\r\n]", " ")
  return value
end

local function host_match(value)
  value = (value or ""):lower()
  if value == "" then
    return false
  end
  if value == target then
    return true
  end
  return value:sub(-(#("." .. target))) == "." .. target
end

local best = nil
for _, conn in ipairs(data.connections) do
  local metadata = conn.metadata or {}
  if host_match(metadata.host) or host_match(metadata.sniffHost) then
    if not best or (normalize(conn.start) > normalize(best.start)) then
      best = conn
    end
  end
end

if not best then
  os.exit(0)
end

local metadata = best.metadata or {}
local chains = best.chains or {}
local route = {}
for i = #chains, 1, -1 do
  route[#route + 1] = normalize(chains[i])
end

io.write(
  normalize(metadata.host ~= "" and metadata.host or metadata.sniffHost), "\t",
  normalize(best.rule), "\t",
  normalize(best.rulePayload), "\t",
  normalize(chains[1]), "\t",
  normalize(chains[#chains]), "\t",
  normalize(table.concat(route, " -> ")), "\t",
  normalize(metadata.dnsMode), "\t",
  normalize(metadata.remoteDestination), "\t",
  normalize(metadata.destinationIP), "\t",
  normalize(best.start), "\n"
)
EOF
  lua_output="$(cat "$output_file" 2>/dev/null || true)"
  rm -f "$tmp_file"
  rm -f "$output_file"
  printf '%s' "$lua_output"
}

split_route_capture_connection() {
  local url="$1"
  local host="$2"
  local conn_line pid tries host_no_www

  [ -n "$url" ] || return 0
  [ -n "$host" ] || return 0
  command_exists curl || return 0

  host_no_www="$(strip_www_prefix "$host")"
  (curl -k -L -A 'Mozilla/5.0' -o /dev/null -sS -m 20 "$url" >/dev/null 2>&1 || true) &
  pid="$!"
  conn_line=''
  tries=0

  while [ "$tries" -lt 3 ]; do
    sleep 1
    conn_line="$(clash_connection_lookup_host "$host" 2>/dev/null || true)"
    if [ -z "$conn_line" ] && [ "$host_no_www" != "$host" ]; then
      conn_line="$(clash_connection_lookup_host "$host_no_www" 2>/dev/null || true)"
    fi
    [ -n "$conn_line" ] && break
    tries=$((tries + 1))
    kill -0 "$pid" >/dev/null 2>&1 || [ "$tries" -ge 1 ] && true
  done

  wait "$pid" 2>/dev/null || true
  printf '%s' "$conn_line"
}

split_route_test_json() {
  local raw_input input normalized_input service_meta label url host expected_route expected_copy service_key probe_message status status_text tone latency http_code detail
  local conn_line conn_host rule rule_payload matched_node matched_group chain_summary dns_mode remote_destination destination_ip started_at
  local actual_route actual_route_text fit fit_text trace_url exit_meta exit_ip exit_country exit_colo route_state route_current_node route_current_exit_ip route_current_exit_country route_current_exit_colo
  local recommendation next_step matched_rule_text route_summary
  local host_no_www

  label=''
  url=''
  host=''
  expected_route=''
  expected_copy=''
  service_key=''

  raw_input="${2:-}"
  input="$(sanitize_one_line "$raw_input")"
  normalized_input="$(printf '%s' "$input" | tr 'A-Z' 'a-z')"

  if [ -z "$input" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '请输入域名、完整网址，或者直接输入服务名，例如 ChatGPT、Netflix、YouTube。')"
    printf '}\n'
    return 0
  fi

  service_meta="$(split_route_service_meta "$input" 2>/dev/null || true)"
  if [ -n "$service_meta" ]; then
    label="$(printf '%s' "$service_meta" | cut -f1)"
    url="$(printf '%s' "$service_meta" | cut -f2)"
    expected_route="$(printf '%s' "$service_meta" | cut -f3)"
    expected_copy="$(printf '%s' "$service_meta" | cut -f4)"
    service_key="$(printf '%s' "$service_meta" | cut -f5)"
  else
    case "$normalized_input" in
      http://*|https://*) url="$input" ;;
      *) url="https://${input}" ;;
    esac
    host="$(extract_host_from_url "$url")"
    label="$host"
    service_meta="$(split_route_expected_from_host "$host" 2>/dev/null || true)"
    expected_route="$(printf '%s' "$service_meta" | cut -f1)"
    expected_copy="$(printf '%s' "$service_meta" | cut -f2)"
    service_key=''
  fi

  [ -n "$host" ] || host="$(extract_host_from_url "$url")"
  host_no_www="$(strip_www_prefix "$host")"
  [ -n "$label" ] || label="$host"
  [ -n "$expected_route" ] || expected_route='unknown'
  [ -n "$expected_copy" ] || expected_copy='先看实际走向，再决定是否需要调整。'

  conn_line="$(split_route_capture_connection "$url" "$host" 2>/dev/null || true)"
  probe_message="$(media_ai_site_probe "$url" "$label")"
  status="$(media_ai_status_code_from_text "$probe_message")"
  status_text="$(media_ai_status_label "$status")"
  tone="$(media_ai_status_tone "$status")"
  latency="$(media_ai_extract_latency_ms "$probe_message")"
  http_code="$(media_ai_extract_http_code "$probe_message")"
  detail="$(printf '%s' "$probe_message" | cut -d'|' -f5-)"

  if [ -z "$conn_line" ]; then
    conn_line="$(clash_connection_lookup_host "$host_no_www" 2>/dev/null || true)"
  fi

  conn_host="$(printf '%s' "$conn_line" | cut -f1)"
  rule="$(printf '%s' "$conn_line" | cut -f2)"
  rule_payload="$(printf '%s' "$conn_line" | cut -f3)"
  matched_node="$(printf '%s' "$conn_line" | cut -f4)"
  matched_group="$(printf '%s' "$conn_line" | cut -f5)"
  chain_summary="$(printf '%s' "$conn_line" | cut -f6)"
  dns_mode="$(printf '%s' "$conn_line" | cut -f7)"
  remote_destination="$(printf '%s' "$conn_line" | cut -f8)"
  destination_ip="$(printf '%s' "$conn_line" | cut -f9)"
  started_at="$(iso8601_to_human "$(printf '%s' "$conn_line" | cut -f10)")"

  actual_route='unknown'
  actual_route_text='这次没有抓到明确的路由链路。'
  if [ -n "$matched_node" ] || [ -n "$matched_group" ]; then
    if [ "$matched_node" = 'DIRECT' ] || [ "$matched_group" = 'DIRECT' ]; then
      actual_route='direct'
      actual_route_text='当前更像直连。'
    elif [ "$matched_node" = 'REJECT' ] || [ "$matched_group" = 'REJECT' ]; then
      actual_route='blocked'
      actual_route_text='当前规则把它拦截了。'
    else
      actual_route='proxy'
      actual_route_text='当前更像走代理。'
    fi
  fi

  fit='unknown'
  fit_text='还不能判断是否符合建议。'
  if [ "$expected_route" = 'direct' ] && [ "$actual_route" = 'direct' ]; then
    fit='yes'
    fit_text='符合建议：这个站点当前走直连。'
  elif [ "$expected_route" = 'proxy' ] && [ "$actual_route" = 'proxy' ]; then
    fit='yes'
    fit_text='符合建议：这个站点当前走代理。'
  elif [ "$expected_route" = 'direct' ] && [ "$actual_route" = 'proxy' ]; then
    fit='no'
    fit_text='不太符合建议：这个站点更像国内站点，却走了代理。'
  elif [ "$expected_route" = 'proxy' ] && [ "$actual_route" = 'direct' ]; then
    fit='no'
    fit_text='不太符合建议：这个站点更像国际或 AI 服务，却走了直连。'
  fi

  matched_rule_text='暂未抓到规则命中'
  if [ -n "$rule" ] || [ -n "$rule_payload" ]; then
    matched_rule_text="$(first_non_empty "$rule" '未知规则')"
    [ -n "$rule_payload" ] && matched_rule_text="${matched_rule_text} / ${rule_payload}"
  fi

  trace_url="$(split_route_trace_url "$service_key" "$host" 2>/dev/null || true)"
  exit_meta=''
  if [ -n "$trace_url" ]; then
    exit_meta="$(split_tunnel_probe_exit_identity "$trace_url" 2>/dev/null || true)"
  fi
  exit_ip="$(printf '%s\n' "$exit_meta" | awk -F '|' '{ print $1 }' | head -n 1)"
  exit_country="$(printf '%s\n' "$exit_meta" | awk -F '|' '{ print $2 }' | head -n 1)"
  exit_colo="$(printf '%s\n' "$exit_meta" | awk -F '|' '{ print $3 }' | head -n 1)"

  if [ -z "$exit_ip" ] && [ "$actual_route" = 'proxy' ]; then
    route_state="$(clash_current_route_state)"
    route_current_node="$(printf '%s' "$route_state" | cut -f3)"
    if [ -n "$matched_node" ] && [ "$matched_node" = "$route_current_node" ]; then
      route_current_exit_ip="$(cloudflare_trace_value ip)"
      route_current_exit_country="$(cloudflare_trace_value loc)"
      route_current_exit_colo="$(cloudflare_trace_value colo)"
      exit_ip="$route_current_exit_ip"
      exit_country="$route_current_exit_country"
      exit_colo="$route_current_exit_colo"
    fi
  fi

  route_summary='已经检测到网站可访问，但暂时没有抓到完整的规则链路。'
  recommendation='建议先看这次网站是否能打开，再决定要不要继续调整。'
  next_step='如果结果和你的预期不一致，去看网站走向检测页下方的批量结果，确认是否只有这一类网站异常。'

  if [ -n "$matched_node" ] || [ -n "$matched_group" ]; then
    route_summary="这个网站当前命中 ${matched_rule_text}，最终走 $(first_non_empty "$matched_group" "$matched_node" '未知分组')。"
  fi

  case "$fit" in
    yes)
      recommendation="$(first_non_empty "$expected_copy" '当前走向基本合理，可以继续使用。')"
      next_step='如果网站已经正常使用，通常不用改；如果仍有卡顿，再看节点延迟和专项检测结果。'
      ;;
    no)
      if [ "$expected_route" = 'direct' ]; then
        recommendation='建议检查国内站点分组或直连规则，避免国内网站被错误绕到代理。'
        next_step='优先检查国内直连规则、DNS 结果是否异常，以及是否有错误的自定义规则覆盖。'
      elif [ "$expected_route" = 'proxy' ]; then
        recommendation='建议检查 AI / 流媒体 / 国际站点分组，确认它是否应该走专门的代理分组。'
        next_step='优先查看对应服务分组当前选中了哪个节点，再决定是否切到更合适的地区线路。'
      fi
      ;;
    *)
      if [ -z "$conn_line" ]; then
        recommendation='这次没有抓到明确路由链路，可能是请求过快结束，也可能是当前请求没有被 OpenClash 接管。'
        next_step='可以换一个更典型的网址再测一次，或者先跑整页网站走向检测，再对比结果。'
      fi
      ;;
  esac

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "input": "%s",\n' "$(json_string "$input")"
  printf '  "label": "%s",\n' "$(json_string "$label")"
  printf '  "url": "%s",\n' "$(json_string "$url")"
  printf '  "host": "%s",\n' "$(json_string "$host")"
  printf '  "status": "%s",\n' "$(json_string "$status")"
  printf '  "status_text": "%s",\n' "$(json_string "$status_text")"
  printf '  "tone": "%s",\n' "$(json_string "$tone")"
  printf '  "latency_ms": "%s",\n' "$(json_string "$latency")"
  printf '  "http_code": "%s",\n' "$(json_string "$http_code")"
  printf '  "detail": "%s",\n' "$(json_string "$detail")"
  printf '  "expected_route": "%s",\n' "$(json_string "$expected_route")"
  printf '  "expected_copy": "%s",\n' "$(json_string "$expected_copy")"
  printf '  "actual_route": "%s",\n' "$(json_string "$actual_route")"
  printf '  "actual_route_text": "%s",\n' "$(json_string "$actual_route_text")"
  printf '  "fit": "%s",\n' "$(json_string "$fit")"
  printf '  "fit_text": "%s",\n' "$(json_string "$fit_text")"
  printf '  "matched_rule": "%s",\n' "$(json_string "$rule")"
  printf '  "matched_rule_payload": "%s",\n' "$(json_string "$rule_payload")"
  printf '  "matched_rule_text": "%s",\n' "$(json_string "$matched_rule_text")"
  printf '  "matched_group": "%s",\n' "$(json_string "$matched_group")"
  printf '  "matched_node": "%s",\n' "$(json_string "$matched_node")"
  printf '  "chain_summary": "%s",\n' "$(json_string "$chain_summary")"
  printf '  "dns_mode": "%s",\n' "$(json_string "$dns_mode")"
  printf '  "remote_destination": "%s",\n' "$(json_string "$remote_destination")"
  printf '  "destination_ip": "%s",\n' "$(json_string "$destination_ip")"
  printf '  "started_at": "%s",\n' "$(json_string "$started_at")"
  printf '  "exit_ip": "%s",\n' "$(json_string "$exit_ip")"
  printf '  "exit_country": "%s",\n' "$(json_string "$exit_country")"
  printf '  "exit_colo": "%s",\n' "$(json_string "$exit_colo")"
  printf '  "route_summary": "%s",\n' "$(json_string "$route_summary")"
  printf '  "recommendation": "%s",\n' "$(json_string "$recommendation")"
  printf '  "next_step": "%s"\n' "$(json_string "$next_step")"
  printf '}\n'
}

media_ai_test_running() {
  local pid
  if [ ! -f "$MEDIA_AI_RUN_PID_FILE" ]; then
    echo false
    return 0
  fi

  pid="$(cat "$MEDIA_AI_RUN_PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo true
    return 0
  fi

  rm -f "$MEDIA_AI_RUN_PID_FILE"
  echo false
}

media_ai_last_run_at() {
  if [ -r "$MEDIA_AI_RESULT_FILE" ]; then
    awk -F '\t' 'END { if (NR > 0) print $2 }' "$MEDIA_AI_RESULT_FILE"
  fi
}

media_ai_result_line() {
  local key="$1"
  [ -r "$MEDIA_AI_RESULT_FILE" ] || return 1
  awk -F '\t' -v key="$key" '$1 == key { print; exit }' "$MEDIA_AI_RESULT_FILE"
}

media_ai_cache_snapshot() {
  local stream_type="$1"
  [ -r "$OPENCLASH_UNLOCK_CACHE" ] || return 0
  command_exists lua || return 0

  lua - "$OPENCLASH_UNLOCK_CACHE" "$stream_type" <<'EOF'
local path = arg[1]
local stream_type = arg[2]
local ok, jsonc = pcall(require, "luci.jsonc")
if not ok then
  os.exit(0)
end

local file = io.open(path)
if not file then
  os.exit(0)
end

local raw = file:read("*a") or ""
file:close()
if raw == "" then
  os.exit(0)
end

local data = jsonc.parse(raw) or {}
local item = data[stream_type]
if type(item) ~= "table" then
  os.exit(0)
end

local node, region, old_region, count = "", "", "", 0
old_region = tostring(item.old_region or "")

for key, value in pairs(item) do
  if key ~= "old_region" and key ~= "old_regex" then
    count = count + 1
    if node == "" then
      node = tostring(key or "")
      region = tostring(value or "")
    end
  end
end

io.write(node .. "\t" .. region .. "\t" .. old_region .. "\t" .. count)
EOF
}

media_ai_extract_region() {
  printf '%s\n' "$1" | sed -n 's/.*area:【\([^】]*\)】.*/\1/p' | head -n 1
}

media_ai_extract_latency_ms() {
  printf '%s\n' "$1" | sed -n 's/^ACCESS_[A-Z_]*|\([0-9][0-9]*\)|.*$/\1/p' | head -n 1
}

media_ai_extract_http_code() {
  printf '%s\n' "$1" | sed -n 's/^ACCESS_[A-Z_]*|[0-9][0-9]*|\([0-9][0-9]*\)|.*$/\1/p' | head -n 1
}

split_tunnel_extract_exit_ip() {
  printf '%s\n' "$1" | awk -F '|' '{ if (NF >= 6) print $6 }' | head -n 1
}

split_tunnel_extract_exit_country() {
  printf '%s\n' "$1" | awk -F '|' '{ if (NF >= 7) print $7 }' | head -n 1
}

split_tunnel_extract_exit_colo() {
  printf '%s\n' "$1" | awk -F '|' '{ if (NF >= 8) print $8 }' | head -n 1
}

media_ai_status_code_from_text() {
  local text
  text="$1"

  if printf '%s' "$text" | grep -q '^ACCESS_OK|'; then
    echo reachable
  elif printf '%s' "$text" | grep -q '^ACCESS_RESTRICTED|'; then
    echo restricted
  elif printf '%s' "$text" | grep -q '^ACCESS_FAIL|'; then
    echo failed
  elif printf '%s' "$text" | grep -qi '^API reachable:'; then
    echo reachable
  elif printf '%s' "$text" | grep -qi '^API blocked:'; then
    echo restricted
  elif printf '%s' "$text" | grep -qi '^API failed:'; then
    echo failed
  elif printf '%s' "$text" | grep -qi 'only support homemade'; then
    echo homemade_only
  elif printf '%s' "$text" | grep -qi 'other full support node'; then
    echo other_region
  elif printf '%s' "$text" | grep -qi 'but not match the regex'; then
    echo other_region
  elif printf '%s' "$text" | grep -qi 'not match the old region'; then
    echo other_region
  elif printf '%s' "$text" | grep -qi 'unlock test faild'; then
    echo failed
  elif printf '%s' "$text" | grep -qi 'not support unlock'; then
    echo no_unlock
  elif printf '%s' "$text" | grep -qi 'no node available'; then
    echo no_unlock
  elif printf '%s' "$text" | grep -qi 'rolled back to the full support node'; then
    echo full_support
  elif printf '%s' "$text" | grep -qi 'full support'; then
    echo full_support
  else
    echo unknown
  fi
}

media_ai_status_label() {
  case "$1" in
    reachable|available) printf '%s' '连接正常' ;;
    restricted) printf '%s' '访问受限' ;;
    full_support) printf '%s' '完整解锁' ;;
    other_region) printf '%s' '其他地区可用' ;;
    homemade_only) printf '%s' '仅支持自制剧' ;;
    no_unlock) printf '%s' '未解锁' ;;
    blocked) printf '%s' '受限或被拒绝' ;;
    failed) printf '%s' '检测失败' ;;
    cache_only) printf '%s' '缓存显示可用' ;;
    disabled) printf '%s' '未启用' ;;
    unknown) printf '%s' '结果待确认' ;;
    *) printf '%s' '暂无结果' ;;
  esac
}

media_ai_status_tone() {
  case "$1" in
    reachable|available|full_support) printf '%s' 'good' ;;
    other_region|homemade_only|cache_only|unknown) printf '%s' 'warn' ;;
    restricted|no_unlock|blocked|failed) printf '%s' 'bad' ;;
    *) printf '%s' 'warn' ;;
  esac
}

media_ai_target_kind() {
  case "$1" in
    openai|claude|gemini|grok|perplexity|poe|cursor|codex) printf '%s' 'ai' ;;
    *) printf '%s' 'streaming' ;;
  esac
}

media_ai_recommended_region() {
  case "$1" in
    openai|codex|claude|cursor) printf '%s' '美国 / 新加坡 / 日本' ;;
    gemini|perplexity) printf '%s' '美国 / 日本 / 新加坡' ;;
    grok|poe) printf '%s' '美国或稳定国际地区' ;;
    netflix|disney|hbo_max|paramount_plus|discovery_plus|prime_video) printf '%s' '与服务内容地区一致的节点' ;;
    youtube|dazn|tvb_anywhere) printf '%s' '优先选择目标服务常用地区节点' ;;
    bilibili) printf '%s' '中国大陆 / 香港 / 台湾按用途选择' ;;
    *) printf '%s' '稳定国际地区' ;;
  esac
}

media_ai_dns_state_text() {
  local status detail http_code
  status="$1"
  detail="$2"
  http_code="$3"

  case "$status" in
    no_data|disabled) printf '%s' '未检测' ; return 0 ;;
  esac

  if printf '%s' "$detail" | grep -Eqi 'resolve|dns|name or service not known|temporary failure in name resolution|no such host'; then
    printf '%s' '异常'
  elif [ -n "$http_code" ] && [ "$http_code" != '000' ]; then
    printf '%s' '正常'
  elif [ "$status" = 'failed' ]; then
    printf '%s' '未确认'
  else
    printf '%s' '基本正常'
  fi
}

media_ai_tls_state_text() {
  local status detail http_code
  status="$1"
  detail="$2"
  http_code="$3"

  case "$status" in
    no_data|disabled) printf '%s' '未检测' ; return 0 ;;
  esac

  if printf '%s' "$detail" | grep -Eqi 'ssl|tls|certificate|handshake'; then
    printf '%s' '异常'
  elif [ -n "$http_code" ] && [ "$http_code" != '000' ]; then
    printf '%s' '正常'
  elif [ "$status" = 'failed' ]; then
    printf '%s' '未确认'
  else
    printf '%s' '基本正常'
  fi
}

media_ai_http_state_text() {
  local status http_code
  status="$1"
  http_code="$2"

  case "$status" in
    no_data|disabled) printf '%s' '未检测' ;;
    reachable|available|full_support)
      [ -n "$http_code" ] && [ "$http_code" != '000' ] && printf '正常（HTTP %s）' "$http_code" || printf '%s' '正常'
      ;;
    restricted|blocked|other_region|homemade_only|no_unlock)
      [ -n "$http_code" ] && [ "$http_code" != '000' ] && printf '有响应（HTTP %s）' "$http_code" || printf '%s' '有响应但受限'
      ;;
    failed) printf '%s' '未拿到有效响应' ;;
    *) printf '%s' '待确认' ;;
  esac
}

media_ai_risk_hint_text() {
  local key status http_code
  key="$1"
  status="$2"
  http_code="$3"

  if { [ "$key" = 'openai' ] || [ "$key" = 'codex' ]; } && [ "$http_code" = '401' ]; then
    printf '%s' '未见明显风控，更像缺少认证'
  elif [ "$key" = 'gemini' ] && [ "$http_code" = '400' ]; then
    printf '%s' '未见明显风控，更像测试 Key 无效'
  elif [ "$status" = 'restricted' ] || [ "$status" = 'blocked' ]; then
    printf '%s' '疑似地区限制或服务风控'
  elif [ "$status" = 'failed' ]; then
    printf '%s' '未确认，先排查线路和解析'
  elif [ "$status" = 'other_region' ] || [ "$status" = 'homemade_only' ] || [ "$status" = 'no_unlock' ]; then
    printf '%s' '更像地区不匹配'
  else
    printf '%s' '未见明显限制'
  fi
}

media_ai_long_term_fit_text() {
  local kind status latency
  kind="$1"
  status="$2"
  latency="${3:-0}"

  case "$status" in
    full_support)
      printf '%s' '适合长期使用'
      ;;
    reachable|available)
      if [ -n "$latency" ] && [ "$latency" -ge 1500 ] 2>/dev/null; then
        printf '%s' '可短期使用，建议继续观察'
      else
        [ "$kind" = 'ai' ] && printf '%s' '适合继续作为 AI 候选线路' || printf '%s' '可作为候选主力'
      fi
      ;;
    other_region|homemade_only)
      printf '%s' '可临时使用，不建议长期固定'
      ;;
    restricted|no_unlock|blocked|failed)
      printf '%s' '不建议长期使用'
      ;;
    *)
      printf '%s' '等待进一步检测'
      ;;
  esac
}

media_ai_native_text() {
  local kind status
  kind="$1"
  status="$2"

  [ "$kind" = 'streaming' ] || {
    printf '%s' '不适用'
    return 0
  }

  case "$status" in
    full_support) printf '%s' '更像完整解锁' ;;
    reachable|available) printf '%s' '可以访问，但未识别是否原生' ;;
    other_region) printf '%s' '可访问，但地区不匹配' ;;
    homemade_only) printf '%s' '仅部分内容可用' ;;
    restricted|no_unlock|blocked|failed) printf '%s' '当前不可用' ;;
    *) printf '%s' '待检测' ;;
  esac
}

media_ai_diagnosis_text() {
  local key kind status http_code
  key="$1"
  kind="$2"
  status="$3"
  http_code="$4"

  if [ "$kind" = 'ai' ]; then
    if { [ "$key" = 'openai' ] || [ "$key" = 'codex' ]; } && [ "$http_code" = '401' ]; then
      printf '%s' '线路已经连通，当前更像 API 认证没补齐。'
    elif [ "$key" = 'gemini' ] && [ "$http_code" = '400' ]; then
      printf '%s' '线路已经连通，当前更像测试 Key 无效。'
    elif [ "$status" = 'reachable' ] || [ "$status" = 'available' ] || [ "$status" = 'full_support' ]; then
      printf '%s' '当前连通性正常，适合继续放在 AI 或国际稳定分组。'
    elif [ "$status" = 'restricted' ] || [ "$status" = 'blocked' ]; then
      printf '%s' '当前更像地区限制、服务风控或分组不匹配。'
    elif [ "$status" = 'failed' ]; then
      printf '%s' '当前更像线路质量、DNS 或 TLS 过程不稳定。'
    else
      printf '%s' '结果还不够稳定，先别急着判断节点失效。'
    fi
    return 0
  fi

  case "$status" in
    full_support) printf '%s' '当前更像完整解锁，适合继续观察延迟和稳定性。' ;;
    reachable|available) printf '%s' '当前可以访问，但还不能直接判断是否长期稳定。' ;;
    other_region) printf '%s' '当前能看，但地区不理想，内容库可能不对。' ;;
    homemade_only) printf '%s' '当前只能看部分内容，更像节点地区不合适。' ;;
    restricted|no_unlock|blocked) printf '%s' '当前更像地区限制、分流不对或节点类型不匹配。' ;;
    failed) printf '%s' '当前更像线路质量、TLS 或解析异常。' ;;
    *) printf '%s' '还没有拿到稳定结果。' ;;
  esac
}

media_ai_next_step_text() {
  local key kind status http_code
  key="$1"
  kind="$2"
  status="$3"
  http_code="$4"

  if [ "$kind" = 'ai' ]; then
    if { [ "$key" = 'openai' ] || [ "$key" = 'codex' ]; } && [ "$http_code" = '401' ]; then
      printf '%s' '优先检查 API Key、账号和客户端配置，不要先急着换节点。'
    elif [ "$key" = 'gemini' ] && [ "$http_code" = '400' ]; then
      printf '%s' '先确认 Key 是否有效，再决定要不要换节点。'
    elif [ "$status" = 'restricted' ] || [ "$status" = 'blocked' ]; then
      printf '先切到 AI 分组，再尝试 %s。' "$(media_ai_recommended_region "$key")"
    elif [ "$status" = 'failed' ]; then
      printf '%s' '先刷新 DNS，再换到延迟更低的国际节点后重试。'
    else
      printf '保持 AI 或国际稳定分组，优先使用 %s。' "$(media_ai_recommended_region "$key")"
    fi
    return 0
  fi

  case "$status" in
    full_support) printf '%s' '可以继续观察延迟和连通稳定性，再决定是否固定为主力流媒体节点。' ;;
    reachable|available) printf '%s' '建议补看地区是否匹配，再决定是否长期使用。' ;;
    other_region|homemade_only) printf '优先换到 %s。' "$(media_ai_recommended_region "$key")" ;;
    restricted|no_unlock|blocked) printf '%s' '先切到流媒体分组，再换对应地区节点后重试。' ;;
    failed) printf '%s' '先刷新 DNS，确认节点可连后再重试。' ;;
    *) printf '%s' '先跑一次真实检测，再看是否需要换地区。' ;;
  esac
}

media_ai_site_probe() {
  local url name output code time_total latency_ms curl_status note

  url="$1"
  name="$2"
  output="$(curl -k -L -A 'Mozilla/5.0' -o /dev/null -sS -m 20 -w '__HTTP_CODE__:%{http_code}\n__TIME_TOTAL__:%{time_total}\n' "$url" 2>&1 || true)"
  curl_status=$?
  code="$(printf '%s\n' "$output" | sed -n 's/^__HTTP_CODE__://p' | tail -n 1)"
  time_total="$(printf '%s\n' "$output" | sed -n 's/^__TIME_TOTAL__://p' | tail -n 1)"
  [ -n "$time_total" ] || time_total=0.001
  latency_ms="$(milliseconds_from_seconds "$time_total")"

  if [ "$curl_status" -eq 0 ] && [ -n "$code" ] && [ "$code" != '000' ] && [ "$code" -lt 400 ] 2>/dev/null; then
    note="连接正常"
    printf 'ACCESS_OK|%s|%s|%s|%s' "$latency_ms" "$code" "$url" "$note"
  elif [ "$curl_status" -eq 0 ] && [ -n "$code" ] && [ "$code" != '000' ]; then
    note="访问受限，HTTP ${code}"
    printf 'ACCESS_RESTRICTED|%s|%s|%s|%s' "$latency_ms" "$code" "$url" "$note"
  else
    note="$(printf '%s\n' "$output" | tail -n 1)"
    note="$(sanitize_one_line "$note")"
    [ -n "$note" ] || note="${name} 检测失败"
    printf 'ACCESS_FAIL|%s|%s|%s|%s' "$latency_ms" "${code:-000}" "$url" "$note"
  fi
}

media_ai_api_probe_openai() {
  local result code body message time_total latency_ms
  result="$(curl -k -sS -m 20 https://api.openai.com/v1/models -w '\n__HTTP_CODE__:%{http_code}\n__TIME_TOTAL__:%{time_total}\n' 2>&1 || true)"
  code="$(printf '%s\n' "$result" | sed -n 's/^__HTTP_CODE__://p' | tail -n 1)"
  time_total="$(printf '%s\n' "$result" | sed -n 's/^__TIME_TOTAL__://p' | tail -n 1)"
  [ -n "$time_total" ] || time_total=0.001
  latency_ms="$(milliseconds_from_seconds "$time_total")"
  body="$(printf '%s\n' "$result" | sed '/^__HTTP_CODE__:/d')"
  body="$(printf '%s\n' "$body" | sed '/^__TIME_TOTAL__:/d')"
  body="$(sanitize_one_line "$body")"

  if printf '%s' "$body" | grep -qi 'Missing bearer authentication'; then
    message="ACCESS_OK|${latency_ms}|${code:-401}|https://api.openai.com/v1/models|连接正常，需要认证"
  elif printf '%s' "$body" | grep -qi 'invalid_api_key'; then
    message="ACCESS_OK|${latency_ms}|${code:-401}|https://api.openai.com/v1/models|连接正常，API Key 无效"
  elif printf '%s' "$body" | grep -qi 'unsupported_country'; then
    message="ACCESS_RESTRICTED|${latency_ms}|${code:-403}|https://api.openai.com/v1/models|访问受限，unsupported_country"
  elif [ "${code:-0}" = '401' ]; then
    message="ACCESS_OK|${latency_ms}|401|https://api.openai.com/v1/models|连接正常，需要认证"
  elif [ "${code:-0}" = '403' ]; then
    message="ACCESS_RESTRICTED|${latency_ms}|403|https://api.openai.com/v1/models|访问受限 ${body:-Request forbidden}"
  else
    message="ACCESS_FAIL|${latency_ms}|${code:-0}|https://api.openai.com/v1/models|${body:-Unknown response}"
  fi

  printf '%s' "$(sanitize_one_line "$message")"
}

media_ai_api_probe_claude() {
  local payload result code body message time_total latency_ms
  payload='{"model":"claude-3-5-haiku-latest","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
  result="$(printf '%s' "$payload" | curl -k -sS -m 20 -X POST https://api.anthropic.com/v1/messages -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' -H 'x-api-key: test-key' --data @- -w '\n__HTTP_CODE__:%{http_code}\n__TIME_TOTAL__:%{time_total}\n' 2>&1 || true)"
  code="$(printf '%s\n' "$result" | sed -n 's/^__HTTP_CODE__://p' | tail -n 1)"
  time_total="$(printf '%s\n' "$result" | sed -n 's/^__TIME_TOTAL__://p' | tail -n 1)"
  [ -n "$time_total" ] || time_total=0.001
  latency_ms="$(milliseconds_from_seconds "$time_total")"
  body="$(printf '%s\n' "$result" | sed '/^__HTTP_CODE__:/d')"
  body="$(printf '%s\n' "$body" | sed '/^__TIME_TOTAL__:/d')"
  body="$(sanitize_one_line "$body")"

  if printf '%s' "$body" | grep -qi 'invalid x-api-key'; then
    message="ACCESS_OK|${latency_ms}|${code:-401}|https://api.anthropic.com/v1/messages|连接正常，API Key 无效"
  elif printf '%s' "$body" | grep -qi 'authentication'; then
    message="ACCESS_OK|${latency_ms}|${code:-401}|https://api.anthropic.com/v1/messages|连接正常，需要认证"
  elif printf '%s' "$body" | grep -qi 'Request not allowed'; then
    message="ACCESS_RESTRICTED|${latency_ms}|${code:-403}|https://api.anthropic.com/v1/messages|访问受限 Request not allowed"
  elif [ "${code:-0}" = '401' ]; then
    message="ACCESS_OK|${latency_ms}|401|https://api.anthropic.com/v1/messages|连接正常，需要认证"
  elif [ "${code:-0}" = '403' ]; then
    message="ACCESS_RESTRICTED|${latency_ms}|403|https://api.anthropic.com/v1/messages|访问受限 ${body:-Request forbidden}"
  else
    message="ACCESS_FAIL|${latency_ms}|${code:-0}|https://api.anthropic.com/v1/messages|${body:-Unknown response}"
  fi

  printf '%s' "$(sanitize_one_line "$message")"
}

media_ai_api_probe_gemini() {
  local result code body message time_total latency_ms
  result="$(curl -k -sS -m 20 'https://generativelanguage.googleapis.com/v1beta/models?key=test-key' -w '\n__HTTP_CODE__:%{http_code}\n__TIME_TOTAL__:%{time_total}\n' 2>&1 || true)"
  code="$(printf '%s\n' "$result" | sed -n 's/^__HTTP_CODE__://p' | tail -n 1)"
  time_total="$(printf '%s\n' "$result" | sed -n 's/^__TIME_TOTAL__://p' | tail -n 1)"
  [ -n "$time_total" ] || time_total=0.001
  latency_ms="$(milliseconds_from_seconds "$time_total")"
  body="$(printf '%s\n' "$result" | sed '/^__HTTP_CODE__:/d')"
  body="$(printf '%s\n' "$body" | sed '/^__TIME_TOTAL__:/d')"
  body="$(sanitize_one_line "$body")"

  if printf '%s' "$body" | grep -qi 'API key not valid'; then
    message="ACCESS_OK|${latency_ms}|${code:-400}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|连接正常，API Key 无效"
  elif printf '%s' "$body" | grep -qi 'API_KEY_INVALID'; then
    message="ACCESS_OK|${latency_ms}|${code:-400}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|连接正常，API Key 无效"
  elif printf '%s' "$body" | grep -qi 'location is not supported'; then
    message="ACCESS_RESTRICTED|${latency_ms}|${code:-403}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|访问受限，地区不支持"
  elif printf '%s' "$body" | grep -qi 'unsupported country'; then
    message="ACCESS_RESTRICTED|${latency_ms}|${code:-403}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|访问受限，地区不支持"
  elif [ "${code:-0}" = '400' ] || [ "${code:-0}" = '401' ]; then
    message="ACCESS_OK|${latency_ms}|${code:-400}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|连接正常"
  elif [ "${code:-0}" = '403' ]; then
    message="ACCESS_RESTRICTED|${latency_ms}|403|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|访问受限 ${body:-Request forbidden}"
  else
    message="ACCESS_FAIL|${latency_ms}|${code:-0}|https://generativelanguage.googleapis.com/v1beta/models?key=test-key|${body:-Unknown response}"
  fi

  printf '%s' "$(sanitize_one_line "$message")"
}

run_media_ai_target_probe() {
  local key stream_type message backend
  key="$1"
  backend="$(media_ai_target_probe_backend "$key")"

  if [ "$backend" = 'official_api' ]; then
    case "$key" in
      openai|codex) media_ai_api_probe_openai ;;
      claude) media_ai_api_probe_claude ;;
      gemini) media_ai_api_probe_gemini ;;
      *) printf '%s' 'API failed: unsupported target' ;;
    esac
    return 0
  fi

  stream_type="$(media_ai_target_type "$key")"
  message="$(media_ai_site_probe "$(media_ai_target_probe_url "$key")" "$stream_type")"
  printf '%s' "$message"
}

split_tunnel_probe_exit_identity() {
  local url trace ip loc colo
  url="$1"
  [ -n "$url" ] || return 0

  trace="$(curl -k -sS -m 12 "$url" 2>/dev/null || true)"
  ip="$(printf '%s\n' "$trace" | sed -n 's/^ip=\(.*\)$/\1/p' | head -n 1)"
  loc="$(printf '%s\n' "$trace" | sed -n 's/^loc=\(.*\)$/\1/p' | head -n 1)"
  colo="$(printf '%s\n' "$trace" | sed -n 's/^colo=\(.*\)$/\1/p' | head -n 1)"

  if [ -n "$ip" ]; then
    printf '%s|%s|%s' "$ip" "$loc" "$colo"
  fi
}

media_ai_source_text() {
  case "$1" in
    assistant_test) printf '%s' '助手实测' ;;
    openclash_cache) printf '%s' 'OpenClash 缓存' ;;
    *) printf '%s' '暂无来源' ;;
  esac
}

set_media_ai_target_state() {
  local key stream_type enabled line tested_at detail status source backend latency_ms http_code kind

  key="$1"
  stream_type="$(media_ai_target_type "$key")"
  enabled="$(media_ai_target_enabled "$key")"
  backend="$(media_ai_target_probe_backend "$key")"
  line="$(media_ai_result_line "$key" 2>/dev/null || true)"
  tested_at=''
  detail=''

  if [ -n "$line" ]; then
    tested_at="$(printf '%s' "$line" | cut -f2)"
    detail="$(printf '%s' "$line" | cut -f3-)"
  fi

  source='none'
  status='no_data'
  latency_ms=''
  http_code=''
  if [ -n "$detail" ]; then
    source='assistant_test'
    status="$(media_ai_status_code_from_text "$detail")"
  elif [ "$enabled" = false ]; then
    status='disabled'
    detail='当前未勾选该检测目标。'
  else
    detail='尚未执行真实检测。'
  fi

  latency_ms="$(media_ai_extract_latency_ms "$detail")"
  http_code="$(media_ai_extract_http_code "$detail")"
  kind="$(media_ai_target_kind "$key")"

  MEDIA_AI_TARGET_ENABLED="$enabled"
  MEDIA_AI_TARGET_KIND="$kind"
  MEDIA_AI_TARGET_STATUS="$status"
  MEDIA_AI_TARGET_STATUS_TEXT="$(media_ai_status_label "$status")"
  MEDIA_AI_TARGET_TONE="$(media_ai_status_tone "$status")"
  MEDIA_AI_TARGET_REGION=''
  MEDIA_AI_TARGET_NODE=''
  MEDIA_AI_TARGET_TESTED_AT="$tested_at"
  MEDIA_AI_TARGET_DETAIL="$detail"
  MEDIA_AI_TARGET_SOURCE="$source"
  MEDIA_AI_TARGET_SOURCE_TEXT="$(media_ai_source_text "$source")"
  MEDIA_AI_TARGET_LATENCY_MS="$latency_ms"
  MEDIA_AI_TARGET_HTTP_CODE="$http_code"
  MEDIA_AI_TARGET_DNS_STATE="$(media_ai_dns_state_text "$status" "$detail" "$http_code")"
  MEDIA_AI_TARGET_TLS_STATE="$(media_ai_tls_state_text "$status" "$detail" "$http_code")"
  MEDIA_AI_TARGET_HTTP_STATE="$(media_ai_http_state_text "$status" "$http_code")"
  MEDIA_AI_TARGET_RISK_HINT="$(media_ai_risk_hint_text "$key" "$status" "$http_code")"
  MEDIA_AI_TARGET_RECOMMENDED_REGION="$(media_ai_recommended_region "$key")"
  MEDIA_AI_TARGET_LONG_TERM_FIT="$(media_ai_long_term_fit_text "$kind" "$status" "$latency_ms")"
  MEDIA_AI_TARGET_NATIVE_TEXT="$(media_ai_native_text "$kind" "$status")"
  MEDIA_AI_TARGET_DIAGNOSIS="$(media_ai_diagnosis_text "$key" "$kind" "$status" "$http_code")"
  MEDIA_AI_TARGET_NEXT_STEP="$(media_ai_next_step_text "$key" "$kind" "$status" "$http_code")"
}

template_lookup_fallback() {
  case "$1" in
    ACL4SSR_Online_Mini_MultiMode.ini)
      printf '%s|%s\n' 'ACL4SSR 规则 Online Mini MultiMode' 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini_MultiMode.ini'
    ;;
    ACL4SSR_Online_Full_MultiMode.ini)
      printf '%s|%s\n' 'ACL4SSR 规则 Online Full MultiMode' 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Full_MultiMode.ini'
    ;;
    ACL4SSR_Online_Mini.ini)
      printf '%s|%s\n' 'ACL4SSR 规则 Online Mini' 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini.ini'
    ;;
    Custom_Clash.ini)
      printf '%s|%s\n' 'Aethersailor 规则 标准版 Custom_Clash' 'https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash.ini'
    ;;
    Custom_Clash_Lite.ini)
      printf '%s|%s\n' 'Aethersailor 规则 轻量版 Custom_Clash_Lite' 'https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash_Lite.ini'
    ;;
    Custom_Clash_Full.ini)
      printf '%s|%s\n' 'Aethersailor 规则 重度分流版 Custom_Clash_Full' 'https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash_Full.ini'
    ;;
    *) return 1 ;;
  esac
}

emit_default_templates_json() {
  printf '    {"name":"ACL4SSR 规则 Online Mini MultiMode","id":"ACL4SSR_Online_Mini_MultiMode.ini","url":"https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini_MultiMode.ini"},\n'
  printf '    {"name":"ACL4SSR 规则 Online Full MultiMode","id":"ACL4SSR_Online_Full_MultiMode.ini","url":"https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Full_MultiMode.ini"},\n'
  printf '    {"name":"ACL4SSR 规则 Online Mini","id":"ACL4SSR_Online_Mini.ini","url":"https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini.ini"},\n'
  printf '    {"name":"Aethersailor 规则 标准版 Custom_Clash","id":"Custom_Clash.ini","url":"https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash.ini"},\n'
  printf '    {"name":"Aethersailor 规则 轻量版 Custom_Clash_Lite","id":"Custom_Clash_Lite.ini","url":"https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash_Lite.ini"},\n'
  printf '    {"name":"Aethersailor 规则 重度分流版 Custom_Clash_Full","id":"Custom_Clash_Full.ini","url":"https://raw.githubusercontent.com/Aethersailor/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash_Full.ini"}\n'
}

urlencode() {
  local string="$1"
  local length index char encoded=""
  length=${#string}
  index=1
  while [ "$index" -le "$length" ]; do
    char=$(printf '%s' "$string" | cut -c "$index")
    case "$char" in
      [a-zA-Z0-9.~_-]) encoded="$encoded$char" ;;
      ' ') encoded="$encoded%20" ;;
      *) encoded="$encoded$(printf '%%%02X' "'$char")" ;;
    esac
    index=$((index + 1))
  done
  printf '%s' "$encoded"
}

subconvert_backend_origin() {
  local backend="$1"
  backend="${backend%%\#*}"
  backend="${backend%%\?*}"
  backend="${backend%/}"
  case "$backend" in
    */sub) backend="${backend%/sub}" ;;
  esac
  [ -n "$backend" ] || backend='http://127.0.0.1:25500'
  printf '%s' "$backend"
}

subconvert_backend_api() {
  local backend_origin
  backend_origin="$(subconvert_backend_origin "$1")"
  printf '%s/sub' "$backend_origin"
}

subconvert_frontend_path() {
  printf '%s' '/luci-static/openclash-assistant/sub-web-modify/index.html'
}

http_fetch_quick() {
  local url="$1"
  if command_exists curl; then
    curl -k -sS -m 4 "$url" 2>/dev/null || true
  elif command_exists wget; then
    wget -T 4 -qO- "$url" 2>/dev/null || true
  elif command_exists uclient-fetch; then
    uclient-fetch -T 4 -O - "$url" 2>/dev/null || true
  else
    true
  fi
}

subconvert_source_format_valid() {
  case "${1:-}" in
    http://*|https://*) echo true ;;
    *) echo false ;;
  esac
}

subconvert_probe_source() {
  local url="$1" body sample trimmed
  body=''
  if command_exists curl; then
    body="$(curl -k -L -sS -m 6 "$url" 2>/dev/null | head -c 1024 || true)"
  elif command_exists wget; then
    body="$(wget -T 6 -qO- "$url" 2>/dev/null | head -c 1024 || true)"
  elif command_exists uclient-fetch; then
    body="$(uclient-fetch -T 6 -O - "$url" 2>/dev/null | head -c 1024 || true)"
  fi

  sample="$(printf '%s' "$body" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c1-180)"
  trimmed="$(printf '%s' "$sample" | tr '[:upper:]' '[:lower:]')"

  if [ -z "$sample" ]; then
    printf 'unknown\t没有成功拿到订阅内容，可能是源站暂时不可达、需要认证，或路由器缺少下载工具。\t-\n'
  elif printf '%s' "$trimmed" | grep -Eq '<!doctype html|<html|<head|<title'; then
    printf 'html\t返回内容更像网页或登录页，不像订阅本体，建议检查订阅链接是否填对。\t%s\n' "$(json_string "$sample")"
  elif printf '%s' "$sample" | grep -Eq 'proxies:|proxy-providers:|mixed-port:|redir-port:|port:'; then
    printf 'yaml\t返回内容更像 Clash / Mihomo 配置，可以继续导入或先转换。\t%s\n' "$(json_string "$sample")"
  elif printf '%s' "$sample" | grep -Eq 'vmess://|vless://|ss://|trojan://|hysteria://|tuic://'; then
    printf 'nodes\t返回内容里已经带节点协议，说明订阅本体大概率有效。\t%s\n' "$(json_string "$sample")"
  elif printf '%s' "$sample" | grep -Eq '^[A-Za-z0-9+/=[:space:]]+$' && [ "${#sample}" -ge 48 ]; then
    printf 'base64\t返回内容更像经过 Base64 编码的节点订阅，大概率是正常订阅。\t%s\n' "$(json_string "$sample")"
  else
    printf 'unknown\t已经拿到内容，但格式不像常见订阅，建议先在内置转换页里试一次，确认是否能正常生成结果。\t%s\n' "$(json_string "$sample")"
  fi
}

subconvert_history_json() {
  local first=1 sid name address enabled sub_convert convert_address template updated_at
  for sid in $(uci -q show openclash 2>/dev/null | sed -n "s/^openclash\.\([^=]*\)=config_subscribe$/\1/p"); do
    name="$(uci -q get openclash."$sid".name 2>/dev/null || echo '未命名订阅')"
    address="$(uci -q get openclash."$sid".address 2>/dev/null || echo '')"
    enabled="$(uci -q get openclash."$sid".enabled 2>/dev/null || echo 0)"
    sub_convert="$(uci -q get openclash."$sid".sub_convert 2>/dev/null || echo 0)"
    convert_address="$(uci -q get openclash."$sid".convert_address 2>/dev/null || echo '')"
    template="$(uci -q get openclash."$sid".template 2>/dev/null || echo '')"
    updated_at=''
    if [ -n "$template" ]; then
      updated_at="$(file_mtime_human "/etc/config/openclash")"
    fi
    [ "$first" -eq 0 ] && printf ',\n'
    first=0
    printf '    {"sid":"%s","name":"%s","address":"%s","enabled":"%s","sub_convert":"%s","convert_address":"%s","template":"%s","updated_at":"%s"}' \
      "$(json_string "$sid")" \
      "$(json_string "$name")" \
      "$(json_string "$address")" \
      "$(json_string "$enabled")" \
      "$(json_string "$sub_convert")" \
      "$(json_string "$convert_address")" \
      "$(json_string "$template")" \
      "$(json_string "$updated_at")"
  done
}

template_lookup() {
  local target="$1"
  if [ -r "$SUB_INI_LIST" ]; then
    while IFS=, read -r name id url; do
      [ -n "$id" ] || continue
      if [ "$id" = "$target" ]; then
        printf '%s|%s\n' "$name" "$url"
        return 0
      fi
    done < "$SUB_INI_LIST"
  fi
  template_lookup_fallback "$target"
}

recommended_template() {
  local role has_public uses_tailscale gaming low_maintenance
  role="$(str_uci routing_role bypass_router)"
  has_public="$(bool_uci has_public_services 0)"
  uses_tailscale="$(bool_uci uses_tailscale 0)"
  gaming="$(bool_uci gaming_devices 0)"
  low_maintenance="$(bool_uci low_maintenance 1)"

  if [ "$low_maintenance" = true ]; then
    printf '%s\n' 'Custom_Clash_Lite.ini'
  elif [ "$role" = 'bypass_router' ] && { [ "$has_public" = true ] || [ "$uses_tailscale" = true ] || [ "$gaming" = true ]; }; then
    printf '%s\n' 'ACL4SSR_Online_Mini_MultiMode.ini'
  else
    printf '%s\n' 'ACL4SSR_Online_Full_MultiMode.ini'
  fi
}

status_json() {
  local installed enabled running config_count openclash_dir dnsmasq_full ipset_ok nft_ok tun_ok firewall4_ok openclash_cfg role mode stream_auto_select stream_auto_select_logic stream_auto_select_interval dnsmasq_running smartdns_available smartdns_running dns_diag_line_value dns_chain dns_diag_code dns_diag_level dns_diag_summary dns_diag_action
  local controller_ready route_state current_group current_group_type current_node current_node_type current_node_delay current_node_alive last_probe_at runtime_state current_mode current_log_level current_ipv6 current_allow_lan exit_ip exit_country exit_colo cpu_pct mem_pct clash_usage recent_errors config_path config_name config_updated_at clash_mem_mb

  if [ -x /etc/init.d/openclash ] || [ -f /etc/config/openclash ]; then
    installed=true
  else
    installed=false
  fi

  enabled="$(service_enabled)"
  running="$(service_running)"
  config_count="$(count_configs)"

  [ -d /etc/openclash ] && openclash_dir=true || openclash_dir=false
  [ -f /etc/config/openclash ] && openclash_cfg=true || openclash_cfg=false
  package_installed dnsmasq-full && dnsmasq_full=true || dnsmasq_full=false

  if package_installed ipset || command_exists ipset; then ipset_ok=true; else ipset_ok=false; fi
  if command_exists nft; then nft_ok=true; else nft_ok=false; fi
  if package_installed kmod-tun || [ -c /dev/net/tun ]; then tun_ok=true; else tun_ok=false; fi
  if [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then firewall4_ok=true; else firewall4_ok=false; fi

  role="$(str_uci routing_role bypass_router)"
  mode="$(str_uci preferred_mode auto)"
  stream_auto_select="$(uci -q get openclash.config.stream_auto_select 2>/dev/null || echo 0)"
  stream_auto_select_logic="$(uci -q get openclash.config.stream_auto_select_logic 2>/dev/null || echo urltest)"
  stream_auto_select_interval="$(uci -q get openclash.config.stream_auto_select_interval 2>/dev/null || echo 30)"
  dnsmasq_running="$(service_running_named dnsmasq)"
  [ -x /etc/init.d/smartdns ] && smartdns_available=true || smartdns_available=false
  smartdns_running="$(service_running_named smartdns)"
  dns_diag_line_value="$(dns_diag_line "$running" "$dnsmasq_running" "$smartdns_available" "$smartdns_running" "$dnsmasq_full")"
  dns_chain="$(printf '%s' "$dns_diag_line_value" | cut -f1)"
  dns_diag_code="$(printf '%s' "$dns_diag_line_value" | cut -f2)"
  dns_diag_level="$(printf '%s' "$dns_diag_line_value" | cut -f3)"
  dns_diag_summary="$(printf '%s' "$dns_diag_line_value" | cut -f4)"
  dns_diag_action="$(printf '%s' "$dns_diag_line_value" | cut -f5)"
  controller_ready="$(clash_controller_ready)"
  route_state="$(clash_current_route_state)"
  current_group="$(printf '%s' "$route_state" | cut -f1)"
  current_group_type="$(printf '%s' "$route_state" | cut -f2)"
  current_node="$(printf '%s' "$route_state" | cut -f3)"
  current_node_type="$(printf '%s' "$route_state" | cut -f4)"
  current_node_delay="$(printf '%s' "$route_state" | cut -f5)"
  current_node_alive="$(printf '%s' "$route_state" | cut -f6)"
  last_probe_at="$(printf '%s' "$route_state" | cut -f7)"
  runtime_state="$(clash_config_runtime_state)"
  current_mode="$(first_non_empty "$(printf '%s' "$runtime_state" | cut -f1)" "$(uci -q get openclash.config.proxy_mode 2>/dev/null || true)")"
  current_log_level="$(first_non_empty "$(printf '%s' "$runtime_state" | cut -f2)" "$(uci -q get openclash.config.log_level 2>/dev/null || true)")"
  current_ipv6="$(first_non_empty "$(printf '%s' "$runtime_state" | cut -f3)" "$(bool_uci ipv6_enable 0)")"
  current_allow_lan="$(printf '%s' "$runtime_state" | cut -f4)"
  exit_ip="$(cloudflare_trace_value ip)"
  exit_country="$(cloudflare_trace_value loc)"
  exit_colo="$(cloudflare_trace_value colo)"
  cpu_pct="$(cpu_usage_percent)"
  mem_pct="$(memory_usage_percent)"
  clash_usage="$(clash_process_usage)"
  recent_errors="$(recent_error_count)"
  config_path="$(uci -q get openclash.config.config_path 2>/dev/null || echo '')"
  config_name="$(basename "${config_path:-}" 2>/dev/null || true)"
  config_updated_at="$(file_mtime_human "$config_path")"
  clash_mem_mb="$(clash_connection_memory_mb)"

  printf '{\n'
  printf '  "installed": %s,\n' "$installed"
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "running": %s,\n' "$running"
  printf '  "openclash_dir": %s,\n' "$openclash_dir"
  printf '  "openclash_config": %s,\n' "$openclash_cfg"
  printf '  "config_count": %s,\n' "$config_count"
  printf '  "dnsmasq_full": %s,\n' "$dnsmasq_full"
  printf '  "ipset": %s,\n' "$ipset_ok"
  printf '  "nft": %s,\n' "$nft_ok"
  printf '  "tun": %s,\n' "$tun_ok"
  printf '  "firewall4": %s,\n' "$firewall4_ok"
  printf '  "routing_role": "%s",\n' "$(json_string "$role")"
  printf '  "preferred_mode": "%s",\n' "$(json_string "$mode")"
  printf '  "stream_auto_select": "%s",\n' "$(json_string "$stream_auto_select")"
  printf '  "stream_auto_select_logic": "%s",\n' "$(json_string "$stream_auto_select_logic")"
  printf '  "stream_auto_select_interval": "%s",\n' "$(json_string "$stream_auto_select_interval")"
  printf '  "dnsmasq_running": %s,\n' "$dnsmasq_running"
  printf '  "smartdns_available": %s,\n' "$smartdns_available"
  printf '  "smartdns_running": %s,\n' "$smartdns_running"
  printf '  "controller_ready": %s,\n' "$controller_ready"
  printf '  "current_mode": "%s",\n' "$(json_string "$current_mode")"
  printf '  "current_log_level": "%s",\n' "$(json_string "$current_log_level")"
  printf '  "current_ipv6": "%s",\n' "$(json_string "$current_ipv6")"
  printf '  "current_allow_lan": "%s",\n' "$(json_string "$current_allow_lan")"
  printf '  "current_group": "%s",\n' "$(json_string "$current_group")"
  printf '  "current_group_type": "%s",\n' "$(json_string "$current_group_type")"
  printf '  "current_node": "%s",\n' "$(json_string "$current_node")"
  printf '  "current_node_type": "%s",\n' "$(json_string "$current_node_type")"
  printf '  "current_node_delay": "%s",\n' "$(json_string "$current_node_delay")"
  printf '  "current_node_alive": "%s",\n' "$(json_string "$current_node_alive")"
  printf '  "last_probe_at": "%s",\n' "$(json_string "$last_probe_at")"
  printf '  "exit_ip": "%s",\n' "$(json_string "$exit_ip")"
  printf '  "exit_country": "%s",\n' "$(json_string "$exit_country")"
  printf '  "exit_colo": "%s",\n' "$(json_string "$exit_colo")"
  printf '  "cpu_pct": "%s",\n' "$(json_string "$cpu_pct")"
  printf '  "mem_pct": "%s",\n' "$(json_string "$mem_pct")"
  printf '  "clash_cpu_pct": "%s",\n' "$(json_string "$(printf '%s' "$clash_usage" | cut -f1)")"
  printf '  "clash_vsz_pct": "%s",\n' "$(json_string "$(printf '%s' "$clash_usage" | cut -f2)")"
  printf '  "clash_mem_mb": "%s",\n' "$(json_string "$clash_mem_mb")"
  printf '  "recent_error_count": "%s",\n' "$(json_string "$recent_errors")"
  printf '  "config_path": "%s",\n' "$(json_string "$config_path")"
  printf '  "config_name": "%s",\n' "$(json_string "$config_name")"
  printf '  "config_updated_at": "%s",\n' "$(json_string "$config_updated_at")"
  printf '  "dns_chain": "%s",\n' "$(json_string "$dns_chain")"
  printf '  "dns_diag_code": "%s",\n' "$(json_string "$dns_diag_code")"
  printf '  "dns_diag_level": "%s",\n' "$(json_string "$dns_diag_level")"
  printf '  "dns_diag_summary": "%s",\n' "$(json_string "$dns_diag_summary")"
  printf '  "dns_diag_action": "%s"\n' "$(json_string "$dns_diag_action")"
  printf '}\n'
}

advice_json() {
  local role mode needs_ipv6 has_public uses_tailscale gaming low_maintenance auto_interval profile risk why pitfalls checklist
  local config_tier dns_plan runtime_plan log_level_plan auto_update_plan default_policy_plan test_cycle_plan switch_plan
  local status media split flush auto subconvert
  local running controller_ready openclash_config current_node current_delay current_delay_num stream_auto_select recent_errors recent_errors_num cpu_pct cpu_pct_num mem_pct mem_pct_num
  local dns_level dns_summary dns_action split_success split_issue media_issue media_success media_partial media_no_data auto_enabled current_auto_enabled current_auto_interval
  local sub_source sub_enabled
  local openai_status openai_http codex_status codex_http claude_status gemini_status cursor_status grok_status perplexity_status poe_status
  local netflix_status disney_status youtube_status tiktok_status spotify_status
  local advice_summary

  role="$(str_uci routing_role bypass_router)"
  mode="$(str_uci preferred_mode auto)"
  needs_ipv6="$(bool_uci needs_ipv6 0)"
  has_public="$(bool_uci has_public_services 0)"
  uses_tailscale="$(bool_uci uses_tailscale 0)"
  gaming="$(bool_uci gaming_devices 0)"
  low_maintenance="$(bool_uci low_maintenance 1)"
  auto_interval="$(str_uci auto_switch_interval 30)"

  profile="均衡方案"
  risk="medium"
  why="建议优先采用兼容性更好的方案，在切换高级模式前先确认 DNS 接管是否正常。"
  pitfalls="上游 DNS 冲突、Fake-IP 缓存残留、TUN 与 IPv6 组合不匹配。"
  checklist="确认已安装 dnsmasq-full；确认 OpenClash 是实际生效的上游 DNS；切换模式前先备份配置。"
  config_tier="均衡配置"
  dns_plan="优先保证解析稳定，国内外网站都能稳定打开后，再考虑更激进的模式。"
  runtime_plan="默认建议自动或兼容优先，先减少兼容性问题。"
  log_level_plan="建议使用 info，既能保留必要信息，也不会把日志页刷得太乱。"
  auto_update_plan="建议保留自动更新，但不要过度频繁，避免线路还没稳定就反复刷新。"
  default_policy_plan="建议国内站点直连，国际常用服务走自动选择，AI 和流媒体保留单独分组。"
  test_cycle_plan="节点检查周期建议保持在 ${auto_interval} 分钟左右，先稳再快。"
  switch_plan="如果节点较多，建议开启自动切换，但不要把范围放得太大。"

  if [ "$role" = "bypass_router" ] && { [ "$has_public" = true ] || [ "$uses_tailscale" = true ] || [ "$gaming" = true ]; }; then
    profile="兼容优先"
    risk="high"
    why="旁路由场景如果同时有公网访问、组网工具或游戏设备，最容易遇到 Fake-IP 兼容性边界问题。"
    pitfalls="局域网服务访问异常、公网端口不可达、组网流量异常、切换模式后设备缓存污染。"
    checklist="先用兼容优先方案；测试公网访问是否正常；按需添加静态路由或绕过规则；逐步切换而不是一次改完。"
    config_tier="保守配置"
    dns_plan="优先保证 DNS 链路单一、稳定，不建议一开始叠太多 DNS 组件。"
    runtime_plan="建议兼容优先，先保证局域网设备、游戏机和远程访问都不受影响。"
    log_level_plan="建议使用 info，排障时够用，日常也不会太吵。"
    auto_update_plan="建议按需更新，不要在高峰时段频繁刷新订阅。"
    default_policy_plan="建议国内站点直连，国际服务走守候网络或自动选择，先不要过度分流。"
    test_cycle_plan="建议 30 分钟检查一次节点，避免频繁切换影响在线设备。"
    switch_plan="自动切换建议只在同类节点里进行，尽量不要全局乱切。"
  elif [ "$mode" = "fake-ip" ] && [ "$needs_ipv6" = true ]; then
    profile="Fake-IP + IPv6 谨慎模式"
    risk="high"
    why="社区反馈显示，Fake-IP 与 TUN / IPv6 的组合在某些固件或内核环境下比较脆弱。"
    pitfalls="TUN 启动失败、DNS 劫持判断混乱、IPv6 表现不稳定。"
    checklist="启用前先确认 TUN、firewall4 和 nft 支持正常，并保留可回滚方案。"
    config_tier="保守配置"
    dns_plan="建议先确保 IPv4 / IPv6 解析链路干净，再逐步打开更激进的模式。"
    runtime_plan="建议兼容优先或自动，不建议一开始就把 Fake-IP 和 IPv6 一起拉满。"
    default_policy_plan="先保证国内直连和常用代理稳定，再考虑更复杂的规则组。"
  elif [ "$low_maintenance" = true ]; then
    profile="稳定优先"
    risk="low"
    why="低维护需求应优先考虑稳定和可预期，而不是一味追求功能堆叠。"
    pitfalls="过度调优会提高维护成本，也更容易在升级后出现意外问题。"
    checklist="保留一套已验证可用的模式；避免频繁切换；修改前先记录当前 DNS 行为。"
    config_tier="保守配置"
    dns_plan="建议保持单一、稳定的解析链路，少改、少叠加。"
    runtime_plan="建议自动或兼容优先，优先追求长期稳定。"
    auto_update_plan="建议保留自动更新，但订阅更新频率不要太高。"
    default_policy_plan="建议国内直连，国外常用服务走自动选择，AI 与流媒体分组独立但不做过度微调。"
    switch_plan="建议把自动切换控制在温和模式，避免节点频繁跳来跳去。"
  elif [ "$mode" = "fake-ip" ] && [ "$needs_ipv6" = false ] && [ "$has_public" = false ] && [ "$uses_tailscale" = false ] && [ "$gaming" = false ]; then
    config_tier="激进优选配置"
    dns_plan="可以尝试更积极的解析模式，但仍建议先确认 DNS 没有冲突。"
    runtime_plan="如果核心和系统兼容，性能优先模式更适合追求速度的场景。"
    log_level_plan="日常保持 info，排障时再切到 warning 或 debug。"
    auto_update_plan="可以保留自动更新，并结合节点测速做定期优选。"
    default_policy_plan="建议国内站点直连，国际服务按用途拆分，AI、流媒体和开发下载分别独立分组。"
    test_cycle_plan="建议 10 到 30 分钟检查一次节点，适合追求更积极的线路优选。"
    switch_plan="建议启用自动切换，并优先在同地区优选节点里切换。"
  fi

  status="$(status_json)"
  media="$(media_ai_json)"
  split="$(split_tunnel_json)"
  flush="$(flush_dns_json)"
  auto="$(auto_switch_json)"
  subconvert="$(subconvert_json)"

  running="$(json_find_bool "$status" running)"
  controller_ready="$(json_find_bool "$status" controller_ready)"
  openclash_config="$(json_find_bool "$status" openclash_config)"
  current_node="$(json_find_string "$status" current_node)"
  current_delay="$(json_find_string "$status" current_node_delay)"
  current_delay_num="$(number_prefix "$current_delay")"
  stream_auto_select="$(json_find_string "$status" stream_auto_select)"
  recent_errors="$(json_find_string "$status" recent_error_count)"
  recent_errors_num="$(number_prefix "$recent_errors")"
  cpu_pct="$(json_find_string "$status" cpu_pct)"
  cpu_pct_num="$(number_prefix "$cpu_pct")"
  mem_pct="$(json_find_string "$status" mem_pct)"
  mem_pct_num="$(number_prefix "$mem_pct")"

  dns_level="$(json_find_string "$flush" dns_diag_level)"
  dns_summary="$(json_find_string "$flush" dns_diag_summary)"
  dns_action="$(json_find_string "$flush" dns_diag_action)"
  split_success="$(json_find_number "$split" success_count)"
  split_issue="$(json_find_number "$split" issue_count)"
  media_issue="$(json_find_number "$media" issue_count)"
  media_success="$(json_find_number "$media" success_count)"
  media_partial="$(json_find_number "$media" partial_count)"
  media_no_data="$(json_find_number "$media" no_data_count)"
  auto_enabled="$(json_find_bool "$auto" enabled)"
  current_auto_enabled="$(json_find_string "$auto" current_enabled)"
  current_auto_interval="$(json_find_string "$auto" current_interval)"
  sub_source="$(json_find_string "$subconvert" source)"
  sub_enabled="$(json_find_bool "$subconvert" enabled)"

  openai_status="$(json_find_string "$media" openai_status)"
  openai_http="$(json_find_string "$media" openai_http_code)"
  codex_status="$(json_find_string "$media" codex_status)"
  codex_http="$(json_find_string "$media" codex_http_code)"
  claude_status="$(json_find_string "$media" claude_status)"
  gemini_status="$(json_find_string "$media" gemini_status)"
  cursor_status="$(json_find_string "$media" cursor_status)"
  grok_status="$(json_find_string "$media" grok_status)"
  perplexity_status="$(json_find_string "$media" perplexity_status)"
  poe_status="$(json_find_string "$media" poe_status)"

  netflix_status="$(json_find_string "$media" netflix_status)"
  disney_status="$(json_find_string "$media" disney_status)"
  youtube_status="$(json_find_string "$media" youtube_status)"
  tiktok_status="$(json_find_string "$media" tiktok_status)"
  spotify_status="$(json_find_string "$media" spotify_status)"

  [ -n "$split_success" ] || split_success=0
  [ -n "$split_issue" ] || split_issue=0
  [ -n "$media_issue" ] || media_issue=0
  [ -n "$media_success" ] || media_success=0
  [ -n "$media_partial" ] || media_partial=0
  [ -n "$media_no_data" ] || media_no_data=0

  advice_reset_items

  if [ "$running" != 'true' ] || [ "$controller_ready" != 'true' ]; then
    advice_add_item \
      'core' \
      'fix' \
      '先恢复 OpenClash 运行' \
      '现在基础代理服务没有完全准备好，后面的流媒体、AI 和网站走向结果都不可靠。' \
      '先确认 OpenClash 能正常启动，再回来做体检和专项检测。' \
      "$(advice_action_tab 'overview' '查看运行状态')"
  elif [ "$openclash_config" != 'true' ]; then
    advice_add_item \
      'config' \
      'risk' \
      '当前还没有识别到有效配置' \
      '助手已经连上了 OpenClash，但没有检测到稳定可用的配置文件，后续结果可能会漂。' \
      '先完成订阅导入和配置生成，再重新检测。' \
      "$(advice_action_tab 'subconvert' '去导入订阅')"
  fi

  if [ -z "$sub_source" ]; then
    advice_add_item \
      'subscription' \
      'risk' \
      '先导入原始订阅' \
      '目前还没有拿到原始订阅地址，模板转换和一键导入流程还没真正开始。' \
      '到第一页粘贴订阅链接，选模板后直接写入 OpenClash。' \
      "$(advice_action_tab 'subconvert' '去导入订阅')"
  elif [ "$sub_enabled" != 'true' ]; then
    advice_add_item \
      'subconvert' \
      'optimize' \
      '建议打开本地订阅转换' \
      '现在虽然已经填了订阅，但还没启用导入前整理，小白模板、AI 和流媒体分组更难自动生成。' \
      '打开本地转换后端，再按用途选模板写入 OpenClash。' \
      "$(advice_action_tab 'subconvert' '去做订阅转换')"
  fi

  if [ "$dns_level" = 'bad' ]; then
    advice_add_item \
      'dns' \
      'fix' \
      '先修 DNS，再看网站和 AI' \
      "$(first_non_empty "$dns_summary" '当前解析链路不完整，网站容易出现打不开、时好时坏、能 ping 不能访问。')" \
      "$(first_non_empty "$dns_action" '建议先刷新解析，再重新检测一次。')" \
      "$(advice_action_command 'flush-dns' '一键刷新解析')"
  elif [ "$dns_level" = 'warn' ]; then
    advice_add_item \
      'dns' \
      'risk' \
      'DNS 有冲突提示' \
      "$(first_non_empty "$dns_summary" '当前解析链路存在冲突，流媒体和 AI 服务最容易先受影响。')" \
      "$(first_non_empty "$dns_action" '建议先刷新解析，再检查 DNS 页面里的链路说明。')" \
      "$(advice_action_command 'flush-dns' '先刷新解析')"
  fi

  if { [ "$openai_status" = 'reachable' ] && [ "$openai_http" = '401' ]; } || { [ "$codex_status" = 'reachable' ] && [ "$codex_http" = '401' ]; }; then
    advice_add_item \
      'ai-auth' \
      'ok' \
      'OpenAI / Codex 线路基本正常' \
      '检测结果更像“已经连通，但缺少 API 认证”，这通常不是节点坏了，而是密钥或账号配置还没补齐。' \
      '如果你在用 API，请优先检查 Key、组织号和客户端配置，不要先急着换节点。' \
      "$(advice_action_tab 'ai' '查看 AI 检测')"
  fi

  if media_status_is_issue "$netflix_status" && media_status_is_good "$youtube_status"; then
    advice_add_item \
      'streaming-netflix' \
      'risk' \
      '当前节点不适合长期看 Netflix' \
      '现在 YouTube 基本正常，但 Netflix 仍然受限，更像是地区或节点类型不匹配，不是整条线路都坏了。' \
      '给流媒体单独分组，优先换到更稳定的流媒体地区节点。' \
      "$(advice_action_tab 'streaming' '查看流媒体检测')"
  elif media_status_is_issue "$netflix_status" || media_status_is_issue "$disney_status" || media_status_is_issue "$tiktok_status" || media_status_is_issue "$spotify_status"; then
    advice_add_item \
      'streaming' \
      'optimize' \
      '流媒体线路还不够稳' \
      '至少有一项常用流媒体显示受限或地区不理想，继续拿它当长期主力节点，体验会不稳定。' \
      '去流媒体检测页看具体是地区问题还是线路问题，再决定是否单独建流媒体分组。' \
      "$(advice_action_tab 'streaming' '查看流媒体检测')"
  fi

  if media_status_is_issue "$openai_status" || media_status_is_issue "$claude_status" || media_status_is_issue "$gemini_status" || media_status_is_issue "$cursor_status" || media_status_is_issue "$grok_status" || media_status_is_issue "$perplexity_status" || media_status_is_issue "$poe_status"; then
    advice_add_item \
      'ai-region' \
      'risk' \
      'AI 服务更像地区或分组不匹配' \
      '当前至少有一项 AI 服务访问受限，优先怀疑分流分组、地区节点和 DNS 一致性，而不是直接判定订阅失效。' \
      '先把 AI 服务放到单独分组，再尝试美国 / 新加坡 / 日本等更常见的 AI 节点。' \
      "$(advice_action_tab 'ai' '查看 AI 检测')"
  elif [ "$media_no_data" -gt 0 ] && [ "$media_success" -eq 0 ]; then
    advice_add_item \
      'ai-media-test' \
      'optimize' \
      '建议补跑一次真实专项检测' \
      '现在还没有拿到完整的流媒体和 AI 实测结果，助手没法稳定判断哪些节点更适合长期使用。' \
      '去专项检测页跑一轮真实测试，再按结果做推荐。' \
      "$(advice_action_tab 'streaming' '去跑专项检测')"
  fi

  if [ "$split_success" -eq 0 ]; then
    advice_add_item \
      'split' \
      'optimize' \
      '建议跑一次网站走向检测' \
      '现在还不知道网站到底是直连、代理，还是走错了分组，所以很多“打不开”的原因还没法说准。' \
      '输入常用网站或服务名，先看它实际走了哪条路。' \
      "$(advice_action_tab 'split' '去测网站走向')"
  elif [ "$split_issue" -gt 0 ]; then
    advice_add_item \
      'split' \
      'optimize' \
      '有些网站走向不太理想' \
      '最近一轮网站走向检测里，已经出现了分流不符合预期的目标，说明规则或模板还可以继续优化。' \
      '优先看打不开的网站、AI 服务和下载站点，确认它们是不是走错了分组。' \
      "$(advice_action_tab 'split' '查看网站走向')"
  fi

  if [ "$auto_enabled" = 'true' ] && [ "$current_auto_enabled" != '1' ]; then
    advice_add_item \
      'auto-switch' \
      'optimize' \
      '建议把自动切换真正应用到 OpenClash' \
      "助手已经根据你的场景给出了自动切换方案，但 OpenClash 当前还没有启用。节点波动时，你还得手动切换。" \
      "直接应用后，OpenClash 会按 ${auto_interval} 分钟左右做温和优选，减少手动折腾。" \
      "$(advice_action_command 'apply-auto-switch' '一键应用自动切换')"
  fi

  if [ "$current_delay_num" -ge 180 ] || [ "$recent_errors_num" -ge 15 ] || [ "$cpu_pct_num" -ge 85 ] || [ "$mem_pct_num" -ge 85 ]; then
    advice_add_item \
      'quality' \
      'risk' \
      '当前线路质量或设备负载需要关注' \
      "默认节点延迟 ${current_delay:-未知} ms，最近错误 ${recent_errors:-0} 次，系统占用 ${cpu_pct:-0}% / ${mem_pct:-0}%。如果继续升高，流媒体和 AI 结果会更不稳。" \
      '先跑网站走向和专项检测，必要时换到更稳的节点，或者减少过于激进的功能组合。' \
      "$(advice_action_tab 'checkup' '查看体检详情')"
  fi

  if [ "$ADVICE_ITEM_COUNT" -eq 0 ]; then
    advice_add_item \
      'healthy' \
      'ok' \
      '当前基础状态适合继续使用' \
      '基础运行、DNS 和专项检测暂时没有明显风险，当前更适合继续按用途细调，而不是大改配置。' \
      '如果你还想继续优化，优先看网站走向、流媒体和 AI 服务的差异。' \
      "$(advice_action_tab 'overview' '查看基础配置')"
  fi

  advice_summary='当前建议以稳定优先为主，可以继续按用途细调。'
  case "$ADVICE_TOP_LEVEL" in
    fix) advice_summary='建议先处理基础运行或 DNS 问题，修好后再做节点优选、流媒体和 AI 检测。' ;;
    risk) advice_summary='当前已经能用，但至少有一项关键能力存在风险。建议按卡片顺序处理，不要同时乱改。' ;;
    optimize) advice_summary='当前基础状态还可以，接下来更适合做网站走向、专项检测和自动切换优化。' ;;
    *) advice_summary='当前没有明显风险，可以直接按推荐配置继续使用。' ;;
  esac

  printf '{\n'
  printf '  "profile": "%s",\n' "$(json_string "$profile")"
  printf '  "risk": "%s",\n' "$(json_string "$risk")"
  printf '  "why": "%s",\n' "$(json_string "$why")"
  printf '  "pitfalls": "%s",\n' "$(json_string "$pitfalls")"
  printf '  "checklist": "%s",\n' "$(json_string "$checklist")"
  printf '  "config_tier": "%s",\n' "$(json_string "$config_tier")"
  printf '  "dns_plan": "%s",\n' "$(json_string "$dns_plan")"
  printf '  "runtime_plan": "%s",\n' "$(json_string "$runtime_plan")"
  printf '  "log_level_plan": "%s",\n' "$(json_string "$log_level_plan")"
  printf '  "auto_update_plan": "%s",\n' "$(json_string "$auto_update_plan")"
  printf '  "default_policy_plan": "%s",\n' "$(json_string "$default_policy_plan")"
  printf '  "test_cycle_plan": "%s",\n' "$(json_string "$test_cycle_plan")"
  printf '  "switch_plan": "%s",\n' "$(json_string "$switch_plan")"
  printf '  "summary": "%s",\n' "$(json_string "$advice_summary")"
  printf '  "overall_level": "%s",\n' "$(json_string "$ADVICE_TOP_LEVEL")"
  printf '  "item_count": %s,\n' "$ADVICE_ITEM_COUNT"
  printf '  "items": [\n%b\n  ]\n' "$ADVICE_ITEMS"
  printf '}\n'
}

checkup_json() {
  local status media split flush auto subconvert
  local running openclash_config current_node current_delay dns_level dns_action stream_auto_select sub_source sub_enabled media_issue media_success split_success split_issue auto_enabled
  local overall='ok' summary dns_level_label current_node_text item_core_level item_sub_level item_dns_level item_node_level item_media_level item_split_level item_auto_level repairable_count

  status="$(status_json)"
  media="$(media_ai_json)"
  split="$(split_tunnel_json)"
  flush="$(flush_dns_json)"
  auto="$(auto_switch_json)"
  subconvert="$(subconvert_json)"

  running="$(json_find_bool "$status" running)"
  openclash_config="$(json_find_bool "$status" openclash_config)"
  current_node="$(json_find_string "$status" current_node)"
  current_delay="$(json_find_string "$status" current_node_delay)"
  dns_level="$(json_find_string "$flush" dns_diag_level)"
  dns_action="$(json_find_string "$flush" dns_diag_action)"
  stream_auto_select="$(json_find_string "$status" stream_auto_select)"
  sub_source="$(json_find_string "$subconvert" source)"
  sub_enabled="$(json_find_bool "$subconvert" enabled)"
  media_issue="$(json_find_number "$media" issue_count)"
  media_success="$(json_find_number "$media" success_count)"
  split_success="$(json_find_number "$split" success_count)"
  split_issue="$(json_find_number "$split" issue_count)"
  auto_enabled="$(json_find_bool "$auto" enabled)"

  [ -n "$media_issue" ] || media_issue=0
  [ -n "$media_success" ] || media_success=0
  [ -n "$split_success" ] || split_success=0
  [ -n "$split_issue" ] || split_issue=0
  repairable_count=0

  item_core_level='ok'
  if [ "$running" != 'true' ]; then
    item_core_level='fix'
    overall='fix'
    repairable_count=$((repairable_count + 1))
  elif [ "$openclash_config" != 'true' ]; then
    item_core_level='risk'
    [ "$overall" = 'ok' ] && overall='risk'
  fi

  item_sub_level='ok'
  if [ -z "$sub_source" ]; then
    item_sub_level='risk'
    [ "$overall" = 'ok' ] && overall='risk'
  elif [ "$sub_enabled" != 'true' ]; then
    item_sub_level='optimize'
    [ "$overall" = 'ok' ] && overall='optimize'
    repairable_count=$((repairable_count + 1))
  fi

  item_dns_level='ok'
  if [ "$dns_level" = 'bad' ]; then
    item_dns_level='fix'
    overall='fix'
    repairable_count=$((repairable_count + 1))
  elif [ "$dns_level" = 'warn' ] && [ "$overall" != 'fix' ]; then
    item_dns_level='risk'
    [ "$overall" = 'ok' ] && overall='risk'
    repairable_count=$((repairable_count + 1))
  fi

  item_node_level='ok'
  if [ -z "$current_node" ]; then
    item_node_level='fix'
    overall='fix'
  elif [ -n "$current_delay" ] && [ "$current_delay" -ge 400 ] 2>/dev/null && [ "$overall" != 'fix' ]; then
    item_node_level='risk'
    [ "$overall" = 'ok' ] && overall='risk'
  elif [ -n "$current_delay" ] && [ "$current_delay" -ge 250 ] 2>/dev/null && [ "$overall" = 'ok' ]; then
    item_node_level='optimize'
    overall='optimize'
  fi

  item_media_level='ok'
  if [ "$media_issue" -gt 0 ] && [ "$overall" != 'fix' ]; then
    item_media_level='risk'
    [ "$overall" = 'ok' ] && overall='risk'
  elif [ "$media_success" -eq 0 ] && [ "$overall" = 'ok' ]; then
    item_media_level='optimize'
    overall='optimize'
  fi

  item_split_level='ok'
  if [ "$split_success" -eq 0 ] && [ "$overall" = 'ok' ]; then
    item_split_level='optimize'
    overall='optimize'
  elif [ "$split_issue" -gt 0 ] && [ "$overall" = 'ok' ]; then
    item_split_level='optimize'
    overall='optimize'
  fi

  item_auto_level='ok'
  if [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && [ "$overall" = 'ok' ]; then
    item_auto_level='optimize'
    overall='optimize'
    repairable_count=$((repairable_count + 1))
  fi

  summary='当前整体状态正常，可以继续使用。'
  if [ "$overall" = 'fix' ]; then
    summary='当前有需要优先修复的问题，建议先处理基础服务、解析或默认节点。'
  elif [ "$overall" = 'risk' ]; then
    summary='当前已经能用，但存在影响稳定性的风险项，建议继续处理。'
  elif [ "$overall" = 'optimize' ]; then
    summary='当前基本可用，但还有一些地方可以进一步优化。'
  fi

  current_node_text="${current_node:-当前还没有识别到默认节点}"
  [ -n "$current_delay" ] && current_node_text="${current_node_text}，最近延迟 ${current_delay} ms"

  printf '{\n'
  printf '  "overall": "%s",\n' "$(json_string "$overall")"
  printf '  "summary": "%s",\n' "$(json_string "$summary")"
  printf '  "repairable_count": %s,\n' "$repairable_count"
  printf '  "items": [\n'
  printf '    {"key":"core","title":"基础服务","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}},\n' \
    "$item_core_level" \
    "$(json_string "$( [ "$running" = 'true' ] && echo 'OpenClash 当前已经在运行，基础服务已接管。' || echo 'OpenClash 当前没有正常运行，后面的检测结果都不可靠。' )")" \
    "$(json_string "$( [ "$running" = 'true' ] && echo '可以继续看订阅、检测和建议。' || echo '先尝试恢复 OpenClash 运行，再继续做体检。' )")" \
    "$( [ "$running" = 'true' ] && echo 'tab' || echo 'command' )" \
    "$( [ "$running" = 'true' ] && echo '查看概览' || echo '一键恢复基础服务' )" \
    "$( [ "$running" = 'true' ] && echo 'tab' || echo 'command' )" \
    "$( [ "$running" = 'true' ] && echo 'overview' || echo 'restart-openclash' )"
  printf '    {"key":"subscription","title":"订阅导入","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}},\n' \
    "$item_sub_level" \
    "$(json_string "$( [ -n "$sub_source" ] && [ "$sub_enabled" = 'true' ] && echo '已经填写原始订阅，并启用了导入前整理。' || ([ -n "$sub_source" ] && echo '已经填写订阅，但当前没有启用导入前整理。' || echo '还没有填写原始订阅地址。') )")" \
    "$(json_string "$( [ -n "$sub_source" ] && echo '确认模板后，把整理好的订阅写入 OpenClash。' || echo '先去导入订阅，再继续做配置和检测。' )")" \
    "$( [ -n "$sub_source" ] && [ "$sub_enabled" != 'true' ] && echo 'command' || echo 'tab' )" \
    "$( [ -n "$sub_source" ] && [ "$sub_enabled" != 'true' ] && echo '应用推荐配置' || ([ -n "$sub_source" ] && echo '去看订阅页' || echo '去导入订阅') )" \
    "$( [ -n "$sub_source" ] && [ "$sub_enabled" != 'true' ] && echo 'command' || echo 'tab' )" \
    "$( [ -n "$sub_source" ] && [ "$sub_enabled" != 'true' ] && echo 'apply-recommended-profile' || echo 'subconvert' )"
  printf '    {"key":"dns","title":"解析状态","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}},\n' \
    "$item_dns_level" \
    "$(json_string "$( [ "$dns_level" = 'good' ] && echo '当前解析链路基本正常。' || ([ "$dns_level" = 'bad' ] && echo '当前解析链路不完整，网站容易时好时坏。' || echo '当前解析链路有冲突，可能影响网站和 AI 服务。') )")" \
    "$(json_string "$( [ "$dns_level" = 'good' ] && echo '如果个别网站仍异常，再刷新一次解析即可。' || first_non_empty "$dns_action" '建议先刷新解析，再重新检测。' )")" \
    "$( [ "$dns_level" = 'good' ] && echo 'tab' || echo 'command' )" \
    "$( [ "$dns_level" = 'good' ] && echo '查看解析页' || echo '一键刷新解析' )" \
    "$( [ "$dns_level" = 'good' ] && echo 'tab' || echo 'command' )" \
    "$( [ "$dns_level" = 'good' ] && echo 'dns' || echo 'flush-dns' )"
  printf '    {"key":"node","title":"默认节点","level":"%s","text":"%s","next":"%s","action":{"type":"tab","label":"%s","tab":"split"}},\n' \
    "$item_node_level" \
    "$(json_string "$current_node_text")" \
    "$(json_string "$( [ -n "$current_node" ] && echo '如果延迟偏高或结果不稳，建议继续看网站走向和流媒体结果。' || echo '先确认策略组里已经选中可用节点。' )")" \
    "$( [ -n "$current_node" ] && echo '去看网站走向' || echo '去看网站走向' )"
  printf '    {"key":"media_ai","title":"流媒体和 AI","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}},\n' \
    "$item_media_level" \
    "$(json_string "$( [ "$media_issue" -gt 0 ] && echo '当前至少有一部分流媒体或 AI 服务访问受限。' || ([ "$media_success" -gt 0 ] && echo '最近已经测到可用的流媒体或 AI 服务。' || echo '还没有拿到完整的流媒体和 AI 检测结果。') )")" \
    "$(json_string "$( [ "$media_issue" -gt 0 ] && echo '建议先看流媒体页和 AI 页，确认问题出在地区还是线路。' || echo '如果你经常看视频或用 AI，建议主动跑一次专项检测。' )")" \
    "$( [ "$media_success" -eq 0 ] && [ "$media_issue" -eq 0 ] && echo 'command' || echo 'tab' )" \
    "$( [ "$media_success" -eq 0 ] && [ "$media_issue" -eq 0 ] && echo '一键开始专项检测' || echo '去看专项检测' )" \
    "$( [ "$media_success" -eq 0 ] && [ "$media_issue" -eq 0 ] && echo 'command' || echo 'tab' )" \
    "$( [ "$media_success" -eq 0 ] && [ "$media_issue" -eq 0 ] && echo 'run-media-ai-live-test' || echo 'streaming' )"
  printf '    {"key":"split","title":"网站走向","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}},\n' \
    "$item_split_level" \
    "$(json_string "$( [ "$split_success" -gt 0 ] && echo '已经拿到一批网站走向结果，可以判断网站到底从哪里出去。' || echo '还没有运行网站走向检测。')")" \
    "$(json_string "$( [ "$split_success" -gt 0 ] && echo '如果网站走向不合理，再回到订阅或场景页调整。' || echo '建议至少跑一次网站走向检测。' )")" \
    "$( [ "$split_success" -eq 0 ] && echo 'command' || echo 'tab' )" \
    "$( [ "$split_success" -eq 0 ] && echo '一键开始走向检测' || echo '去看网站走向' )" \
    "$( [ "$split_success" -eq 0 ] && echo 'command' || echo 'tab' )" \
    "$( [ "$split_success" -eq 0 ] && echo 'run-split-tunnel-test' || echo 'split' )"
  printf '    {"key":"auto","title":"自动切换","level":"%s","text":"%s","next":"%s","action":{"type":"%s","label":"%s","%s":"%s"}}\n' \
    "$item_auto_level" \
    "$(json_string "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo '系统建议开启自动切换，但 OpenClash 里还没有应用。' || echo '自动切换当前没有明显冲突。' )")" \
    "$(json_string "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo '如果你节点多、波动大，建议应用自动切换。' || echo '如果你更在意稳定，保持当前设置也可以。' )")" \
    "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo 'command' || echo 'tab' )" \
    "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo '一键应用自动切换' || echo '去看自动切换' )" \
    "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo 'command' || echo 'tab' )" \
    "$( [ "$auto_enabled" = 'true' ] && [ "$stream_auto_select" != '1' ] && echo 'apply-auto-switch' || echo 'auto' )"
  printf '  ]\n'
  printf '}\n'
}

auto_switch_json() {
  local quick
  local enabled goal logic interval scope latency_threshold packet_loss_threshold fail_threshold revert_preferred expand_group close_con
  local current_enabled current_logic current_interval logic_label goal_label scope_label revert_label suggestion commands
  local goal_hint scope_hint threshold_hint recommendation_title
  local status media current_node current_delay current_delay_num recent_errors recent_errors_num
  local openai_status codex_status claude_status gemini_status cursor_status grok_status perplexity_status poe_status
  local netflix_status disney_status youtube_status tiktok_status spotify_status
  local ai_good_count ai_issue_count streaming_good_count streaming_issue_count
  local node_best_for node_ai_fit node_streaming_fit node_game_fit node_long_term_fit node_profile_title node_profile_summary node_switch_reason node_next_step

  quick=false
  [ "${1:-}" = '--fast' ] && quick=true

  enabled="$(bool_uci auto_switch_enabled 1)"
  goal="$(str_uci auto_switch_goal stability)"
  logic="$(str_uci auto_switch_logic urltest)"
  interval="$(str_uci auto_switch_interval 30)"
  scope="$(str_uci auto_switch_scope same_group)"
  latency_threshold="$(str_uci auto_switch_latency_threshold 180)"
  packet_loss_threshold="$(str_uci auto_switch_packet_loss_threshold 20)"
  fail_threshold="$(str_uci auto_switch_fail_threshold 2)"
  revert_preferred="$(bool_uci auto_switch_revert_preferred 1)"
  expand_group="$(bool_uci auto_switch_expand_group 1)"
  close_con="$(bool_uci auto_switch_close_con 1)"

  current_enabled="$(uci -q get openclash.config.stream_auto_select 2>/dev/null || echo 0)"
  current_logic="$(uci -q get openclash.config.stream_auto_select_logic 2>/dev/null || echo urltest)"
  current_interval="$(uci -q get openclash.config.stream_auto_select_interval 2>/dev/null || echo 30)"
  status="$(status_json)"
  if [ "$quick" = true ]; then
    media='{}'
  else
    media="$(media_ai_json)"
  fi

  current_node="$(json_find_string "$status" current_node)"
  current_delay="$(json_find_string "$status" current_node_delay)"
  current_delay_num="$(number_prefix "$current_delay")"
  recent_errors="$(json_find_string "$status" recent_error_count)"
  recent_errors_num="$(number_prefix "$recent_errors")"
  openai_status="$(json_find_string "$media" openai_status)"
  codex_status="$(json_find_string "$media" codex_status)"
  claude_status="$(json_find_string "$media" claude_status)"
  gemini_status="$(json_find_string "$media" gemini_status)"
  cursor_status="$(json_find_string "$media" cursor_status)"
  grok_status="$(json_find_string "$media" grok_status)"
  perplexity_status="$(json_find_string "$media" perplexity_status)"
  poe_status="$(json_find_string "$media" poe_status)"
  netflix_status="$(json_find_string "$media" netflix_status)"
  disney_status="$(json_find_string "$media" disney_status)"
  youtube_status="$(json_find_string "$media" youtube_status)"
  tiktok_status="$(json_find_string "$media" tiktok_status)"
  spotify_status="$(json_find_string "$media" spotify_status)"

  ai_good_count=0
  ai_issue_count=0
  streaming_good_count=0
  streaming_issue_count=0
  for node_status in "$openai_status" "$codex_status" "$claude_status" "$gemini_status" "$cursor_status" "$grok_status" "$perplexity_status" "$poe_status"; do
    media_status_is_good "$node_status" && ai_good_count=$((ai_good_count + 1))
    media_status_is_issue "$node_status" && ai_issue_count=$((ai_issue_count + 1))
  done
  for node_status in "$netflix_status" "$disney_status" "$youtube_status" "$tiktok_status" "$spotify_status"; do
    media_status_is_good "$node_status" && streaming_good_count=$((streaming_good_count + 1))
    media_status_is_issue "$node_status" && streaming_issue_count=$((streaming_issue_count + 1))
  done

  node_best_for='日常浏览'
  node_ai_fit='可临时使用'
  node_streaming_fit='可临时使用'
  node_game_fit='不建议'
  node_long_term_fit='可继续观察'
  node_profile_title='当前节点偏日常综合'
  node_profile_summary='这条线路目前更像通用日常线路，能满足基础网页和常规代理，但是否适合 AI、流媒体和长期主力，还要看专项检测结果。'
  node_switch_reason='如果你没有明显异常，可以先保持当前节点。'
  node_next_step='继续看 AI、流媒体和网站走向结果，再决定是否单独建分组。'

  if [ "$current_delay_num" -gt 0 ] && [ "$current_delay_num" -le 80 ] && [ "$ai_good_count" -ge 2 ]; then
    node_best_for='AI + 日常'
    node_ai_fit='适合'
    node_game_fit='可临时使用'
    node_profile_title='当前节点更适合 AI 和日常'
    node_profile_summary='这条线路延迟不高，且至少有两项 AI 服务连通正常，更适合对话、开发工具和日常浏览一起用。'
  elif [ "$streaming_good_count" -ge 2 ] && [ "$streaming_issue_count" -le 1 ]; then
    node_best_for='流媒体'
    node_streaming_fit='适合'
    node_long_term_fit='适合长期看视频'
    node_profile_title='当前节点更适合流媒体'
    node_profile_summary='这条线路在流媒体结果上更稳定，适合继续作为看视频的候选主力节点。'
  elif [ "$current_delay_num" -gt 0 ] && [ "$current_delay_num" -le 60 ] && [ "$recent_errors_num" -le 3 ]; then
    node_best_for='低延迟'
    node_game_fit='适合'
    node_profile_title='当前节点更适合低延迟场景'
    node_profile_summary='这条线路延迟较低、近期错误不多，更适合游戏、远程桌面或实时交互。'
  fi

  if [ "$ai_issue_count" -ge 3 ]; then
    node_ai_fit='不太适合'
    if [ "$node_best_for" = 'AI + 日常' ]; then
      node_best_for='日常浏览'
      node_profile_title='当前节点偏日常综合'
      node_profile_summary='这条线路在基础网页和常规代理上还能用，但 AI 结果不够稳定，不适合长期承担 AI 主力线路。'
    fi
    node_switch_reason='当前至少有多项 AI 服务受限，这条线路不适合长期承担 ChatGPT、Claude、Cursor 这类用途。'
    node_next_step='建议把 AI 放到单独分组，优先换到美国 / 日本 / 新加坡等更常见的 AI 节点。'
  fi
  if [ "$streaming_issue_count" -ge 2 ]; then
    node_streaming_fit='不太适合'
    if [ "$node_best_for" = '流媒体' ]; then
      node_best_for='日常浏览'
      node_profile_title='当前节点偏日常综合'
      node_profile_summary='这条线路在基础使用上还能用，但流媒体结果不够稳，不适合长期承担视频解锁主力。'
    fi
    node_switch_reason='当前常用流媒体里至少有两项不稳定，这条线路不适合长期承担视频解锁。'
    node_next_step='建议给流媒体单独分组，优先换到更稳定、地区更匹配的节点。'
  fi
  if [ "$current_delay_num" -ge 180 ]; then
    node_game_fit='不适合'
    node_long_term_fit='不建议长期使用'
    node_switch_reason='当前延迟已经偏高，这条线路即使能连通，也更容易在游戏、AI 和视频高峰时掉体验。'
    node_next_step='建议先应用自动切换，或切到更低延迟的同组节点。'
  fi
  if [ "$recent_errors_num" -ge 15 ]; then
    node_long_term_fit='不建议长期使用'
    node_profile_title='当前节点短期可用，但不建议长期使用'
    node_profile_summary='这条线路近期错误偏多，就算暂时能用，也更像临时线路，不适合作为长期主力。'
    node_switch_reason='近期错误次数偏多，继续长期挂在当前节点上，体验容易忽好忽坏。'
    node_next_step='建议优先切到更稳的候选节点，并保留当前节点作为备用。'
  fi

  case "$goal" in
    speed) goal_label='速度优先'; goal_hint='更适合日常刷网页、下载和常规代理，容忍偶尔切换。'; logic='urltest'; close_con=true ;;
    streaming) goal_label='流媒体优先'; goal_hint='更适合视频平台，优先保持地区稳定，再考虑速度。'; logic='urltest'; close_con=true ;;
    ai) goal_label='AI 优先'; goal_hint='更适合 ChatGPT、Claude、Gemini、Cursor 这类对地区和稳定性都敏感的服务。'; logic='urltest'; close_con=true ;;
    game) goal_label='游戏低延迟'; goal_hint='更适合对延迟更敏感的游戏设备，建议阈值更严格。'; logic='urltest'; close_con=true ;;
    *) goal='stability'; goal_label='稳定优先'; goal_hint='更适合家里多人共用、售后交付和长期放着不折腾的场景。'; logic='urltest' ;;
  esac

  case "$scope" in
    same_region) scope_label='同地区'; scope_hint='优先在同地区节点里切，地区更稳定，适合流媒体和 AI。'; expand_group=false ;;
    global) scope_label='全局'; scope_hint='候选范围最大，更适合节点少或线路波动大的场景。'; expand_group=true ;;
    *) scope='same_group'; scope_label='同策略组'; scope_hint='先在当前策略组内切换，最稳妥，也最不容易误伤其它用途。'; expand_group=true ;;
  esac

  threshold_hint="当延迟超过 ${latency_threshold} ms、丢包率超过 ${packet_loss_threshold}% 或连续失败达到 ${fail_threshold} 次时，建议考虑切换。"
  if [ "$revert_preferred" = true ]; then
    revert_label='允许回切首选节点'
  else
    revert_label='保持当前优选结果'
  fi

  case "$logic" in
    random) logic_label='随机轮换' ;;
    *) logic='urltest'; logic_label='延迟优先（Urltest）' ;;
  esac

  if [ "$enabled" = true ]; then
    recommendation_title="${goal_label}自动切换"
    suggestion="当前建议采用${goal_label}，切换范围为${scope_label}，检查周期 ${interval} 分钟。${threshold_hint}${scope_hint}"
  else
    recommendation_title='暂不自动切换'
    suggestion="当前助手建议未启用自动切换；如果节点较多、线路波动大，或者你经常看流媒体、用 AI，建议打开自动切换。"
  fi

  commands="uci set openclash.config.stream_auto_select='$( [ "$enabled" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_interval='${interval}'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_logic='${logic}'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_expand_group='$( [ "$expand_group" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_close_con='$( [ "$close_con" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci commit openclash\n/etc/init.d/openclash restart"

  printf '{\n'
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "goal": "%s",\n' "$(json_string "$goal")"
  printf '  "goal_label": "%s",\n' "$(json_string "$goal_label")"
  printf '  "logic": "%s",\n' "$(json_string "$logic")"
  printf '  "logic_label": "%s",\n' "$(json_string "$logic_label")"
  printf '  "interval": "%s",\n' "$(json_string "$interval")"
  printf '  "scope": "%s",\n' "$(json_string "$scope")"
  printf '  "scope_label": "%s",\n' "$(json_string "$scope_label")"
  printf '  "latency_threshold": "%s",\n' "$(json_string "$latency_threshold")"
  printf '  "packet_loss_threshold": "%s",\n' "$(json_string "$packet_loss_threshold")"
  printf '  "fail_threshold": "%s",\n' "$(json_string "$fail_threshold")"
  printf '  "revert_preferred": %s,\n' "$revert_preferred"
  printf '  "revert_label": "%s",\n' "$(json_string "$revert_label")"
  printf '  "expand_group": %s,\n' "$expand_group"
  printf '  "close_con": %s,\n' "$close_con"
  printf '  "current_enabled": "%s",\n' "$(json_string "$current_enabled")"
  printf '  "current_logic": "%s",\n' "$(json_string "$current_logic")"
  printf '  "current_interval": "%s",\n' "$(json_string "$current_interval")"
  printf '  "current_node": "%s",\n' "$(json_string "$current_node")"
  printf '  "current_delay": "%s",\n' "$(json_string "$current_delay")"
  printf '  "node_best_for": "%s",\n' "$(json_string "$node_best_for")"
  printf '  "node_ai_fit": "%s",\n' "$(json_string "$node_ai_fit")"
  printf '  "node_streaming_fit": "%s",\n' "$(json_string "$node_streaming_fit")"
  printf '  "node_game_fit": "%s",\n' "$(json_string "$node_game_fit")"
  printf '  "node_long_term_fit": "%s",\n' "$(json_string "$node_long_term_fit")"
  printf '  "node_profile_title": "%s",\n' "$(json_string "$node_profile_title")"
  printf '  "node_profile_summary": "%s",\n' "$(json_string "$node_profile_summary")"
  printf '  "node_switch_reason": "%s",\n' "$(json_string "$node_switch_reason")"
  printf '  "node_next_step": "%s",\n' "$(json_string "$node_next_step")"
  printf '  "recommendation_title": "%s",\n' "$(json_string "$recommendation_title")"
  printf '  "goal_hint": "%s",\n' "$(json_string "$goal_hint")"
  printf '  "scope_hint": "%s",\n' "$(json_string "$scope_hint")"
  printf '  "threshold_hint": "%s",\n' "$(json_string "$threshold_hint")"
  printf '  "suggestion": "%s",\n' "$(json_string "$suggestion")"
  printf '  "commands": "%s"\n' "$(json_string "$commands")"
  printf '}\n'
}

templates_json() {
  local first=1
  printf '{\n  "templates": [\n'
  if [ -r "$SUB_INI_LIST" ]; then
    while IFS=, read -r name id url; do
      [ -n "$id" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ',\n'
      fi
      first=0
      printf '    {"name":"%s","id":"%s","url":"%s"}' \
        "$(json_string "$name")" "$(json_string "$id")" "$(json_string "$url")"
    done < "$SUB_INI_LIST"
  else
    emit_default_templates_json
  fi
  printf '\n  ]\n}\n'
}

subconvert_json() {
  local quick
  local enabled source backend_origin backend_api frontend_base template_id custom_template emoji udp sort skip_verify append_type template_info template_name template_url recommended_id recommended_info recommended_name recommended_url encoded_source encoded_template convert_url frontend_url source_hint commands
  local source_valid backend_probe backend_ready backend_status_text template_status_text should_convert_text next_step source_status_text history_json history_count history_label source_ready template_ready
  local expected_groups_text expected_domestic expected_international expected_ai expected_streaming expected_download
  local source_probe source_probe_kind source_probe_text source_probe_sample source_detected_as

  quick=false
  [ "${1:-}" = '--fast' ] && quick=true

  enabled="$(bool_uci sub_convert_enabled 1)"
  source="$(str_uci sub_convert_source '')"
  backend_origin="$(subconvert_backend_origin "$(str_uci sub_convert_backend 'http://127.0.0.1:25500')")"
  backend_api="$(subconvert_backend_api "$backend_origin")"
  frontend_base="$(subconvert_frontend_path)"
  template_id="$(str_uci sub_convert_template 'ACL4SSR_Online_Mini_MultiMode.ini')"
  custom_template="$(str_uci sub_convert_custom_template_url '')"
  emoji="$(str_uci sub_convert_emoji true)"
  udp="$(str_uci sub_convert_udp true)"
  sort="$(str_uci sub_convert_sort false)"
  skip_verify="$(str_uci sub_convert_skip_cert_verify false)"
  append_type="$(str_uci sub_convert_append_node_type true)"

  if [ "$template_id" = 'custom' ] && [ -n "$custom_template" ]; then
    template_name='自定义模板'
    template_url="$custom_template"
  else
    template_info="$(template_lookup "$template_id" 2>/dev/null || true)"
    template_name="${template_info%%|*}"
    template_url="${template_info#*|}"
    [ "$template_info" = "$template_name" ] && template_url=''
  fi

  recommended_id="$(recommended_template)"
  recommended_info="$(template_lookup "$recommended_id" 2>/dev/null || true)"
  recommended_name="${recommended_info%%|*}"
  recommended_url="${recommended_info#*|}"
  [ "$recommended_info" = "$recommended_name" ] && recommended_url=''

  source_valid="$(subconvert_source_format_valid "$source")"
  backend_probe="$(http_fetch_quick "${backend_origin}/version")"
  if [ -n "$backend_probe" ] && printf '%s' "$backend_probe" | grep -qi 'version'; then
    backend_ready=true
    backend_status_text='本地转换后端已连通'
  elif [ -n "$backend_probe" ]; then
    backend_ready=true
    backend_status_text='本地转换后端可访问'
  else
    backend_ready=false
    backend_status_text='暂时没连上本地转换后端'
  fi

  if [ -z "$source" ]; then
    source_status_text='还没有填写原始订阅地址'
  elif [ "$source_valid" = true ]; then
    source_status_text='原始订阅链接格式看起来正常'
  else
    source_status_text='原始订阅格式不对，建议检查是否以 http:// 或 https:// 开头'
  fi

  source_probe_kind='unknown'
  source_probe_text='还没有开始检测订阅内容。'
  source_probe_sample='-'
  source_detected_as='未检测'
  if [ "$source_valid" = true ] && [ "$quick" != true ]; then
    source_probe="$(subconvert_probe_source "$source")"
    source_probe_kind="$(printf '%s' "$source_probe" | cut -f1)"
    source_probe_text="$(printf '%s' "$source_probe" | cut -f2)"
    source_probe_sample="$(printf '%s' "$source_probe" | cut -f3-)"
    case "$source_probe_kind" in
      yaml) source_detected_as='Clash / Mihomo 配置' ;;
      nodes) source_detected_as='节点订阅' ;;
      base64) source_detected_as='Base64 节点订阅' ;;
      html) source_detected_as='疑似网页 / 登录页' ;;
      *) source_detected_as='未识别格式' ;;
    esac
    if [ "$source_probe_kind" = 'html' ]; then
      source_status_text='订阅链接能打开，但返回内容更像网页或登录页，建议重新检查订阅地址。'
    elif [ "$source_probe_kind" = 'yaml' ] || [ "$source_probe_kind" = 'nodes' ] || [ "$source_probe_kind" = 'base64' ]; then
      source_status_text='订阅内容看起来正常，可以继续转换和导入。'
    fi
  elif [ "$source_valid" = true ]; then
    source_probe_kind='skipped'
    source_probe_text='首屏已跳过远程订阅内容探测，避免页面加载过久。进入订阅页后再按需判断内容类型。'
    source_probe_sample='-'
    source_detected_as='等待进一步检测'
  fi

  if [ -n "$template_url" ]; then
    template_status_text="当前模板可用，建议优先使用 ${template_name:-当前模板}"
    template_ready=true
  else
    template_status_text='当前还没有匹配到有效模板'
    template_ready=false
  fi

  if [ "$enabled" = true ]; then
    should_convert_text='建议先转换再导入，这样更适合小白使用，也更容易生成 AI、流媒体和自动切换相关分组。'
  else
    should_convert_text='当前未启用转换。除非你明确知道原始配置已经很完整，否则仍建议先转换再导入。'
  fi

  source_ready=false
  [ -n "$source" ] && [ "$source_valid" = true ] && source_ready=true

  if [ "$source_ready" = true ] && [ "$backend_ready" = true ] && [ "$template_ready" = true ]; then
    next_step='订阅、后端和模板都准备好了。可以直接打开下方转换页，确认无误后再一键写入 OpenClash。'
  elif [ "$source_ready" != true ]; then
    next_step='先粘贴原始订阅地址并保存，再继续做模板选择和导入。'
  elif [ "$source_probe_kind" = 'html' ]; then
    next_step='先修正订阅地址，确保拿到的不是网页或登录页，再继续转换和导入。'
  elif [ "$template_ready" != true ]; then
    next_step='先确认模板是否匹配，再继续转换和导入。'
  else
    next_step='先确认本地转换后端已经正常启动，再继续转换订阅。'
  fi

  history_count="$(uci -q show openclash 2>/dev/null | sed -n "s/^openclash\.\([^=]*\)=config_subscribe$/\1/p" | wc -l | tr -d ' ')"
  history_json="$(subconvert_history_json)"
  if [ "${history_count:-0}" -gt 0 ]; then
    history_label="已识别 ${history_count} 条历史订阅"
  else
    history_label='还没有识别到历史订阅'
  fi

  expected_groups_text='国内直连、国际常用、AI、流媒体、下载更新'
  expected_domestic='国内常见网站默认直连，优先保证日常网页、支付、办公和本地服务稳定。'
  expected_international='国外常用网站默认走代理分组，适合日常浏览和基础外网访问。'
  expected_ai='AI 服务建议单独走 AI 或国际稳定分组，优先换到更适合 AI 的地区节点。'
  expected_streaming='流媒体建议单独走视频分组，优先保证地区匹配和长期可用性。'
  expected_download='下载、更新和开发镜像建议走更稳定的国际分组，避免和 AI、流媒体互相影响。'

  case "$template_id" in
    Custom_Clash_Lite.ini)
      expected_groups_text='国内直连、国际常用、AI、流媒体'
      expected_download='轻量模板会更偏稳妥，下载和更新通常跟随国际常用分组，不做过度拆分。'
    ;;
    Custom_Clash_Full.ini|ACL4SSR_Online_Full_MultiMode.ini)
      expected_groups_text='国内直连、国际常用、AI、流媒体、下载更新、更多细分分组'
      expected_download='重度分流模板通常会把下载、更新、开发站点拆得更细，更适合爱折腾或售后精细化交付。'
    ;;
  esac

  source_hint='已生成项目内置的 sub-web-modify 页面入口，支持继续在完整前端里调整参数。'
  convert_url=''
  frontend_url="${frontend_base}?backend=$(urlencode "$backend_origin")"
  if [ -n "$source" ]; then
    encoded_source="$(urlencode "$source")"
    frontend_url="${frontend_url}&target=clash&url=${encoded_source}"
  fi
  if [ -n "$template_url" ]; then
    encoded_template="$(urlencode "$template_url")"
    frontend_url="${frontend_url}&config=${encoded_template}"
  fi
  if [ -n "$source" ] && [ -n "$template_url" ]; then
    convert_url="${backend_api}?target=clash&new_name=true&url=${encoded_source}&config=${encoded_template}&emoji=${emoji}&list=false&sort=${sort}"
    [ "$udp" = 'true' ] && convert_url="${convert_url}&udp=true"
    convert_url="${convert_url}&scv=${skip_verify}&append_type=${append_type}&fdn=true"
    source_hint='已生成项目内置 sub-web-modify 页面，并预填当前后端、订阅地址和模板。'
  else
    source_hint='已生成项目内置 sub-web-modify 页面入口；填写原始订阅地址并保存后，会继续自动带入订阅和模板参数。'
  fi

  commands="sid=\$(uci add openclash config_subscribe)\n"
  commands="$commands""uci set openclash.\$sid.enabled='1'\n"
  commands="$commands""uci set openclash.\$sid.name='助手生成订阅'\n"
  commands="$commands""uci set openclash.\$sid.address=$(shell_single_quote "$source")\n"
  commands="$commands""uci set openclash.\$sid.sub_convert='$( [ "$enabled" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.\$sid.convert_address=$(shell_single_quote "$backend_api")\n"
  commands="$commands""uci set openclash.\$sid.template=$(shell_single_quote "$template_id")\n"
  [ -n "$custom_template" ] && commands="$commands""uci set openclash.\$sid.custom_template_url=$(shell_single_quote "$custom_template")\n"
  commands="$commands""uci set openclash.\$sid.emoji=$(shell_single_quote "$emoji")\n"
  commands="$commands""uci set openclash.\$sid.udp=$(shell_single_quote "$udp")\n"
  commands="$commands""uci set openclash.\$sid.sort=$(shell_single_quote "$sort")\n"
  commands="$commands""uci set openclash.\$sid.skip_cert_verify=$(shell_single_quote "$skip_verify")\n"
  commands="$commands""uci set openclash.\$sid.node_type=$(shell_single_quote "$append_type")\n"
  commands="$commands""uci commit openclash"

  printf '{\n'
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "backend": "%s",\n' "$(json_string "$backend_origin")"
  printf '  "backend_api": "%s",\n' "$(json_string "$backend_api")"
  printf '  "backend_origin": "%s",\n' "$(json_string "$backend_origin")"
  printf '  "frontend_url": "%s",\n' "$(json_string "$frontend_url")"
  printf '  "template_id": "%s",\n' "$(json_string "$template_id")"
  printf '  "template_name": "%s",\n' "$(json_string "${template_name:-未匹配到模板}")"
  printf '  "template_url": "%s",\n' "$(json_string "$template_url")"
  printf '  "recommended_template_id": "%s",\n' "$(json_string "$recommended_id")"
  printf '  "recommended_template_name": "%s",\n' "$(json_string "$recommended_name")"
  printf '  "recommended_template_url": "%s",\n' "$(json_string "$recommended_url")"
  printf '  "source": "%s",\n' "$(json_string "$source")"
  printf '  "source_valid": %s,\n' "$source_valid"
  printf '  "source_status_text": "%s",\n' "$(json_string "$source_status_text")"
  printf '  "source_probe_kind": "%s",\n' "$(json_string "$source_probe_kind")"
  printf '  "source_probe_text": "%s",\n' "$(json_string "$source_probe_text")"
  printf '  "source_probe_sample": "%s",\n' "$(json_string "$source_probe_sample")"
  printf '  "source_detected_as": "%s",\n' "$(json_string "$source_detected_as")"
  printf '  "backend_ready": %s,\n' "$backend_ready"
  printf '  "backend_status_text": "%s",\n' "$(json_string "$backend_status_text")"
  printf '  "template_status_text": "%s",\n' "$(json_string "$template_status_text")"
  printf '  "should_convert_text": "%s",\n' "$(json_string "$should_convert_text")"
  printf '  "next_step": "%s",\n' "$(json_string "$next_step")"
  printf '  "expected_groups_text": "%s",\n' "$(json_string "$expected_groups_text")"
  printf '  "expected_domestic": "%s",\n' "$(json_string "$expected_domestic")"
  printf '  "expected_international": "%s",\n' "$(json_string "$expected_international")"
  printf '  "expected_ai": "%s",\n' "$(json_string "$expected_ai")"
  printf '  "expected_streaming": "%s",\n' "$(json_string "$expected_streaming")"
  printf '  "expected_download": "%s",\n' "$(json_string "$expected_download")"
  printf '  "history_count": %s,\n' "${history_count:-0}"
  printf '  "history_label": "%s",\n' "$(json_string "$history_label")"
  printf '  "emoji": "%s",\n' "$(json_string "$emoji")"
  printf '  "udp": "%s",\n' "$(json_string "$udp")"
  printf '  "sort": "%s",\n' "$(json_string "$sort")"
  printf '  "skip_cert_verify": "%s",\n' "$(json_string "$skip_verify")"
  printf '  "append_node_type": "%s",\n' "$(json_string "$append_type")"
  printf '  "convert_url": "%s",\n' "$(json_string "$convert_url")"
  printf '  "hint": "%s",\n' "$(json_string "$source_hint")"
  printf '  "commands": "%s",\n' "$(json_string "$commands")"
  printf '  "history": [\n%b\n  ]\n' "$history_json"
  printf '}\n'
}

find_subscribe_section_by_name() {
  local target="$1"
  local sid current_name
  for sid in $(uci -q show openclash 2>/dev/null | sed -n "s/^openclash\.\([^=]*\)=config_subscribe$/\1/p"); do
    current_name="$(uci -q get openclash."$sid".name 2>/dev/null || true)"
    if [ "$current_name" = "$target" ]; then
      printf '%s\n' "$sid"
      return 0
    fi
  done
  return 1
}

find_first_subscribe_section() {
  local sid
  for sid in $(uci -q show openclash 2>/dev/null | sed -n "s/^openclash\.\([^=]*\)=config_subscribe$/\1/p"); do
    printf '%s\n' "$sid"
    return 0
  done
  return 1
}

apply_auto_switch() {
  local enabled goal logic interval scope latency_threshold packet_loss_threshold fail_threshold revert_preferred expand_group close_con restart_result

  enabled="$(bool_uci_01 auto_switch_enabled 1)"
  goal="$(str_uci auto_switch_goal stability)"
  logic="$(str_uci auto_switch_logic urltest)"
  interval="$(str_uci auto_switch_interval 30)"
  scope="$(str_uci auto_switch_scope same_group)"
  latency_threshold="$(str_uci auto_switch_latency_threshold 180)"
  packet_loss_threshold="$(str_uci auto_switch_packet_loss_threshold 20)"
  fail_threshold="$(str_uci auto_switch_fail_threshold 2)"
  revert_preferred="$(bool_uci_01 auto_switch_revert_preferred 1)"
  expand_group="$(bool_uci_01 auto_switch_expand_group 1)"
  close_con="$(bool_uci_01 auto_switch_close_con 1)"

  case "$goal" in
    speed|streaming|ai|game|stability) ;;
    *) goal='stability' ;;
  esac
  case "$logic" in
    urltest|random) ;;
    *) logic='urltest' ;;
  esac
  case "$scope" in
    same_region|same_group|global) ;;
    *) scope='same_group' ;;
  esac

  uci -q set openclash.config.stream_auto_select="$enabled"
  uci -q set openclash.config.stream_auto_select_interval="$interval"
  uci -q set openclash.config.stream_auto_select_logic="$logic"
  uci -q set openclash.config.stream_auto_select_expand_group="$expand_group"
  uci -q set openclash.config.stream_auto_select_close_con="$close_con"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_goal=$goal"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_scope=$scope"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_latency_threshold=$latency_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_packet_loss_threshold=$packet_loss_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_fail_threshold=$fail_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_revert_preferred=$revert_preferred"
  uci -q commit openclash
  uci -q commit "$CONFIG_NAME"

  if [ -x /etc/init.d/openclash ]; then
    /etc/init.d/openclash restart >/dev/null 2>&1 && restart_result='已重启 OpenClash' || restart_result='已写入配置，但重启 OpenClash 失败'
  else
    restart_result='已写入配置，但未检测到 OpenClash 服务脚本'
  fi

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已应用节点自动切换设置，${restart_result}。")"
  printf '}\n'
}

apply_subconvert() {
  local enabled source backend_origin backend_api template_id custom_template emoji udp sort skip_verify append_type sid name sub_convert_value multiple_hint update_result

  enabled="$(bool_uci sub_convert_enabled 1)"
  source="$(str_uci sub_convert_source '')"
  backend_origin="$(subconvert_backend_origin "$(str_uci sub_convert_backend 'http://127.0.0.1:25500')")"
  backend_api="$(subconvert_backend_api "$backend_origin")"
  template_id="$(str_uci sub_convert_template 'ACL4SSR_Online_Mini_MultiMode.ini')"
  custom_template="$(str_uci sub_convert_custom_template_url '')"
  emoji="$(str_uci sub_convert_emoji true)"
  udp="$(str_uci sub_convert_udp true)"
  sort="$(str_uci sub_convert_sort false)"
  skip_verify="$(str_uci sub_convert_skip_cert_verify false)"
  append_type="$(str_uci sub_convert_append_node_type true)"
  name='助手生成订阅'

  if [ -z "$source" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '请先在助手页面填写原始订阅地址，再执行一键写入。')"
    printf '}\n'
    return 0
  fi

  sid="$(find_subscribe_section_by_name "$name" 2>/dev/null || true)"
  [ -n "$sid" ] || sid="$(uci add openclash config_subscribe)"

  [ "$enabled" = true ] && sub_convert_value='1' || sub_convert_value='0'

  uci -q set openclash."$sid".enabled='1'
  uci -q set openclash."$sid".name="$name"
  uci -q set openclash."$sid".address="$source"
  uci -q set openclash."$sid".sub_ua='clash.meta'
  uci -q set openclash."$sid".sub_convert="$sub_convert_value"
  uci -q set openclash."$sid".convert_address="$backend_api"
  uci -q set openclash."$sid".template="$template_id"
  if [ "$template_id" = 'custom' ] && [ -n "$custom_template" ]; then
    uci -q set openclash."$sid".custom_template_url="$custom_template"
  else
    uci -q delete openclash."$sid".custom_template_url >/dev/null 2>&1 || true
  fi
  uci -q set openclash."$sid".emoji="$emoji"
  uci -q set openclash."$sid".udp="$udp"
  uci -q set openclash."$sid".sort="$sort"
  uci -q set openclash."$sid".skip_cert_verify="$skip_verify"
  uci -q set openclash."$sid".node_type="$append_type"
  uci -q set openclash."$sid".rule_provider='false'
  uci -q commit openclash

  if [ -x /usr/share/openclash/openclash.sh ]; then
    /usr/share/openclash/openclash.sh "$name" >/dev/null 2>&1 &
    update_result='已在后台触发 OpenClash 更新该订阅。'
  else
    update_result='已写入 OpenClash 订阅项，但未检测到自动更新脚本。'
  fi

  multiple_hint="已写入 OpenClash 订阅项。${update_result}"
  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "section": "%s",\n' "$(json_string "$sid")"
  printf '  "message": "%s"\n' "$(json_string "$multiple_hint")"
  printf '}\n'
}

apply_recommended_profile() {
  local role mode needs_ipv6 has_public uses_tailscale gaming low_maintenance
  local recommended_template_id preferred_mode config_tier auto_goal auto_interval auto_scope latency_threshold packet_loss_threshold fail_threshold

  role="$(str_uci routing_role bypass_router)"
  mode="$(str_uci preferred_mode auto)"
  needs_ipv6="$(bool_uci needs_ipv6 0)"
  has_public="$(bool_uci has_public_services 0)"
  uses_tailscale="$(bool_uci uses_tailscale 0)"
  gaming="$(bool_uci gaming_devices 0)"
  low_maintenance="$(bool_uci low_maintenance 1)"
  recommended_template_id="$(recommended_template)"

  preferred_mode='auto'
  config_tier='均衡配置'
  auto_goal='stability'
  auto_interval='30'
  auto_scope='same_group'
  latency_threshold='180'
  packet_loss_threshold='20'
  fail_threshold='2'

  if [ "$role" = 'bypass_router' ] && { [ "$has_public" = true ] || [ "$uses_tailscale" = true ] || [ "$gaming" = true ]; }; then
    preferred_mode='compatibility'
    config_tier='保守配置'
    auto_goal='stability'
    auto_interval='30'
    auto_scope='same_group'
    latency_threshold='220'
    packet_loss_threshold='25'
    fail_threshold='3'
  elif [ "$mode" = 'fake-ip' ] && [ "$needs_ipv6" = true ]; then
    preferred_mode='compatibility'
    config_tier='保守配置'
    auto_goal='stability'
    auto_interval='30'
    auto_scope='same_group'
    latency_threshold='220'
    packet_loss_threshold='25'
    fail_threshold='3'
  elif [ "$low_maintenance" = true ]; then
    preferred_mode='auto'
    config_tier='保守配置'
    auto_goal='stability'
    auto_interval='30'
    auto_scope='same_group'
    latency_threshold='180'
    packet_loss_threshold='20'
    fail_threshold='2'
  else
    preferred_mode='fake-ip'
    config_tier='激进优选配置'
    auto_goal='speed'
    auto_interval='10'
    auto_scope='same_region'
    latency_threshold='140'
    packet_loss_threshold='15'
    fail_threshold='1'
  fi

  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.preferred_mode=$preferred_mode"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_enabled=1"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_template=$recommended_template_id"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_enabled=1"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_goal=$auto_goal"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_interval=$auto_interval"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_scope=$auto_scope"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_latency_threshold=$latency_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_packet_loss_threshold=$packet_loss_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_fail_threshold=$fail_threshold"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.auto_switch_revert_preferred=1"
  uci -q commit "$CONFIG_NAME"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "config_tier": "%s",\n' "$(json_string "$config_tier")"
  printf '  "template_id": "%s",\n' "$(json_string "$recommended_template_id")"
  printf '  "preferred_mode": "%s",\n' "$(json_string "$preferred_mode")"
  printf '  "auto_goal": "%s",\n' "$(json_string "$auto_goal")"
  printf '  "message": "%s"\n' "$(json_string "已把助手配置应用为${config_tier}，并同步推荐模板、运行模式和自动切换参数。")"
  printf '}\n'
}

media_ai_json() {
  local enabled group_filter region_filter node_filter current_global current_logic current_openai current_netflix current_disney current_youtube current_prime current_bilibili selected summary suggestion commands live_running last_run_at success_count partial_count issue_count no_data_count cache_count assistant_count can_run_live_test key json_fields toggle_option filter_suffix selected_count progress_selected progress_completed target_label

  enabled="$(bool_uci media_ai_enabled 1)"
  group_filter="$(str_uci media_ai_group_filter '')"
  region_filter="$(str_uci media_ai_region_filter '')"
  node_filter="$(str_uci media_ai_node_filter '')"

  current_global="$(uci -q get openclash.config.stream_auto_select 2>/dev/null || echo 0)"
  current_logic="$(uci -q get openclash.config.stream_auto_select_logic 2>/dev/null || echo urltest)"
  current_openai="$(uci -q get openclash.config.stream_auto_select_openai 2>/dev/null || echo 0)"
  current_netflix="$(uci -q get openclash.config.stream_auto_select_netflix 2>/dev/null || echo 0)"
  current_disney="$(uci -q get openclash.config.stream_auto_select_disney 2>/dev/null || echo 0)"
  current_youtube="$(uci -q get openclash.config.stream_auto_select_ytb 2>/dev/null || echo 0)"
  current_prime="$(uci -q get openclash.config.stream_auto_select_prime_video 2>/dev/null || echo 0)"
  current_bilibili="$(uci -q get openclash.config.stream_auto_select_bilibili 2>/dev/null || echo 0)"

  selected=''
  selected_count=0
  for key in $(media_ai_target_keys); do
    [ "$(media_ai_target_enabled "$key")" = true ] || continue
    target_label="$(media_ai_target_label "$key")"
    if [ -n "$selected" ]; then
      selected="${selected}|${target_label}"
    else
      selected="${target_label}"
    fi
    selected_count=$((selected_count + 1))
  done
  selected="$(printf '%s' "$selected" | sed 's/|/, /g')"
  [ -z "$selected" ] && selected='未选择任何检测目标'

  live_running="$(media_ai_test_running)"
  last_run_at="$(media_ai_last_run_at)"
  can_run_live_test=false
  if { [ -x "$OPENCLASH_STREAMING_UNLOCK" ] || command_exists curl; }; then
    can_run_live_test=true
  fi
  success_count=0
  partial_count=0
  issue_count=0
  no_data_count=0
  cache_count=0
  assistant_count=0
  json_fields=''
  progress_selected="$(progress_state_value "$MEDIA_AI_PROGRESS_FILE" selected)"
  progress_completed="$(progress_state_value "$MEDIA_AI_PROGRESS_FILE" completed)"

  for key in $(media_ai_target_keys); do
    set_media_ai_target_state "$key"

    case "$MEDIA_AI_TARGET_STATUS" in
      reachable|available|full_support) success_count=$((success_count + 1)) ;;
      other_region|homemade_only) partial_count=$((partial_count + 1)) ;;
      restricted|no_unlock|blocked|failed) issue_count=$((issue_count + 1)) ;;
      no_data) no_data_count=$((no_data_count + 1)) ;;
    esac
    [ "$MEDIA_AI_TARGET_SOURCE" = 'assistant_test' ] && assistant_count=$((assistant_count + 1))

    json_fields="${json_fields}  \"${key}_enabled\": ${MEDIA_AI_TARGET_ENABLED},\n"
    json_fields="${json_fields}  \"${key}_status\": \"$(json_string "$MEDIA_AI_TARGET_STATUS")\",\n"
    json_fields="${json_fields}  \"${key}_status_text\": \"$(json_string "$MEDIA_AI_TARGET_STATUS_TEXT")\",\n"
    json_fields="${json_fields}  \"${key}_tone\": \"$(json_string "$MEDIA_AI_TARGET_TONE")\",\n"
    json_fields="${json_fields}  \"${key}_region\": \"$(json_string "$MEDIA_AI_TARGET_REGION")\",\n"
    json_fields="${json_fields}  \"${key}_node\": \"$(json_string "$MEDIA_AI_TARGET_NODE")\",\n"
    json_fields="${json_fields}  \"${key}_tested_at\": \"$(json_string "$MEDIA_AI_TARGET_TESTED_AT")\",\n"
    json_fields="${json_fields}  \"${key}_source\": \"$(json_string "$MEDIA_AI_TARGET_SOURCE")\",\n"
    json_fields="${json_fields}  \"${key}_source_text\": \"$(json_string "$MEDIA_AI_TARGET_SOURCE_TEXT")\",\n"
    json_fields="${json_fields}  \"${key}_latency_ms\": \"$(json_string "$MEDIA_AI_TARGET_LATENCY_MS")\",\n"
    json_fields="${json_fields}  \"${key}_http_code\": \"$(json_string "$MEDIA_AI_TARGET_HTTP_CODE")\",\n"
    json_fields="${json_fields}  \"${key}_dns_state\": \"$(json_string "$MEDIA_AI_TARGET_DNS_STATE")\",\n"
    json_fields="${json_fields}  \"${key}_tls_state\": \"$(json_string "$MEDIA_AI_TARGET_TLS_STATE")\",\n"
    json_fields="${json_fields}  \"${key}_http_state\": \"$(json_string "$MEDIA_AI_TARGET_HTTP_STATE")\",\n"
    json_fields="${json_fields}  \"${key}_risk_hint\": \"$(json_string "$MEDIA_AI_TARGET_RISK_HINT")\",\n"
    json_fields="${json_fields}  \"${key}_recommended_region\": \"$(json_string "$MEDIA_AI_TARGET_RECOMMENDED_REGION")\",\n"
    json_fields="${json_fields}  \"${key}_long_term_fit\": \"$(json_string "$MEDIA_AI_TARGET_LONG_TERM_FIT")\",\n"
    json_fields="${json_fields}  \"${key}_native_text\": \"$(json_string "$MEDIA_AI_TARGET_NATIVE_TEXT")\",\n"
    json_fields="${json_fields}  \"${key}_diagnosis\": \"$(json_string "$MEDIA_AI_TARGET_DIAGNOSIS")\",\n"
    json_fields="${json_fields}  \"${key}_next_step\": \"$(json_string "$MEDIA_AI_TARGET_NEXT_STEP")\",\n"
    json_fields="${json_fields}  \"${key}_detail\": \"$(json_string "$MEDIA_AI_TARGET_DETAIL")\",\n"
  done

  if [ "$live_running" = true ]; then
    [ -n "$progress_selected" ] && selected_count="$progress_selected"
    [ -n "$progress_completed" ] && assistant_count="$progress_completed"
    summary="真实检测正在后台执行，当前已完成 ${assistant_count}/${selected_count} 项。完成后会一次性刷新全部结果。"
  elif [ -n "$last_run_at" ]; then
    summary="下面展示的是最近一次助手真实检测结果（${last_run_at}）。"
  else
    summary='暂无访问检查结果。页面会按当前已启用的流媒体 / AI 目标执行访问检查。'
  fi

  if [ "$issue_count" -gt 0 ]; then
    suggestion='至少有一项当前显示访问受限或检测失败。可以先检查当前 OpenClash 出口节点、DNS 与分流策略。'
  elif [ "$no_data_count" -gt 0 ]; then
    suggestion='有些 AI 或流媒体目标还没有拿到最新结果，建议重新跑一次真实检测，把新增目标也补齐。'
  elif [ "$partial_count" -gt 0 ]; then
    suggestion='当前至少有一项仅能命中其他地区或仅支持自制剧，可以进一步收窄地区和节点关键字。'
  elif [ "$success_count" -gt 0 ]; then
    suggestion='当前访问检查结果正常，可以按延迟与 HTTP 返回码判断线路质量。'
  elif [ "$enabled" = true ]; then
    suggestion='正在准备访问检查结果。'
  else
    suggestion='访问检查当前未启用。'
  fi

  commands="uci set openclash.config.stream_auto_select='$( [ "$enabled" = true ] && echo 1 || echo 0 )'\n"
  for key in $(media_ai_target_keys); do
    [ "$(media_ai_target_probe_backend "$key")" = 'openclash' ] || continue
    toggle_option="$(media_ai_target_openclash_toggle_option "$key" 2>/dev/null || true)"
    filter_suffix="$(media_ai_target_openclash_filter_suffix "$key" 2>/dev/null || true)"
    [ -n "$toggle_option" ] || continue
    commands="$commands""uci set openclash.config.${toggle_option}='$(bool_uci_01 "$(media_ai_target_assistant_option "$key")" 0)'\n"

    if [ -n "$filter_suffix" ]; then
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$group_filter" ]; then
        commands="$commands""uci set openclash.config.stream_auto_select_group_key_${filter_suffix}=$(shell_single_quote "$group_filter")\n"
      else
        commands="$commands""uci -q delete openclash.config.stream_auto_select_group_key_${filter_suffix} >/dev/null 2>&1 || true\n"
      fi
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$region_filter" ]; then
        commands="$commands""uci set openclash.config.stream_auto_select_region_key_${filter_suffix}=$(shell_single_quote "$region_filter")\n"
      else
        commands="$commands""uci -q delete openclash.config.stream_auto_select_region_key_${filter_suffix} >/dev/null 2>&1 || true\n"
      fi
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$node_filter" ]; then
        commands="$commands""uci set openclash.config.stream_auto_select_node_key_${filter_suffix}=$(shell_single_quote "$node_filter")\n"
      else
        commands="$commands""uci -q delete openclash.config.stream_auto_select_node_key_${filter_suffix} >/dev/null 2>&1 || true\n"
      fi
    fi
  done

  commands="$commands""uci commit openclash\n/etc/init.d/openclash restart"

  printf '{\n'
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "test_running": %s,\n' "$live_running"
  printf '  "can_run_live_test": %s,\n' "$can_run_live_test"
  printf '  "last_run_at": "%s",\n' "$(json_string "$last_run_at")"
  printf '  "selected": "%s",\n' "$(json_string "$selected")"
  printf '  "summary": "%s",\n' "$(json_string "$summary")"
  printf '  "suggestion": "%s",\n' "$(json_string "$suggestion")"
  printf '  "group_filter": "%s",\n' "$(json_string "$group_filter")"
  printf '  "region_filter": "%s",\n' "$(json_string "$region_filter")"
  printf '  "node_filter": "%s",\n' "$(json_string "$node_filter")"
  printf '  "current_global": "%s",\n' "$(json_string "$current_global")"
  printf '  "current_logic": "%s",\n' "$(json_string "$current_logic")"
  printf '  "current_netflix": "%s",\n' "$(json_string "$current_netflix")"
  printf '  "current_disney": "%s",\n' "$(json_string "$current_disney")"
  printf '  "current_youtube": "%s",\n' "$(json_string "$current_youtube")"
  printf '  "current_prime_video": "%s",\n' "$(json_string "$current_prime")"
  printf '  "current_bilibili": "%s",\n' "$(json_string "$current_bilibili")"
  printf '  "current_openai": "%s",\n' "$(json_string "$current_openai")"
  printf '  "success_count": %s,\n' "$success_count"
  printf '  "partial_count": %s,\n' "$partial_count"
  printf '  "issue_count": %s,\n' "$issue_count"
  printf '  "no_data_count": %s,\n' "$no_data_count"
  printf '  "selected_count": %s,\n' "$selected_count"
  printf '  "completed_count": %s,\n' "$assistant_count"
  printf '  "cache_count": %s,\n' "$cache_count"
  printf '  "assistant_test_count": %s,\n' "$assistant_count"
  printf '%b' "$json_fields"
  printf '  "commands": "%s"\n' "$(json_string "$commands")"
  printf '}\n'
}

run_media_ai_live_test() {
  local running count key message require_openclash require_api completed now

  require_openclash=false
  require_api=false

  running="$(media_ai_test_running)"
  if [ "$running" = true ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '已有一轮真实检测正在后台执行，请稍后刷新页面查看结果。')"
    printf '}\n'
    return 0
  fi

  count=0
  for key in $(media_ai_target_keys); do
    [ "$(media_ai_target_enabled "$key")" = true ] || continue
    count=$((count + 1))
    case "$(media_ai_target_probe_backend "$key")" in
      openclash) require_openclash=true ;;
      official_api) require_api=true ;;
    esac
  done

  if [ "$count" -eq 0 ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '当前没有勾选任何流媒体 / AI 检测目标。')"
    printf '}\n'
    return 0
  fi

  if [ "$require_openclash" = true ] && [ ! -x "$OPENCLASH_STREAMING_UNLOCK" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '已勾选流媒体或 OpenAI 检测，但未检测到 OpenClash 真实解锁检测脚本。')"
    printf '}\n'
    return 0
  fi

  if [ "$require_openclash" = true ] && [ "$(service_running)" != true ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '已勾选流媒体或 OpenAI 检测，但 OpenClash 当前未运行，无法发起对应实测。')"
    printf '}\n'
    return 0
  fi

  if [ "$require_api" = true ] && ! command_exists curl; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '已勾选 Claude 或 Gemini 检测，但系统缺少 curl，无法发起官方 API 探测。')"
    printf '}\n'
    return 0
  fi

  (
    trap 'rm -f "$MEDIA_AI_RUN_PID_FILE" "$MEDIA_AI_PROGRESS_FILE" "${MEDIA_AI_RESULT_FILE}.tmp"' EXIT INT TERM
    : > "${MEDIA_AI_RESULT_FILE}.tmp"
    completed=0
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    write_progress_state "$MEDIA_AI_PROGRESS_FILE" "$count" 0 "$now"

    for key in $(media_ai_target_keys); do
      [ "$(media_ai_target_enabled "$key")" = true ] || continue
      message="$(run_media_ai_target_probe "$key")"
      printf '%s\t%s\t%s\n' "$key" "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "${MEDIA_AI_RESULT_FILE}.tmp"
      completed=$((completed + 1))
      write_progress_state "$MEDIA_AI_PROGRESS_FILE" "$count" "$completed" "$now"
    done

    mv "${MEDIA_AI_RESULT_FILE}.tmp" "$MEDIA_AI_RESULT_FILE"
  ) >/dev/null 2>&1 &

  printf '%s\n' "$!" > "$MEDIA_AI_RUN_PID_FILE"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已在后台启动 ${count} 项真实检测。检测过程中 OpenClash 可能会短暂切换策略组，请稍后刷新页面查看结果。")"
  printf '}\n'
}

apply_media_ai() {
  local group_filter region_filter node_filter restart_result key toggle_option filter_suffix

  group_filter="$(str_uci media_ai_group_filter '')"
  region_filter="$(str_uci media_ai_region_filter '')"
  node_filter="$(str_uci media_ai_node_filter '')"

  uci -q set openclash.config.stream_auto_select="$(bool_uci_01 media_ai_enabled 1)"
  for key in $(media_ai_target_keys); do
    [ "$(media_ai_target_probe_backend "$key")" = 'openclash' ] || continue
    toggle_option="$(media_ai_target_openclash_toggle_option "$key" 2>/dev/null || true)"
    filter_suffix="$(media_ai_target_openclash_filter_suffix "$key" 2>/dev/null || true)"
    [ -n "$toggle_option" ] || continue

    uci -q set openclash.config."$toggle_option"="$(bool_uci_01 "$(media_ai_target_assistant_option "$key")" 0)"

    if [ -n "$filter_suffix" ]; then
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$group_filter" ]; then
        uci -q set openclash.config."stream_auto_select_group_key_${filter_suffix}"="$group_filter"
      else
        uci -q delete openclash.config."stream_auto_select_group_key_${filter_suffix}" >/dev/null 2>&1 || true
      fi
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$region_filter" ]; then
        uci -q set openclash.config."stream_auto_select_region_key_${filter_suffix}"="$region_filter"
      else
        uci -q delete openclash.config."stream_auto_select_region_key_${filter_suffix}" >/dev/null 2>&1 || true
      fi
      if [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$node_filter" ]; then
        uci -q set openclash.config."stream_auto_select_node_key_${filter_suffix}"="$node_filter"
      else
        uci -q delete openclash.config."stream_auto_select_node_key_${filter_suffix}" >/dev/null 2>&1 || true
      fi
    fi
  done
  uci -q commit openclash

  if [ -x /etc/init.d/openclash ]; then
    /etc/init.d/openclash restart >/dev/null 2>&1 && restart_result='已重启 OpenClash' || restart_result='已写入配置，但重启 OpenClash 失败'
  else
    restart_result='已写入配置，但未检测到 OpenClash 服务脚本'
  fi

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已应用流媒体 / AI 检测设置，${restart_result}。")"
  printf '}\n'
}

sync_media_ai_from_openclash() {
  local global group_filter region_filter node_filter key toggle_option filter_suffix

  global="$(uci -q get openclash.config.stream_auto_select 2>/dev/null || echo 0)"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.media_ai_enabled=$( [ "$global" = '1' ] && echo 1 || echo 0 )"
  for key in $(media_ai_target_keys); do
    [ "$(media_ai_target_probe_backend "$key")" = 'openclash' ] || continue
    toggle_option="$(media_ai_target_openclash_toggle_option "$key" 2>/dev/null || true)"
    [ -n "$toggle_option" ] || continue
    uci -q set "$CONFIG_NAME.$CONFIG_SECTION.$(media_ai_target_assistant_option "$key")=$(uci -q get openclash.config.${toggle_option} 2>/dev/null || echo 0)"
  done

  group_filter=''
  region_filter=''
  node_filter=''
  for key in openai netflix disney youtube prime_video hbo_max dazn paramount_plus discovery_plus tvb_anywhere bilibili; do
    filter_suffix="$(media_ai_target_openclash_filter_suffix "$key" 2>/dev/null || true)"
    [ -n "$filter_suffix" ] || continue
    [ -n "$group_filter" ] || group_filter="$(uci -q get openclash.config.stream_auto_select_group_key_${filter_suffix} 2>/dev/null || echo '')"
    [ -n "$region_filter" ] || region_filter="$(uci -q get openclash.config.stream_auto_select_region_key_${filter_suffix} 2>/dev/null || echo '')"
    [ -n "$node_filter" ] || node_filter="$(uci -q get openclash.config.stream_auto_select_node_key_${filter_suffix} 2>/dev/null || echo '')"
  done

  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.media_ai_group_filter=$group_filter"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.media_ai_region_filter=$region_filter"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.media_ai_node_filter=$node_filter"
  uci -q commit "$CONFIG_NAME"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string '已从 OpenClash 导入当前流媒体 / AI 检测配置。')"
  printf '}\n'
}

sync_subconvert_section_internal() {
  local sid="$1"
  local name address sub_convert backend_origin template custom_template emoji udp sort skip_verify node_type

  [ -n "$sid" ] || return 1
  if ! uci -q get openclash."$sid" >/dev/null 2>&1; then
    return 1
  fi

  name="$(uci -q get openclash."$sid".name 2>/dev/null || echo '')"
  address="$(uci -q get openclash."$sid".address 2>/dev/null || echo '')"
  sub_convert="$(uci -q get openclash."$sid".sub_convert 2>/dev/null || echo 0)"
  backend_origin="$(subconvert_backend_origin "$(uci -q get openclash."$sid".convert_address 2>/dev/null || echo 'http://127.0.0.1:25500/sub')")"
  template="$(uci -q get openclash."$sid".template 2>/dev/null || echo 'ACL4SSR_Online_Mini_MultiMode.ini')"
  custom_template="$(uci -q get openclash."$sid".custom_template_url 2>/dev/null || echo '')"
  emoji="$(uci -q get openclash."$sid".emoji 2>/dev/null || echo 'true')"
  udp="$(uci -q get openclash."$sid".udp 2>/dev/null || echo 'true')"
  sort="$(uci -q get openclash."$sid".sort 2>/dev/null || echo 'false')"
  skip_verify="$(uci -q get openclash."$sid".skip_cert_verify 2>/dev/null || echo 'false')"
  node_type="$(uci -q get openclash."$sid".node_type 2>/dev/null || echo 'true')"

  [ "$template" = '0' ] && template='custom'

  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_enabled=$( [ "$sub_convert" = '1' ] && echo 1 || echo 0 )"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_source=$address"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_backend=$backend_origin"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_template=$template"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_custom_template_url=$custom_template"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_emoji=$emoji"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_udp=$udp"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_sort=$sort"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_skip_cert_verify=$skip_verify"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_append_node_type=$node_type"
  uci -q commit "$CONFIG_NAME"

  printf '%s\n' "${name:-未命名}"
}

sync_subconvert_from_openclash() {
  local sid name

  sid="$(find_first_subscribe_section 2>/dev/null || true)"
  if [ -z "$sid" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '未找到现有的 OpenClash 订阅项，无法导入。')"
    printf '}\n'
    return 0
  fi

  name="$(sync_subconvert_section_internal "$sid" 2>/dev/null || true)"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已从 OpenClash 现有订阅【${name:-未命名}】导入参数到助手页面。")"
  printf '}\n'
}

sync_subconvert_section_from_openclash() {
  local sid name
  sid="${2:-}"
  if [ -z "$sid" ]; then
    sid="${1:-}"
  fi

  if [ -z "$sid" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '缺少订阅标识，无法按条导入。')"
    printf '}\n'
    return 0
  fi

  name="$(sync_subconvert_section_internal "$sid" 2>/dev/null || true)"
  if [ -z "$name" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '没有找到你指定的历史订阅。')"
    printf '}\n'
    return 0
  fi

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已按条导入历史订阅【${name}】到助手页面。")"
  printf '}\n'
}

restart_openclash() {
  local result
  if [ ! -x /etc/init.d/openclash ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '未检测到 OpenClash 服务脚本，无法自动恢复基础服务。')"
    printf '}\n'
    return 0
  fi

  /etc/init.d/openclash enable >/dev/null 2>&1 || true
  if /etc/init.d/openclash restart >/dev/null 2>&1; then
    result='已尝试重启 OpenClash，基础服务恢复成功。'
  else
    result='已尝试重启 OpenClash，但恢复失败，请继续检查配置和日志。'
  fi

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "$result")"
  printf '}\n'
}

auto_fix_basic() {
  local status flush auto subconvert running dns_level auto_enabled current_auto_enabled sub_source sub_enabled
  local need_restart steps fixed_any auto_logic auto_interval auto_expand auto_close result

  status="$(status_json)"
  flush="$(flush_dns_json)"
  auto="$(auto_switch_json)"
  subconvert="$(subconvert_json)"

  running="$(json_find_bool "$status" running)"
  dns_level="$(json_find_string "$flush" dns_diag_level)"
  auto_enabled="$(json_find_bool "$auto" enabled)"
  current_auto_enabled="$(json_find_string "$auto" current_enabled)"
  sub_source="$(json_find_string "$subconvert" source)"
  sub_enabled="$(json_find_bool "$subconvert" enabled)"

  need_restart=false
  fixed_any=false
  steps=''

  if [ "$dns_level" != 'good' ]; then
    if [ -x /etc/init.d/dnsmasq ]; then
      /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
      steps="${steps}已刷新 dnsmasq；"
      fixed_any=true
    fi
    if [ -x /etc/init.d/smartdns ]; then
      /etc/init.d/smartdns restart >/dev/null 2>&1 || true
      steps="${steps}已刷新 smartdns；"
      fixed_any=true
    fi
  fi

  if [ -n "$sub_source" ] && [ "$sub_enabled" != 'true' ]; then
    uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_enabled=1"
    uci -q commit "$CONFIG_NAME"
    steps="${steps}已启用订阅转换；"
    fixed_any=true
  fi

  if [ "$auto_enabled" = 'true' ] && [ "$current_auto_enabled" != '1' ]; then
    auto_logic="$(str_uci auto_switch_logic urltest)"
    auto_interval="$(str_uci auto_switch_interval 30)"
    auto_expand="$(bool_uci_01 auto_switch_expand_group 1)"
    auto_close="$(bool_uci_01 auto_switch_close_con 1)"
    uci -q set openclash.config.stream_auto_select='1'
    uci -q set openclash.config.stream_auto_select_logic="$auto_logic"
    uci -q set openclash.config.stream_auto_select_interval="$auto_interval"
    uci -q set openclash.config.stream_auto_select_expand_group="$auto_expand"
    uci -q set openclash.config.stream_auto_select_close_con="$auto_close"
    uci -q commit openclash
    steps="${steps}已应用自动切换；"
    fixed_any=true
    need_restart=true
  fi

  if [ "$running" != 'true' ]; then
    need_restart=true
  fi

  if [ "$need_restart" = true ] && [ -x /etc/init.d/openclash ]; then
    /etc/init.d/openclash enable >/dev/null 2>&1 || true
    /etc/init.d/openclash restart >/dev/null 2>&1 || true
    steps="${steps}已尝试恢复 OpenClash；"
    fixed_any=true
  fi

  if [ "$fixed_any" = true ]; then
    result="已自动处理这些项目：$(printf '%s' "$steps" | sed 's/；$//')。建议 5 到 10 秒后重新跑一键体检确认结果。"
  else
    result='当前没有发现适合自动修复的基础项目。建议按体检卡片逐项处理。'
  fi

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "$result")"
  printf '}\n'
}

flush_dns_json() {
  local dnsmasq_available dnsmasq_running smartdns_available smartdns_running openclash_running last_run_at last_status last_message dnsmasq_full dns_diag_line_value dns_chain dns_diag_code dns_diag_level dns_diag_summary dns_diag_action

  [ -x /etc/init.d/dnsmasq ] && dnsmasq_available=true || dnsmasq_available=false
  dnsmasq_running="$(service_running_named dnsmasq)"
  [ -x /etc/init.d/smartdns ] && smartdns_available=true || smartdns_available=false
  smartdns_running="$(service_running_named smartdns)"
  openclash_running="$(service_running)"
  last_run_at="$(flush_dns_state_value last_run_at)"
  last_status="$(flush_dns_state_value status)"
  last_message="$(flush_dns_state_value message)"
  package_installed dnsmasq-full && dnsmasq_full=true || dnsmasq_full=false
  dns_diag_line_value="$(dns_diag_line "$openclash_running" "$dnsmasq_running" "$smartdns_available" "$smartdns_running" "$dnsmasq_full")"
  dns_chain="$(printf '%s' "$dns_diag_line_value" | cut -f1)"
  dns_diag_code="$(printf '%s' "$dns_diag_line_value" | cut -f2)"
  dns_diag_level="$(printf '%s' "$dns_diag_line_value" | cut -f3)"
  dns_diag_summary="$(printf '%s' "$dns_diag_line_value" | cut -f4)"
  dns_diag_action="$(printf '%s' "$dns_diag_line_value" | cut -f5)"

  printf '{\n'
  printf '  "dnsmasq_available": %s,\n' "$dnsmasq_available"
  printf '  "dnsmasq_running": %s,\n' "$dnsmasq_running"
  printf '  "smartdns_available": %s,\n' "$smartdns_available"
  printf '  "smartdns_running": %s,\n' "$smartdns_running"
  printf '  "openclash_running": %s,\n' "$openclash_running"
  printf '  "last_run_at": "%s",\n' "$(json_string "$last_run_at")"
  printf '  "last_status": "%s",\n' "$(json_string "$last_status")"
  printf '  "last_message": "%s",\n' "$(json_string "$last_message")"
  printf '  "dns_chain": "%s",\n' "$(json_string "$dns_chain")"
  printf '  "dns_diag_code": "%s",\n' "$(json_string "$dns_diag_code")"
  printf '  "dns_diag_level": "%s",\n' "$(json_string "$dns_diag_level")"
  printf '  "dns_diag_summary": "%s",\n' "$(json_string "$dns_diag_summary")"
  printf '  "dns_diag_action": "%s",\n' "$(json_string "$dns_diag_action")"
  printf '  "hint": "%s"\n' "$(json_string '用于刷新本机 DNS 缓存。会优先重启 dnsmasq；如果系统启用了 smartdns，也会一并重启。')"
  printf '}\n'
}

flush_dns() {
  local steps status message now

  steps=''
  status='ok'
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  if [ -x /etc/init.d/dnsmasq ]; then
    if /etc/init.d/dnsmasq restart >/dev/null 2>&1; then
      steps='已重启 dnsmasq'
    else
      steps='dnsmasq 重启失败'
      status='error'
    fi
  else
    steps='未检测到 dnsmasq 服务脚本'
    status='error'
  fi

  if [ -x /etc/init.d/smartdns ]; then
    if /etc/init.d/smartdns restart >/dev/null 2>&1; then
      steps="${steps}；已重启 smartdns"
    else
      steps="${steps}；smartdns 重启失败"
      status='error'
    fi
  fi

  message="DNS 刷新完成。${steps}"
  write_flush_dns_state "$now" "$status" "$message"

  printf '{\n'
  printf '  "ok": %s,\n' "$( [ "$status" = 'ok' ] && echo true || echo false )"
  printf '  "message": "%s"\n' "$(json_string "$message")"
  printf '}\n'
}

split_tunnel_test_running() {
  local pid
  if [ ! -f "$SPLIT_TUNNEL_RUN_PID_FILE" ]; then
    echo false
    return 0
  fi

  pid="$(cat "$SPLIT_TUNNEL_RUN_PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo true
    return 0
  fi

  rm -f "$SPLIT_TUNNEL_RUN_PID_FILE"
  echo false
}

split_tunnel_result_line() {
  local key="$1"
  [ -r "$SPLIT_TUNNEL_RESULT_FILE" ] || return 1
  awk -F '\t' -v key="$key" '$1 == key { print; exit }' "$SPLIT_TUNNEL_RESULT_FILE"
}

split_tunnel_json() {
  local test_running last_run_at selected_count completed_count success_count issue_count key line tested_at detail status latency http_code exit_ip exit_country exit_colo json_fields summary

  test_running="$(split_tunnel_test_running)"
  last_run_at=''
  [ -r "$SPLIT_TUNNEL_RESULT_FILE" ] && last_run_at="$(awk -F '\t' 'END { if (NR > 0) print $2 }' "$SPLIT_TUNNEL_RESULT_FILE")"
  selected_count="$(printf '%s\n' "$(split_tunnel_target_keys)" | wc -l | tr -d ' ')"
  completed_count="$(progress_state_value "$SPLIT_TUNNEL_PROGRESS_FILE" completed)"
  [ -n "$completed_count" ] || completed_count=0
  success_count=0
  issue_count=0
  json_fields=''

  for key in $(split_tunnel_target_keys); do
    line="$(split_tunnel_result_line "$key" 2>/dev/null || true)"
    tested_at=''
    detail=''
    status='no_data'
    latency=''
    http_code=''
    exit_ip=''
    exit_country=''
    exit_colo=''

    if [ -n "$line" ]; then
      tested_at="$(printf '%s' "$line" | cut -f2)"
      detail="$(printf '%s' "$line" | cut -f3-)"
      status="$(media_ai_status_code_from_text "$detail")"
      latency="$(media_ai_extract_latency_ms "$detail")"
      http_code="$(media_ai_extract_http_code "$detail")"
      exit_ip="$(split_tunnel_extract_exit_ip "$detail")"
      exit_country="$(split_tunnel_extract_exit_country "$detail")"
      exit_colo="$(split_tunnel_extract_exit_colo "$detail")"
    fi

    case "$status" in
      reachable|available|full_support) success_count=$((success_count + 1)) ;;
      restricted|blocked|failed|no_unlock|other_region|homemade_only|unknown) issue_count=$((issue_count + 1)) ;;
    esac

    json_fields="${json_fields}  \"${key}_label\": \"$(json_string "$(split_tunnel_target_label "$key")")\",\n"
    json_fields="${json_fields}  \"${key}_group\": \"$(json_string "$(split_tunnel_target_group "$key")")\",\n"
    json_fields="${json_fields}  \"${key}_status\": \"$(json_string "$status")\",\n"
    json_fields="${json_fields}  \"${key}_status_text\": \"$(json_string "$(media_ai_status_label "$status")")\",\n"
    json_fields="${json_fields}  \"${key}_tone\": \"$(json_string "$(media_ai_status_tone "$status")")\",\n"
    json_fields="${json_fields}  \"${key}_latency_ms\": \"$(json_string "$latency")\",\n"
    json_fields="${json_fields}  \"${key}_http_code\": \"$(json_string "$http_code")\",\n"
    json_fields="${json_fields}  \"${key}_exit_ip\": \"$(json_string "$exit_ip")\",\n"
    json_fields="${json_fields}  \"${key}_exit_country\": \"$(json_string "$exit_country")\",\n"
    json_fields="${json_fields}  \"${key}_exit_colo\": \"$(json_string "$exit_colo")\",\n"
    json_fields="${json_fields}  \"${key}_tested_at\": \"$(json_string "$tested_at")\",\n"
    json_fields="${json_fields}  \"${key}_detail\": \"$(json_string "$detail")\",\n"
  done

  if [ "$test_running" = true ]; then
    summary='分流测试执行中，全部目标并发检测，完成后会一次性刷新全部结果。'
  elif [ -n "$last_run_at" ]; then
    summary="下面展示的是最近一次分流测试结果（${last_run_at}）。"
    completed_count="$selected_count"
  else
    summary='暂无分流测试结果。进入该标签页后会自动开始检测。'
  fi

  printf '{\n'
  printf '  "test_running": %s,\n' "$test_running"
  printf '  "last_run_at": "%s",\n' "$(json_string "$last_run_at")"
  printf '  "selected_count": %s,\n' "$selected_count"
  printf '  "completed_count": %s,\n' "$completed_count"
  printf '  "success_count": %s,\n' "$success_count"
  printf '  "issue_count": %s,\n' "$issue_count"
  printf '  "summary": "%s",\n' "$(json_string "$summary")"
  printf '%b' "$json_fields"
  printf '  "ok": true\n'
  printf '}\n'
}

run_split_tunnel_test() {
  local running count key message completed now exit_meta trace_url tmpdir idx pids file

  running="$(split_tunnel_test_running)"
  if [ "$running" = true ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '已有一轮分流测试正在后台执行，请稍后查看结果。')"
    printf '}\n'
    return 0
  fi

  count="$(printf '%s\n' "$(split_tunnel_target_keys)" | wc -l | tr -d ' ')"

  (
    tmpdir="$(mktemp -d /tmp/openclash-assistant-split.XXXXXX)"
    trap 'rm -f "$SPLIT_TUNNEL_RUN_PID_FILE" "$SPLIT_TUNNEL_PROGRESS_FILE" "${SPLIT_TUNNEL_RESULT_FILE}.tmp"; rm -rf "$tmpdir"' EXIT INT TERM
    : > "${SPLIT_TUNNEL_RESULT_FILE}.tmp"
    completed=0
    idx=0
    pids=''
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    write_progress_state "$SPLIT_TUNNEL_PROGRESS_FILE" "$count" 0 "$now"

    for key in $(split_tunnel_target_keys); do
      idx=$((idx + 1))
      file="$tmpdir/$(printf '%03d' "$idx")-${key}.tsv"
      (
        message="$(media_ai_site_probe "$(split_tunnel_target_url "$key")" "$(split_tunnel_target_label "$key")")"
        trace_url="$(split_tunnel_trace_url "$key" 2>/dev/null || true)"
        exit_meta="$(split_tunnel_probe_exit_identity "$trace_url" 2>/dev/null || true)"
        if [ -n "$exit_meta" ]; then
          message="${message}|${exit_meta}"
        fi
        printf '%s\t%s\t%s\n' "$key" "$(date '+%Y-%m-%d %H:%M:%S')" "$message" > "$file"
      ) >/dev/null 2>&1 &
      pids="$pids $!"
    done

    for pid in $pids; do
      wait "$pid" || true
    done

    for file in "$tmpdir"/*.tsv; do
      [ -f "$file" ] || continue
      cat "$file" >> "${SPLIT_TUNNEL_RESULT_FILE}.tmp"
      completed=$((completed + 1))
    done
    write_progress_state "$SPLIT_TUNNEL_PROGRESS_FILE" "$count" "$completed" "$now"

    mv "${SPLIT_TUNNEL_RESULT_FILE}.tmp" "$SPLIT_TUNNEL_RESULT_FILE"
  ) >/dev/null 2>&1 &

  printf '%s\n' "$!" > "$SPLIT_TUNNEL_RUN_PID_FILE"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已在后台启动 ${count} 项分流测试。完成后会一次性刷新全部结果。")"
  printf '}\n'
}

case "${1:-status-json}" in
  status-json) status_json ;;
  checkup-json) checkup_json ;;
  advice-json) advice_json ;;
  auto-switch-json) auto_switch_json ;;
  auto-switch-lite-json) auto_switch_json --fast ;;
  media-ai-json) media_ai_json ;;
  split-tunnel-json) split_tunnel_json ;;
  flush-dns-json) flush_dns_json ;;
  templates-json) templates_json ;;
  subconvert-json) subconvert_json ;;
  subconvert-lite-json) subconvert_json --fast ;;
  run-split-tunnel-test) run_split_tunnel_test ;;
  split-route-test-json) split_route_test_json "$@" ;;
  restart-openclash) restart_openclash ;;
  auto-fix-basic) auto_fix_basic ;;
  flush-dns) flush_dns ;;
  apply-auto-switch) apply_auto_switch ;;
  apply-recommended-profile) apply_recommended_profile ;;
  apply-media-ai) apply_media_ai ;;
  run-media-ai-live-test) run_media_ai_live_test ;;
  apply-subconvert) apply_subconvert ;;
  sync-media-ai-from-openclash) sync_media_ai_from_openclash ;;
  sync-subconvert-from-openclash) sync_subconvert_from_openclash ;;
  sync-subconvert-section-from-openclash) shift; sync_subconvert_section_from_openclash "$@" ;;
  *)
    echo "usage: $0 {status-json|checkup-json|advice-json|auto-switch-json|auto-switch-lite-json|media-ai-json|split-tunnel-json|split-route-test-json|flush-dns-json|templates-json|subconvert-json|subconvert-lite-json|run-split-tunnel-test|restart-openclash|auto-fix-basic|flush-dns|apply-auto-switch|apply-recommended-profile|apply-media-ai|run-media-ai-live-test|apply-subconvert|sync-media-ai-from-openclash|sync-subconvert-from-openclash|sync-subconvert-section-from-openclash <sid>}" >&2
    exit 1
  ;;
esac
