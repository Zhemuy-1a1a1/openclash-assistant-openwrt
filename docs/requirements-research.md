# OpenClash Assistant Requirements Research

## Research date

- 2026-03-25 (Asia/Shanghai)

## Goal

Collect current requirements from the OpenClash / soft-router community and turn them into an MVP for an OpenWrt helper plugin.

## Sources reviewed

### Official / primary

1. OpenClash GitHub repository
   - https://github.com/vernesong/OpenClash
2. OpenClash Wiki home
   - https://github.com/vernesong/openclash/wiki
3. OpenClash Wiki: DNS settings
   - https://github.com/vernesong/OpenClash/wiki/DNS%E8%AE%BE%E7%BD%AE
4. OpenClash issue tracker snapshot
   - https://github.com/vernesong/openclash/issues
5. OpenWrt / LuCI feed repository
   - https://github.com/openwrt/luci

### Community demand signals

6. V2EX: `openclash fake-ip 模式的使用问题`
   - https://www.v2ex.com/t/1048402
7. V2EX: `OpenClash fake-ip 模式兼容性问题`
   - https://www.v2ex.com/t/951618
8. OpenClash issue #4644: bypass-router mode traffic not being taken over
   - https://github.com/vernesong/OpenClash/issues/4644
9. OpenClash issue #4573: subscription updated but effective config remains invalid
   - https://github.com/vernesong/OpenClash/issues/4573
10. OpenClash issue #4577: Fake-IP TUN with IPv6 mode fails to start
   - https://github.com/vernesong/OpenClash/issues/4577
11. OpenClash issue #4924: TUN auto-route forced false
   - https://github.com/vernesong/OpenClash/issues/4924
12. OpenClash issue #4926: dashboard behavior confusion after update
   - https://github.com/vernesong/OpenClash/issues/4926
13. OpenClash issue #4935: Smart node-group weight anomaly
   - https://github.com/vernesong/OpenClash/issues/4935

## Key demand clusters

### 1. Bypass-router users need mode selection help

Observed pattern:

- Users running OpenClash as a bypass router often struggle to choose between Fake-IP, TUN, and compatibility-focused modes.
- Community discussions repeatedly report that Fake-IP can improve speed but also create LAN, public-service, or DNS-cache compatibility issues.

Implication for product:

- The assistant should not just expose toggles.
- It should recommend a mode based on scenario inputs such as bypass-router deployment, exposed LAN services, Tailscale, game consoles, and IPv6 requirements.

### 2. DNS conflict diagnosis is a recurring pain point

Observed pattern:

- Official wiki guidance stresses DNS hijack correctness and warns about conflicts with other DNS-forwarding plugins.
- Multiple issue reports show users struggling to understand whether dnsmasq forwarding, custom DNS, local hijack, or another plugin is the current conflict source.

Implication for product:

- The MVP should provide a concise diagnostic summary rather than forcing users to manually inspect many pages.
- The plugin should surface likely conflict areas and give plain-language next steps.

### 3. TUN / IPv6 / firewall dependency visibility is poor

Observed pattern:

- Current issue reports commonly include missing `nft_tproxy`, TUN startup failure, IPv6 interactions, or runtime mismatch between installed dependencies and selected mode.
- Users often only discover the mismatch after failure.

Implication for product:

- The assistant should detect key dependency presence and show a mode-risk summary before users change major settings.

### 4. Runtime state after updates is hard to validate

Observed pattern:

- Recent issues show confusion around subscription conversion, dashboard behavior, configuration activation, and whether changes really took effect.

Implication for product:

- The MVP should show a compact health status: installed, enabled, running, config present, core-related hints, and whether OpenClash appears to be the active DNS upstream.

## Product opportunity

The best near-term plugin is not a replacement for OpenClash itself.
It is a helper layer that focuses on:

- diagnosis
- recommendation
- safer defaults
- clearer next actions

## MVP requirements

### Functional

1. Detect whether OpenClash is installed, enabled, and currently running.
2. Detect common dependency signals relevant to OpenClash health:
   - `dnsmasq-full`
   - `ipset` / `nftset` support
   - `kmod-tun`
   - firewall4 / nft presence
3. Detect whether OpenClash config files are present.
4. Provide scenario-based advice for:
   - bypass-router deployment
   - Fake-IP preference
   - IPv6 requirement
   - exposed LAN services
   - Tailscale / exit-node style networking
   - gaming / low-friction device compatibility
5. Present results in a single LuCI page with actionable language.

### Non-functional

- Avoid modifying OpenClash configuration automatically in the MVP.
- Prefer read-only diagnostics plus guidance.
- Keep dependencies lightweight.
- Work as a standalone LuCI companion package.

## Initial product decision

Build `luci-app-openclash-assistant` as a lightweight LuCI app with:

- one assistant page
- one diagnostics shell backend
- one scenario config section
- one advice renderer

## Inference notes

Some recommendations in the plugin are heuristic rather than official OpenClash policy.
Those heuristics are inferred from recurring community problem patterns and should be labeled as guidance, not authoritative truth.
