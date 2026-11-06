# Clash Verge Desktop Widget for macOS

一个独立的 macOS 桌面状态卡片，适配 Clash Verge Rev 2.5.10。默认实现使用桌面层原生面板，不依赖 Apple Developer 证书。

功能：

- 344 × 164 桌面卡片，默认放在桌面左侧第三行
- 可按住卡片顶部标题区域拖动，位置自动保存并限制在屏幕范围内；登录后自动启动
- 点击规则、全局、直连可直接切换代理模式
- 点击系统代理、TUN 可直接开关对应功能
- 操作期间显示加载状态，完成后重新读取真实状态；失败不会假装已经切换
- 每 5 秒更新最近一次采样的上下行速率、累计流量与活动连接数
- 显示 TUN、系统代理、规则/全局/直连模式的当前状态
- 只有右上角按钮和双击卡片会打开 Clash Verge 主界面；右键菜单支持立即刷新
- 不直接修改 Mihomo、系统网络设置或 Clash Verge YAML；控制动作会按下 Clash Verge 自己的状态栏菜单项，因此配置、托盘、服务与运行态保持同步
- 不读取或保存订阅密钥；通过当前用户私有的 Mihomo Unix Socket 获取状态
- 辅助服务仅监听当前用户专属的 `127.0.0.1` 端口，并校验每次构建随机生成的本地令牌

项目仍保留小号/中号 WidgetKit 扩展源码；要添加到 macOS 原生组件库，需要用带 Team Identifier 的 Apple Development 或 Developer ID 证书重新签名。无证书安装时，桌面面板就是实际运行的组件。

## 构建

```bash
./Scripts/build.sh
```

## 安装

```bash
./Scripts/install.sh
```

安装脚本会先重新构建，再安装到 `~/Applications/Clash Verge Widget.app`。桌面卡片与只读辅助服务通过当前用户的 LaunchAgent 自动运行。

## 一次性控制设置

Clash Verge Rev 2.5.10 没有提供给独立小组件调用的完整控制 API。为了让切换仍然走 Clash Verge 自己的配置、TUN 服务、系统代理和托盘同步逻辑，小组件会通过 macOS 辅助功能按下 Clash Verge 自己的状态栏菜单项。无需设置任何 Clash Verge 快捷键。

请在 Clash Verge 的 `设置 → Verge 基础设置 → 系统匣点击事件` 选择“显示系统匣菜单”。这是 Clash Verge 官方设置，确保小组件能从状态栏图标展开原生菜单；即使图标被 Hidden Bar 一类工具收起，辅助功能仍可找到它。

首次点击控制项时，请在 `系统设置 → 隐私与安全性 → 辅助功能`（部分系统版本显示在“装置控制和资料取用”中）允许 `Clash Verge Widget`，然后关闭并重新打开小组件。无需开启“输入监控”或“屏幕录制”。构建脚本会嵌入稳定的本地指定要求，后续在同一路径覆盖升级通常无需重复授权；移动 App 或更换 Bundle Identifier 后仍可能需要重新授权。Clash Verge 必须保持运行。

## 验证

```bash
swift test
pluginkit -m -p com.apple.widgetkit-extension -i com.local.ClashVergeWidget.Extension -A -D -vv
```

本项目是独立本机工具，不修改或替换 Clash Verge.app。若 Clash Verge 未运行、状态栏菜单不可访问或没有辅助功能权限，小组件会显示错误并保留实际状态，不会退回到直接修改 Mihomo/YAML 的不一致方案。

## 开源发布说明

- 仓库不包含 Clash Verge 的图标、二进制文件、订阅或用户配置。
- 安装脚本不会修改用户的 Clash Verge 配置，也不会自动重启 Clash Verge。
- 构建时生成的本地 Bridge 令牌会在结束后自动还原为占位值，避免误提交。
- 当前尚未选择开源许可证；发布到 GitHub 前请按你的授权意图补充 `LICENSE`。
- `com.local.*` Bundle Identifier 适合本机开发，正式发布时建议替换为维护者自己的反向域名。
