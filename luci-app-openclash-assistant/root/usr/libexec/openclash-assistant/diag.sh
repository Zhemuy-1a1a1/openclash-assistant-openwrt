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

sanitize_one_line() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
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
  printf '%s\n' netflix disney youtube prime_video hbo_max dazn paramount_plus discovery_plus tvb_anywhere bilibili openai claude gemini
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
  # Access checks always run against the full built-in target list.
  # Hidden legacy UCI toggles are ignored for the runtime check pipeline.
  echo true
}

media_ai_target_probe_backend() {
  case "$1" in
    claude|gemini) printf '%s' 'official_api' ;;
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
    *) return 1 ;;
  esac
}

split_tunnel_target_keys() {
  printf '%s\n' \
    alibaba netease bytedance tencent qualcomm_cn cloudflare_cn \
    cloudflare bytedance_global discord x medium crunchyroll \
    chatgpt sora openai_web claude grok anthropic perplexity \
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
      claude) media_ai_api_probe_claude ;;
      gemini) media_ai_api_probe_gemini ;;
      openai) media_ai_api_probe_openai ;;
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
  local key stream_type enabled line tested_at detail status source backend latency_ms http_code

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

  MEDIA_AI_TARGET_ENABLED="$enabled"
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
  local installed enabled running config_count openclash_dir dnsmasq_full ipset_ok nft_ok tun_ok firewall4_ok openclash_cfg role mode stream_auto_select stream_auto_select_logic stream_auto_select_interval

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
  printf '  "stream_auto_select_interval": "%s"\n' "$(json_string "$stream_auto_select_interval")"
  printf '}\n'
}

advice_json() {
  local role mode needs_ipv6 has_public uses_tailscale gaming low_maintenance profile risk why pitfalls checklist

  role="$(str_uci routing_role bypass_router)"
  mode="$(str_uci preferred_mode auto)"
  needs_ipv6="$(bool_uci needs_ipv6 0)"
  has_public="$(bool_uci has_public_services 0)"
  uses_tailscale="$(bool_uci uses_tailscale 0)"
  gaming="$(bool_uci gaming_devices 0)"
  low_maintenance="$(bool_uci low_maintenance 1)"

  profile="均衡方案"
  risk="中"
  why="建议优先采用兼容性更好的方案，在切换高级模式前先确认 DNS 接管是否正常。"
  pitfalls="上游 DNS 冲突、Fake-IP 缓存残留、TUN 与 IPv6 组合不匹配。"
  checklist="确认已安装 dnsmasq-full；确认 OpenClash 是实际生效的上游 DNS；切换模式前先备份配置。"

  if [ "$role" = "bypass_router" ] && { [ "$has_public" = true ] || [ "$uses_tailscale" = true ] || [ "$gaming" = true ]; }; then
    profile="兼容优先"
    risk="高"
    why="旁路由场景如果同时有公网访问、组网工具或游戏设备，最容易遇到 Fake-IP 兼容性边界问题。"
    pitfalls="局域网服务访问异常、公网端口不可达、组网流量异常、切换模式后设备缓存污染。"
    checklist="先用兼容优先方案；测试公网访问是否正常；按需添加静态路由或绕过规则；逐步切换而不是一次改完。"
  elif [ "$mode" = "fake-ip" ] && [ "$needs_ipv6" = true ]; then
    profile="Fake-IP + IPv6 谨慎模式"
    risk="高"
    why="社区反馈显示，Fake-IP 与 TUN / IPv6 的组合在某些固件或内核环境下比较脆弱。"
    pitfalls="TUN 启动失败、DNS 劫持判断混乱、IPv6 表现不稳定。"
    checklist="启用前先确认 TUN、firewall4 和 nft 支持正常，并保留可回滚方案。"
  elif [ "$low_maintenance" = true ]; then
    profile="稳定优先"
    risk="低"
    why="低维护需求应优先考虑稳定和可预期，而不是一味追求功能堆叠。"
    pitfalls="过度调优会提高维护成本，也更容易在升级后出现意外问题。"
    checklist="保留一套已验证可用的模式；避免频繁切换；修改前先记录当前 DNS 行为。"
  fi

  printf '{\n'
  printf '  "profile": "%s",\n' "$(json_string "$profile")"
  printf '  "risk": "%s",\n' "$(json_string "$risk")"
  printf '  "why": "%s",\n' "$(json_string "$why")"
  printf '  "pitfalls": "%s",\n' "$(json_string "$pitfalls")"
  printf '  "checklist": "%s"\n' "$(json_string "$checklist")"
  printf '}\n'
}

