<div align="center">

<img src="Resources/iLaunch-icon-source.png" width="160" alt="iLaunch" />

# iLaunch

**把 macOS 26 拿走的 Launchpad 找回来——原生、飞快。**

全屏可视化应用网格，支持文件夹、即时搜索和手动布局，  
基于 SwiftUI + AppKit 打造，适用于 macOS Tahoe 及更新系统。

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange?logo=swift)](https://www.swift.org)
[![Release](https://img.shields.io/github/v/release/mengyuefeitian/iLaunch?label=release)](../../releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**简体中文** | [English](README_en.md)

</div>

---

## 为什么做这个

macOS 26 Tahoe 用类 Spotlight 的 Apps 入口取代了经典的 Launchpad。它搜索起来很高效，却丢掉了 Launchpad 最迷人的东西：**空间记忆**。知道某个应用在第几页、哪个角落，往往比每次都打字更快。

iLaunch 把这种体验带了回来——一个安静、全屏的网格，整理一次，终生可靠。

## 核心特性

- **全屏网格** —— 无边框 overlay，真实系统图标，页面指示器；行列数、图标大小（S/M/L）、应用名称显示均可在设置中自定义。
- **即时搜索** —— 实时过滤，完整**拼音**支持（输入 `yy` 即可找到「音乐」/ Music），键盘导航，点任意空白处即退出。
- **文件夹** —— 把一个应用拖到另一个上即可成组；弹窗从瓦片位置放大打开、关闭时缩回；支持重命名、弹窗内重排、拖出；关闭态 3×3 预览，放大文件夹可直点迷你图标启动。
- **Apple 应用智能成夹** —— 首次启动时，几十个 `com.apple.*` 应用自动收进「Apple」文件夹，之后新装的也会悄悄归入，绝不打乱你的布局。
- **实时拖拽整理** —— 主网格拖动时瓦片自动让位；跨页移动、文件夹内重排、拖出时实时留缝与新建文件夹感应；布局自动保存。
- **可配置全局热键** —— 默认 `⌥ Space`，可在设置中自定义；菜单栏与 Dock 亦可唤起。
- **移到废纸篓 / 隐藏** —— 长按或右键移除或隐藏应用；启动应用后立即退出大屏，不卡顿。
- **国际化** —— 支持系统语言以及中 / 英 / 日 / 韩 / 俄，运行时可切换。

## 最新版本 v1.8

- **产品更名：InceptLaunch → iLaunch** —— 应用标识、设置界面、打包（`.app` / DMG）、Bundle ID（`com.ilaunch.iLaunch`）、README 与多语言文案全面统一。
- **数据无缝迁移** —— 首次启动自动将 `Application Support/InceptLaunch/` 下的既有数据迁移到 `iLaunch/`，不丢布局、不丢设置。

> 完整变更见 [CHANGELOG](CHANGELOG.md) / [中文](CHANGELOG.zh.md)。最新发布包：[Releases](../../releases/latest)。

## 安装

从 [Releases](../../releases/latest) 下载最新的 `iLaunch-*.dmg`，打开后把 **iLaunch** 拖进 **Applications** 即可。

> 当前版本为 ad-hoc 签名的个人分发包。首次启动可能需要右键 → **打开** 以绕过 Gatekeeper。

## 快速上手

1. 启动 iLaunch（或从菜单栏 / Dock 打开）。
2. 用全局热键（默认 `⌥ Space`）打开网格。
3. 点击应用即可启动；直接输入开始搜索。
4. 拖动应用重新排列；把一个拖到另一个上即可建文件夹。
5. 点击文件夹打开弹层；在放大文件夹上可直接点迷你图标启动。
6. 在设置中调整网格、图标、热键与动画等选项。
7. 按 `Esc` 或点击空白处退出。

## 路线图

iLaunch 的演进方向，对照最初的[设计规格](docs/superpowers/specs/2026-07-20-ilaunch-launchpad-replica-design.md)追踪。

| 阶段 | 重点 | 状态 |
|------|------|------|
| **v0.1** 原型 | 应用扫描、网格、搜索、启动、菜单栏 | ✅ 已完成 |
| **v0.2** 基础体验 | 全屏 overlay、全局快捷键、分页、设置、布局持久化 | ✅ 已完成 |
| **v0.3** 手动组织 | 拖拽排序、跨页移动、文件夹、Apple 与目录折叠 | ✅ 已完成 |
| **v0.4** 完整复刻 | 编辑模式、移到废纸篓、动画打磨、键盘导航 | ✅ 已完成（多显示器仍在路上） |
| **v1.5** 体验升级 | 实时拖拽重排、i18n (日/韩)、设置页重构、隐藏应用 | ✅ 已完成 |
| **v1.6** 视觉与可控性 | Liquid Glass 文件夹、网格/图标设置、俄语、拖出感应 | ✅ 已完成 |
| **v1.7** 流畅交互 | 文件夹缩放开合、迷你图标直启、快速退屏启动、首击修复 | ✅ 已完成 |
| **v1.8** 品牌更名 | InceptLaunch → iLaunch 全面更名，数据无缝迁移 | ✅ 已完成 |
| **v1.9** 自动更新 | 基于 Sparkle 的自动更新，每日后台检查，菜单栏"检查更新…"，一键安装 | ✅ 已完成 |
| **v2.0** 稳定发布 | 多显示器与 Space、性能、首次使用引导、签名与公证 | 📋 计划中 |

### 接下来要做

- **多显示器与 Space** —— 在多显示器、全屏应用和 Stage Manager 下可预测地弹出，退出后焦点还原。
- **多套布局** —— 在工作 / 个人 / 演示网格之间切换。
- **旧 Launchpad 迁移** —— 实验性地从旧版 Launchpad 数据库导入页面和文件夹。
- **签名与公证** —— 通过 Developer ID 签名并公证，彻底消除 Gatekeeper 警告。

## 设计原则

iLaunch 遵循「Launchpad 优先」的理念：

- 手动布局优先于智能排序。
- 视觉网格优先于命令输入。
- 隐藏优先于删除。
- 稳定启动优先于炫技动画。
- 本地持久化优先于云同步。

目标是做一个值得信赖的系统伴侣，而不是一个功能堆砌、核心摇晃的启动器。

## 参与贡献

这目前是一个个人项目。欢迎通过 [Issues](../../issues) 提交想法和 bug 报告。

## 许可协议

基于 [MIT 协议](LICENSE) 开源。版权所有 © 2026。
