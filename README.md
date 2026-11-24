# XMPro for macOS

基于 [angusdevgo/XMPro](https://github.com/angusdevgo/XMPro) 喜马拉雅极速版协议打造的原生 macOS 轻量听书客户端，使用纯 Swift 6 + SwiftUI + AppKit + AVFoundation 零第三方重型依赖构建。

## 特性概览
- **原生苹果播客美学**：磨砂侧边栏、统一工具栏搜索、封面动态柔和氛围光晕、底部悬浮毛玻璃播控条与沉浸式播放抽屉，跟随系统深浅色模式。
- **常驻菜单栏控制**：关闭主窗口自动退居菜单栏安静后台播放，点击菜单栏声波图标弹出迷你播控卡片；原生接入 macOS 控制中心、锁屏封面、AirPods 与键盘多媒体键。
- **完整听书闭环**：发现频道与推荐流、专辑/声音搜索、专辑详情与 100 集分段选集、书单（听更新 / 订阅 / 历史 / 收藏）、倍速（0.5×–3.0×）、定时关闭、音质切换、跳过头尾（智能静音检测 / 手动比例裁剪）、双端进度同步。
- **账号与听时**：支持一键导入 XMPro Cookie 或手机号短信验证码登录（内嵌隔离 CSP 的原生 `WKWebView` 安全滑块）；支持听时余额查询、福利档位明细与后台自动补领。
- **极致轻量**：成品 `XMPro.app` 约 6.1 MB，零外部运行时依赖。

## 安装使用
1. 前往 [Releases](https://github.com/245678000000/XMProMac/releases) 下载 `XMPro-1.0.0-macOS-arm64.zip`（需 macOS 14.0+，Apple Silicon）。
2. 解压后将 `XMPro.app` 拖入 `/Applications` 文件夹即可。
3. 首次打开若遇到 macOS 提示“无法验证开发者”（本地自签名），可在右键菜单选择“打开”，或在终端执行 `xattr -cr /Applications/XMPro.app` 后双击启动。

## 常用快捷键
- `⌘P`：播放 / 暂停
- `⌘]` / `⌘[`：下一集 / 上一集
- `⌘→` / `⌘←`：快进 / 快退 15 秒
- `⌘L`：展开 / 收起沉浸播放与待播队列

## 从源码构建与测试
无需安装完整 Xcode，仅需 macOS Command Line Tools（Swift 6）：

```bash
# 运行 XMProCore 协议对拍单元测试
./scripts/run-tests.sh

# 编译 Release 并生成带原生图标的 dist/XMPro.app
./scripts/bundle-app.sh
```

## 开源许可与致谢
- 遵循 [AGPL-3.0-or-later](LICENSE) 开源协议。
- 协议逻辑与测试向量移植自 [angusdevgo/XMPro](https://github.com/angusdevgo/XMPro)，特此致谢。

> 声明：本项目与喜马拉雅官方无关，仅供个人学习与自用，请使用自有账号并遵守服务条款。