auto_switch_json() {
  local enabled logic interval expand_group close_con current_enabled current_logic current_interval logic_label suggestion commands

  enabled="$(bool_uci auto_switch_enabled 1)"
  logic="$(str_uci auto_switch_logic urltest)"
  interval="$(str_uci auto_switch_interval 30)"
  expand_group="$(bool_uci auto_switch_expand_group 1)"
  close_con="$(bool_uci auto_switch_close_con 1)"

  current_enabled="$(uci -q get openclash.config.stream_auto_select 2>/dev/null || echo 0)"
  current_logic="$(uci -q get openclash.config.stream_auto_select_logic 2>/dev/null || echo urltest)"
  current_interval="$(uci -q get openclash.config.stream_auto_select_interval 2>/dev/null || echo 30)"

  case "$logic" in
    random) logic_label='随机轮换' ;;
    *) logic='urltest'; logic_label='延迟优先（Urltest）' ;;
  esac

  if [ "$enabled" = true ]; then
    suggestion="建议开启 OpenClash 的自动选择解锁节点功能，逻辑使用${logic_label}，间隔 ${interval} 分钟。"
  else
    suggestion="当前助手建议未启用自动切换；如果节点较多或解锁场景频繁变化，建议打开自动切换。"
  fi

  commands="uci set openclash.config.stream_auto_select='$( [ "$enabled" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_interval='${interval}'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_logic='${logic}'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_expand_group='$( [ "$expand_group" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.config.stream_auto_select_close_con='$( [ "$close_con" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci commit openclash\n/etc/init.d/openclash restart"

  printf '{\n'
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "logic": "%s",\n' "$(json_string "$logic")"
  printf '  "logic_label": "%s",\n' "$(json_string "$logic_label")"
  printf '  "interval": "%s",\n' "$(json_string "$interval")"
  printf '  "expand_group": %s,\n' "$expand_group"
  printf '  "close_con": %s,\n' "$close_con"
  printf '  "current_enabled": "%s",\n' "$(json_string "$current_enabled")"
  printf '  "current_logic": "%s",\n' "$(json_string "$current_logic")"
  printf '  "current_interval": "%s",\n' "$(json_string "$current_interval")"
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
  local enabled source backend template_id custom_template emoji udp sort skip_verify append_type template_info template_name template_url recommended_id recommended_info recommended_name recommended_url encoded_source encoded_template convert_url source_hint commands

  enabled="$(bool_uci sub_convert_enabled 1)"
  source="$(str_uci sub_convert_source '')"
  backend="$(str_uci sub_convert_backend 'https://api.dler.io/sub')"
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

  source_hint='请先填写原始订阅地址，支持单条订阅地址，后续可扩展为多链接。'
  convert_url=''
  if [ -n "$source" ] && [ -n "$template_url" ] && [ -n "$backend" ]; then
    encoded_source="$(urlencode "$source")"
    encoded_template="$(urlencode "$template_url")"
    convert_url="${backend}?target=clash&new_name=true&url=${encoded_source}&config=${encoded_template}&emoji=${emoji}&list=false&sort=${sort}"
    [ "$udp" = 'true' ] && convert_url="${convert_url}&udp=true"
    convert_url="${convert_url}&scv=${skip_verify}&append_type=${append_type}&fdn=true"
    source_hint='已按 OpenClash 当前支持的 subconverter 参数生成转换地址。'
  fi

  commands="sid=\$(uci add openclash config_subscribe)\n"
  commands="$commands""uci set openclash.\$sid.enabled='1'\n"
  commands="$commands""uci set openclash.\$sid.name='助手生成订阅'\n"
  commands="$commands""uci set openclash.\$sid.address='${source}'\n"
  commands="$commands""uci set openclash.\$sid.sub_convert='$( [ "$enabled" = true ] && echo 1 || echo 0 )'\n"
  commands="$commands""uci set openclash.\$sid.convert_address='${backend}'\n"
  commands="$commands""uci set openclash.\$sid.template='${template_id}'\n"
  [ -n "$custom_template" ] && commands="$commands""uci set openclash.\$sid.custom_template_url='${custom_template}'\n"
  commands="$commands""uci set openclash.\$sid.emoji='${emoji}'\n"
  commands="$commands""uci set openclash.\$sid.udp='${udp}'\n"
  commands="$commands""uci set openclash.\$sid.sort='${sort}'\n"
  commands="$commands""uci set openclash.\$sid.skip_cert_verify='${skip_verify}'\n"
  commands="$commands""uci set openclash.\$sid.node_type='${append_type}'\n"
  commands="$commands""uci commit openclash"

  printf '{\n'
  printf '  "enabled": %s,\n' "$enabled"
  printf '  "backend": "%s",\n' "$(json_string "$backend")"
  printf '  "template_id": "%s",\n' "$(json_string "$template_id")"
  printf '  "template_name": "%s",\n' "$(json_string "${template_name:-未匹配到模板}")"
  printf '  "template_url": "%s",\n' "$(json_string "$template_url")"
  printf '  "recommended_template_id": "%s",\n' "$(json_string "$recommended_id")"
  printf '  "recommended_template_name": "%s",\n' "$(json_string "$recommended_name")"
  printf '  "recommended_template_url": "%s",\n' "$(json_string "$recommended_url")"
  printf '  "source": "%s",\n' "$(json_string "$source")"
  printf '  "emoji": "%s",\n' "$(json_string "$emoji")"
  printf '  "udp": "%s",\n' "$(json_string "$udp")"
  printf '  "sort": "%s",\n' "$(json_string "$sort")"
  printf '  "skip_cert_verify": "%s",\n' "$(json_string "$skip_verify")"
  printf '  "append_node_type": "%s",\n' "$(json_string "$append_type")"
  printf '  "convert_url": "%s",\n' "$(json_string "$convert_url")"
  printf '  "hint": "%s",\n' "$(json_string "$source_hint")"
  printf '  "commands": "%s"\n' "$(json_string "$commands")"
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
  local enabled logic interval expand_group close_con restart_result

  enabled="$(bool_uci_01 auto_switch_enabled 1)"
  logic="$(str_uci auto_switch_logic urltest)"
  interval="$(str_uci auto_switch_interval 30)"
  expand_group="$(bool_uci_01 auto_switch_expand_group 1)"
  close_con="$(bool_uci_01 auto_switch_close_con 1)"

  case "$logic" in
    urltest|random) ;;
    *) logic='urltest' ;;
  esac

  uci -q set openclash.config.stream_auto_select="$enabled"
  uci -q set openclash.config.stream_auto_select_interval="$interval"
  uci -q set openclash.config.stream_auto_select_logic="$logic"
  uci -q set openclash.config.stream_auto_select_expand_group="$expand_group"
  uci -q set openclash.config.stream_auto_select_close_con="$close_con"
  uci -q commit openclash

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
  local enabled source backend template_id custom_template emoji udp sort skip_verify append_type sid name sub_convert_value multiple_hint update_result

  enabled="$(bool_uci sub_convert_enabled 1)"
  source="$(str_uci sub_convert_source '')"
  backend="$(str_uci sub_convert_backend 'https://api.dler.io/sub')"
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
  uci -q set openclash."$sid".convert_address="$backend"
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

