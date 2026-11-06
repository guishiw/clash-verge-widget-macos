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
- 不直接修改 Mihomo、系统网络设置或 Clash Verge YAML；控制动作通过 Clash Verge 自带全局快捷键执行，因此配置、托盘、服务与运行态保持同步
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

Clash Verge Rev 2.5.10 没有提供给独立小组件调用的完整控制 API。为了让切换仍然走 Clash Verge 自己的配置、TUN 服务、系统代理和托盘同步逻辑，小组件会读取并触发 Clash Verge 已配置的全局快捷键。

在 Clash Verge 中打开：`设置 → Verge 基础设置 → 快速键设置`，开启“启用全域快速键”，并为下面五项分别设置一个不重复的快捷键：

| 功能 | Clash Verge 配置名 | 本机测试映射 |
| --- | --- | --- |
| 规则 | `clash_mode_rule` | `F13` |
| 全局 | `clash_mode_global` | `F14` |
| 直连 | `clash_mode_direct` | `F15` |
| 系统代理 | `toggle_system_proxy` | `F16` |
| TUN | `toggle_tun_mode` | `F17` |

可以使用其他组合，例如 `Control+Option+Command+1` 到 `5`；小组件会读取现有配置，不要求固定使用 F13–F17。当前支持 F1–F20、字母、数字、方向键及常用按键，并支持 Command、Control、Option、Shift 修饰键。Clash Verge 必须保持运行。

安装完成后可只读检查配置，不会改写 `verge.yaml`：

```bash
./Scripts/check-hotkeys.sh
```

首次点击控制项时，macOS 可能请求事件合成权限。请在 `系统设置 → 隐私与安全性 → 辅助功能` 中允许 `Clash Verge Widget`，然后再点击一次；若仍未生效，请重新启动小组件。无需开启“输入监控”或“屏幕录制”。使用临时签名重新构建或移动 App 后，macOS 可能要求重新授权。

## 验证

```bash
swift test
./Scripts/check-hotkeys.sh
pluginkit -m -p com.apple.widgetkit-extension -i com.local.ClashVergeWidget.Extension -A -D -vv
```

本项目是独立本机工具，不修改或替换 Clash Verge.app。若快捷键缺失、禁用、冲突或没有辅助功能权限，小组件会显示错误并保留实际状态，不会退回到直接修改 Mihomo/YAML 的不一致方案。

## 开源发布说明

- 仓库不包含 Clash Verge 的图标、二进制文件、订阅或用户配置。
- 安装脚本只检测快捷键，不会静默覆盖用户已有绑定，也不会自动重启 Clash Verge。
- 构建时生成的本地 Bridge 令牌会在结束后自动还原为占位值，避免误提交。
- 当前尚未选择开源许可证；发布到 GitHub 前请按你的授权意图补充 `LICENSE`。
- `com.local.*` Bundle Identifier 适合本机开发，正式发布时建议替换为维护者自己的反向域名。
