# OpenClash 助手技术方案

## 1. 技术目标

围绕 OpenWrt / LuCI / OpenClash 场景，做一套资源占用可控、可解释、可扩展的助手式产品。

目标不是做重型后台，而是：

1. 先用 LuCI + Shell + Lua 跑通闭环
2. 先用规则引擎，不依赖大模型
3. 优先保证检测结果、建议和动作的一致性

## 2. 推荐技术栈

### 前端层

1. LuCI 视图页
2. 原生 JS
3. 卡片式页面渲染
4. localStorage 持久化小白 / 高级模式和最近标签页

### 后端层

1. `diag.sh` 负责状态采集、检测、修复执行
2. LuCI Lua Controller 暴露页面和后续 API
3. UCI 保存助手配置

### 状态采集层

1. `uci`
2. `/etc/init.d/*`
3. `pgrep`
4. OpenClash 脚本和状态文件
5. 本地 `subconverter`
6. `curl`

## 3. 当前目录角色

### `/luci-app-openclash-assistant/htdocs/luci-static/resources/view/openclash-assistant/overview.js`

前端主工作台。

负责：

1. 快速入口
2. 场景配置
3. 运行概览
4. 一键体检
5. 各专项检测页
6. 小白 / 高级模式切换

### `/luci-app-openclash-assistant/root/usr/libexec/openclash-assistant/diag.sh`

后端脚本总入口。

已承担：

1. `status-json`
2. `advice-json`
3. `subconvert-json`
4. `templates-json`
5. `media-ai-json`
6. `split-tunnel-json`
7. `flush-dns-json`
8. `auto-switch-json`
9. 修复和应用动作

## 4. 前端架构建议

## 4.1 页面分层

1. Hero 区
2. 快速入口区
3. Tab 工作区

## 4.2 Tab 划分

1. 导入订阅与生成配置
2. 场景配置与概览
3. 一键体检
4. 流媒体检测
5. AI 服务测试
6. DNS 修复
7. 自动切换建议
8. 网站走向检测

## 4.3 展示模式

### 小白模式

1. 隐藏技术表格
2. 默认展示结论和建议
3. 优先显示“下一步该做什么”

### 高级模式

1. 显示状态表格
2. 显示命令
3. 显示更完整的技术明细

## 5. 后端脚本接口定义

当前使用命令式接口：

1. `diag.sh status-json`
2. `diag.sh advice-json`
3. `diag.sh subconvert-json`
4. `diag.sh templates-json`
5. `diag.sh media-ai-json`
6. `diag.sh split-tunnel-json`
7. `diag.sh flush-dns-json`
8. `diag.sh auto-switch-json`
9. `diag.sh flush-dns`
10. `diag.sh apply-auto-switch`
11. `diag.sh apply-subconvert`
12. `diag.sh sync-subconvert-from-openclash`
13. `diag.sh run-media-ai-live-test`
14. `diag.sh run-split-tunnel-test`

## 6. 状态模型

### 6.1 基础状态

来源：`status-json`

主要字段：

1. `installed`
2. `enabled`
3. `running`
4. `config_count`
5. `routing_role`
6. `preferred_mode`
7. `stream_auto_select`
8. `dns_chain`
9. `dns_diag_level`
10. `dns_diag_summary`

### 6.2 基础建议

来源：`advice-json`

主要字段：

1. `profile`
2. `risk`
3. `why`
4. `pitfalls`
5. `checklist`

### 6.3 订阅转换

来源：`subconvert-json`

主要字段：

1. `enabled`
2. `backend`
3. `backend_api`
4. `template_id`
5. `template_name`
6. `recommended_template_name`
7. `source`
8. `frontend_url`
9. `convert_url`

### 6.4 流媒体 / AI 检测

来源：`media-ai-json`

结构特点：

1. 整体状态字段
2. 各平台独立结果字段
3. 后台执行进度字段

### 6.5 网站走向检测

来源：`split-tunnel-json`

主要字段：

1. `test_running`
2. `selected_count`
3. `success_count`
4. `issue_count`
5. `summary`
6. `*_exit_country`
7. `*_exit_ip`
8. `*_latency_ms`

### 6.6 DNS 修复

来源：`flush-dns-json`

主要字段：

1. `last_run_at`
2. `last_message`
3. `dns_chain`
4. `dns_diag_level`
5. `dns_diag_summary`
6. `dns_diag_action`

## 7. 规则引擎设计

当前规则引擎先放前端和 `diag.sh` 轻逻辑中，后续可抽成独立规则表。

### 7.1 输入

1. OpenClash 运行状态
2. 订阅转换状态
3. DNS 状态
4. 流媒体结果
5. AI 结果
6. 网站走向结果
7. 自动切换状态

### 7.2 输出

统一输出：

1. `level`
2. `title`
3. `text`
4. `next`
5. `action`

### 7.3 当前体检规则

1. OpenClash 未运行 -> `fix`
2. 未填写订阅 -> `risk`
3. DNS 诊断为 `bad` -> `fix`
4. 流媒体 / AI 异常数 > 0 -> `risk`
5. 网站走向暂无结果 -> `optimize`
6. 建议自动切换但 OpenClash 未开启 -> `optimize`

## 8. 近期开发任务

### P0

1. 保持 `overview.js` 的助手式结构稳定
2. 新增后端“体检 JSON”接口，避免前端拼规则
3. 补充当前节点、出口、资源占用字段
4. DNS 修复后自动刷新页面卡片

### P1

1. 增加历史检测结果存储
2. 拆分 `overview.js` 为组件化文件
3. 增加节点画像规则
4. 增加自动切换向导

## 9. API 演进建议

后续建议把 `diag.sh` 包装成更清晰的 LuCI API：

1. `GET /overview`
2. `POST /checkup`
3. `POST /checkup/fix`
4. `POST /subscription/import`
5. `POST /convert`
6. `POST /streaming-test`
7. `POST /ai-test`
8. `POST /dns/check`
9. `POST /dns/flush`
10. `POST /route-test`

## 10. 当前实现原则

1. 不依赖外部 hosted 前端
2. 订阅转换前端内置到 LuCI 静态资源
3. 订阅转换后端优先走本地 `subconverter`
4. 默认使用本地 `127.0.0.1:25500`
5. 浏览器端自动把回环地址映射成路由器可访问地址