media_ai_json() {
  local enabled group_filter region_filter node_filter current_global current_logic current_openai current_netflix current_disney current_youtube current_prime current_bilibili selected summary suggestion commands live_running last_run_at success_count partial_count issue_count cache_count assistant_count can_run_live_test key json_fields toggle_option filter_suffix selected_count progress_selected progress_completed

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
    selected="${selected} $(media_ai_target_label "$key")"
    selected_count=$((selected_count + 1))
  done
  selected="$(printf '%s' "$selected" | sed 's/^ *//; s/  */, /g')"
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
    json_fields="${json_fields}  \"${key}_detail\": \"$(json_string "$MEDIA_AI_TARGET_DETAIL")\",\n"
  done

  if [ "$live_running" = true ]; then
    [ -n "$progress_selected" ] && selected_count="$progress_selected"
    [ -n "$progress_completed" ] && assistant_count="$progress_completed"
    summary="真实检测正在后台执行，当前已完成 ${assistant_count}/${selected_count} 项。完成后会一次性刷新全部结果。"
  elif [ -n "$last_run_at" ]; then
    summary="下面展示的是最近一次助手真实检测结果（${last_run_at}）。"
  else
    summary='暂无访问检查结果。页面会自动对全部流媒体与 AI 目标执行访问检查，无需手动勾选。'
  fi

  if [ "$issue_count" -gt 0 ]; then
    suggestion='至少有一项当前显示访问受限或检测失败。可以先检查当前 OpenClash 出口节点、DNS 与分流策略。'
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

    if [ -n "$group_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      commands="$commands""uci set openclash.config.stream_auto_select_group_key_${filter_suffix}='${group_filter}'\n"
    fi
    if [ -n "$region_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      commands="$commands""uci set openclash.config.stream_auto_select_region_key_${filter_suffix}='${region_filter}'\n"
    fi
    if [ -n "$node_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      commands="$commands""uci set openclash.config.stream_auto_select_node_key_${filter_suffix}='${node_filter}'\n"
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

    if [ -n "$group_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      uci -q set openclash.config."stream_auto_select_group_key_${filter_suffix}"="$group_filter"
    fi
    if [ -n "$region_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      uci -q set openclash.config."stream_auto_select_region_key_${filter_suffix}"="$region_filter"
    fi
    if [ -n "$node_filter" ] && [ "$(media_ai_target_enabled "$key")" = true ] && [ -n "$filter_suffix" ]; then
      uci -q set openclash.config."stream_auto_select_node_key_${filter_suffix}"="$node_filter"
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

sync_subconvert_from_openclash() {
  local sid name address sub_convert backend template custom_template emoji udp sort skip_verify node_type

  sid="$(find_first_subscribe_section 2>/dev/null || true)"
  if [ -z "$sid" ]; then
    printf '{\n'
    printf '  "ok": false,\n'
    printf '  "message": "%s"\n' "$(json_string '未找到现有的 OpenClash 订阅项，无法导入。')"
    printf '}\n'
    return 0
  fi

  name="$(uci -q get openclash."$sid".name 2>/dev/null || echo '')"
  address="$(uci -q get openclash."$sid".address 2>/dev/null || echo '')"
  sub_convert="$(uci -q get openclash."$sid".sub_convert 2>/dev/null || echo 0)"
  backend="$(uci -q get openclash."$sid".convert_address 2>/dev/null || echo 'https://api.dler.io/sub')"
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
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_backend=$backend"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_template=$template"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_custom_template_url=$custom_template"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_emoji=$emoji"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_udp=$udp"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_sort=$sort"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_skip_cert_verify=$skip_verify"
  uci -q set "$CONFIG_NAME.$CONFIG_SECTION.sub_convert_append_node_type=$node_type"
  uci -q commit "$CONFIG_NAME"

  printf '{\n'
  printf '  "ok": true,\n'
  printf '  "message": "%s"\n' "$(json_string "已从 OpenClash 现有订阅【${name:-未命名}】导入参数到助手页面。")"
  printf '}\n'
}

flush_dns_json() {
  local dnsmasq_available dnsmasq_running smartdns_available smartdns_running openclash_running last_run_at last_status last_message

  [ -x /etc/init.d/dnsmasq ] && dnsmasq_available=true || dnsmasq_available=false
  dnsmasq_running="$(service_running_named dnsmasq)"
  [ -x /etc/init.d/smartdns ] && smartdns_available=true || smartdns_available=false
  smartdns_running="$(service_running_named smartdns)"
  openclash_running="$(service_running)"
  last_run_at="$(flush_dns_state_value last_run_at)"
  last_status="$(flush_dns_state_value status)"
  last_message="$(flush_dns_state_value message)"

  printf '{\n'
  printf '  "dnsmasq_available": %s,\n' "$dnsmasq_available"
  printf '  "dnsmasq_running": %s,\n' "$dnsmasq_running"
  printf '  "smartdns_available": %s,\n' "$smartdns_available"
  printf '  "smartdns_running": %s,\n' "$smartdns_running"
  printf '  "openclash_running": %s,\n' "$openclash_running"
  printf '  "last_run_at": "%s",\n' "$(json_string "$last_run_at")"
  printf '  "last_status": "%s",\n' "$(json_string "$last_status")"
  printf '  "last_message": "%s",\n' "$(json_string "$last_message")"
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
  advice-json) advice_json ;;
  auto-switch-json) auto_switch_json ;;
  media-ai-json) media_ai_json ;;
  split-tunnel-json) split_tunnel_json ;;
  flush-dns-json) flush_dns_json ;;
  templates-json) templates_json ;;
  subconvert-json) subconvert_json ;;
  run-split-tunnel-test) run_split_tunnel_test ;;
  flush-dns) flush_dns ;;
  apply-auto-switch) apply_auto_switch ;;
  apply-media-ai) apply_media_ai ;;
  run-media-ai-live-test) run_media_ai_live_test ;;
  apply-subconvert) apply_subconvert ;;
  sync-media-ai-from-openclash) sync_media_ai_from_openclash ;;
  sync-subconvert-from-openclash) sync_subconvert_from_openclash ;;
  *)
    echo "usage: $0 {status-json|advice-json|auto-switch-json|media-ai-json|split-tunnel-json|flush-dns-json|templates-json|subconvert-json|run-split-tunnel-test|flush-dns|apply-auto-switch|apply-media-ai|run-media-ai-live-test|apply-subconvert|sync-media-ai-from-openclash|sync-subconvert-from-openclash}" >&2
    exit 1
  ;;
esac
