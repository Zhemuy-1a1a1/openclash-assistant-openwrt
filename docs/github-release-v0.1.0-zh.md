# OpenClash Assistant v0.1.0

OpenClash Assistant 是一个面向 iStoreOS / OpenWrt 的 LuCI 辅助插件。

## 版本亮点

- 统一的 `访问检查` 页面
  用于检查流媒体和 AI 目标的连接状态、延迟和返回情况
- 默认全量自动检查
  不需要手动勾选目标
- `DNS 工具` 标签
  支持 `Flush DNS`
- 保留 `自动切换` 与 `订阅转换` 功能页
- 提供 iStoreOS / OpenWrt 可直接安装的 `.run` 安装包
- 提供标准 `ipk` 包

## Release 资产

- `openclash-assistant-istoreos-v0.1.0-r1.run`
- `openclash-assistant-istoreos-v0.1.0-r1.run.sha256`
- `openclash-assistant-istoreos-v0.1.0-r1-release.tar.gz`
- `luci-app-openclash-assistant_0.1.0-1_all.ipk`
- `luci-app-openclash-assistant_0.1.0-1_all.ipk.sha256`
- `中文说明.md`

## 安装方式

### 一键安装命令

```sh
cd /tmp && curl -L -o openclash-assistant-istoreos-v0.1.0-r1.run https://github.com/Zhemuy-1a1a1/openclash-assistant-openwrt/releases/download/v0.1.0/openclash-assistant-istoreos-v0.1.0-r1.run && chmod +x openclash-assistant-istoreos-v0.1.0-r1.run && sh openclash-assistant-istoreos-v0.1.0-r1.run
```

### 方式一：使用 `.run`

```sh
chmod +x openclash-assistant-istoreos-v0.1.0-r1.run
./openclash-assistant-istoreos-v0.1.0-r1.run
```

### 方式二：使用 `ipk`

```sh
opkg install luci-app-openclash-assistant_0.1.0-1_all.ipk
```

## 卸载方式

### 卸载 `.run` 安装版

```sh
./openclash-assistant-istoreos-v0.1.0-r1.run --uninstall
```

### 卸载 `ipk` 安装版

```sh
opkg remove luci-app-openclash-assistant
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
