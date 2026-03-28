# OpenClash Assistant v0.1.1

OpenClash Assistant for iStoreOS / OpenWrt.

## Highlights

- Assistant-style dashboard layout instead of a scattered tool page
- Single-page subscription workflow: source URL, conversion preview, and one-click import on the same page
- First-screen load hardening with timeout fallback, cache, and post-render live refresh
- Fixed occasional false empty states such as `OpenClash 未运行` and `订阅转换 未设置`
- Repository screenshots added for GitHub preview

## Included Assets

- `openclash-assistant-istoreos-v0.1.1-r1.run`
- `openclash-assistant-istoreos-v0.1.1-r1.run.sha256`
- `openclash-assistant-istoreos-v0.1.1-r1-release.tar.gz`
- `luci-app-openclash-assistant_0.1.1-1_all.ipk`
- `luci-app-openclash-assistant_0.1.1-1_all.ipk.sha256`

## Install

```sh
chmod +x openclash-assistant-istoreos-v0.1.1-r1.run
./openclash-assistant-istoreos-v0.1.1-r1.run
```

## Uninstall

```sh
./openclash-assistant-istoreos-v0.1.1-r1.run --uninstall
```

## Open Source References

This project references or draws inspiration from:

- `vernesong/OpenClash`
- `openwrt/luci`
- `Rabbit-Spec/Surge`
  - `Module/Panel/Stream-All`
  - `Module/Panel/Flush-DNS`
- `ACL4SSR/ACL4SSR`
- `Aethersailor/Custom_OpenClash_Rules`
