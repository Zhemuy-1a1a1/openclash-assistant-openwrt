# OpenClash Assistant for OpenWrt

A LuCI helper plugin for iStoreOS / OpenWrt that turns recurring OpenClash soft-router pain points into a compact diagnostic and access-check panel.

## 中文说明

- 中文使用说明：[`docs/中文说明.md`](docs/中文说明.md)
- GitHub Release 中文说明：[`docs/github-release-v0.1.0-zh.md`](docs/github-release-v0.1.0-zh.md)

## Why this exists

Recent community reports repeatedly cluster around:

- Fake-IP compatibility in bypass-router deployments
- DNS hijack and upstream conflict diagnosis
- TUN / IPv6 / nftables dependency confusion
- Subscription and runtime state validation after updates
- Lack of a single, actionable "what should I choose" assistant for OpenClash modes

This project packages those needs into a lightweight LuCI plugin named `luci-app-openclash-assistant`.

## Current scope

- Runtime environment diagnostics for an OpenClash host
- Unified access checks for streaming and AI targets
- DNS utility panel with `Flush DNS`
- Node auto-switch guidance
- Subscription conversion helper
- LuCI page under `Services -> OpenClash Assistant`

## Project layout

- `docs/requirements-research.md` — demand collection and source summary
- `docs/mvp-design.md` — MVP goals and package architecture
- `luci-app-openclash-assistant/` — OpenWrt package scaffold

## Build / Install

- OpenWrt / iStoreOS package source: `luci-app-openclash-assistant/`
- One-file installer: `dist/openclash-assistant-istoreos-v0.1.0-r1.run`

## Open Source References

This project references or draws inspiration from the following open source projects:

- [vernesong/OpenClash](https://github.com/vernesong/OpenClash)
  Core product context, OpenClash runtime behavior, and LuCI/OpenWrt integration assumptions.
- [openwrt/luci](https://github.com/openwrt/luci)
  LuCI package structure, menu/ACL wiring, and frontend conventions.
- [Rabbit-Spec/Surge](https://github.com/Rabbit-Spec/Surge)
  Panel interaction ideas and visual inspiration, especially:
  - `Module/Panel/Stream-All`
  - `Module/Panel/Flush-DNS`
- [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR)
  Subscription conversion template references.
- [Aethersailor/Custom_OpenClash_Rules](https://github.com/Aethersailor/Custom_OpenClash_Rules)
  Additional subscription conversion template references.

These upstream projects remain owned by their respective authors. This repository does not claim ownership of those projects and only reuses ideas, integration knowledge, or template references where applicable.

## Notes

This repository is designed to be built inside an OpenWrt tree / SDK, or installed on compatible iStoreOS / OpenWrt systems via the generated `.run` installer.
