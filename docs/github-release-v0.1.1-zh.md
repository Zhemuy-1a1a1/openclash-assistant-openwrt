# OpenClash Assistant v0.1.1

OpenClash Assistant 是一个面向 iStoreOS / OpenWrt 的 LuCI 辅助插件。

## 版本亮点

- 助手式首页重排
  首页改成“摘要卡 + 快速入口 + 标签式工作台”，不再是零散工具页
- 订阅单页流程
  原始订阅、转换预览、一键导入 OpenClash 放在同一页完成
- 首屏加载优化
  加入超时回退、本地缓存和渲染后热更新，避免长期停在“正在载入视图…”
- 状态识别修复
  修复首页偶发显示“OpenClash 未运行 / 订阅转换未设置”的问题
- 内置界面截图
  仓库新增 GitHub 展示截图，方便直接查看实际界面

## Release 资产

- `openclash-assistant-istoreos-v0.1.1-r1.run`
- `openclash-assistant-istoreos-v0.1.1-r1.run.sha256`
- `openclash-assistant-istoreos-v0.1.1-r1-release.tar.gz`
- `luci-app-openclash-assistant_0.1.1-1_all.ipk`
- `luci-app-openclash-assistant_0.1.1-1_all.ipk.sha256`
- `中文说明.md`

## 安装方式

### 一键安装命令

```sh
cd /tmp && curl -L -o openclash-assistant-istoreos-v0.1.1-r1.run https://github.com/Zhemuy-1a1a1/openclash-assistant-openwrt/releases/download/v0.1.1/openclash-assistant-istoreos-v0.1.1-r1.run && chmod +x openclash-assistant-istoreos-v0.1.1-r1.run && sh openclash-assistant-istoreos-v0.1.1-r1.run
```

### 方式一：使用 `.run`

```sh
chmod +x openclash-assistant-istoreos-v0.1.1-r1.run
./openclash-assistant-istoreos-v0.1.1-r1.run
```

### 方式二：使用 `ipk`

```sh
opkg install luci-app-openclash-assistant_0.1.1-1_all.ipk
```

## 卸载方式

### 卸载 `.run` 安装版

```sh
./openclash-assistant-istoreos-v0.1.1-r1.run --uninstall
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
