# XMPro macOS 原生客户端设计规格

## 1. 产品定位
基于 `angusdevgo/XMPro` 喜马拉雅极速版协议打造的原生 macOS 轻量听书客户端（**精致主力听书版**）：
- **视觉与交互**：苹果播客（Apple Podcasts）式原生 macOS 磨砂侧边栏 + 底部悬浮毛玻璃播控条 + 封面动态柔和氛围光晕 + 常驻菜单栏迷你播控卡片。
- **核心功能闭环**：发现频道与推荐流、专辑/声音搜索、专辑详情与 100 集分段选集、书单（听更新 / 订阅 / 历史 / 收藏）、完整播放控制（倍速 0.5×–3.0×、定时关闭、音质切换、跳过头尾[智能静音/手动比例]、待播队列分段）、听时余额查询/福利任务/自动领取、账号登录（Cookie 导入 + 手机号短信验证码 + 原生 WKWebView 极验滑块）、云端与本地双端进度同步、系统媒体中心与菜单栏常驻后台播放。
- **克制取舍**：不纳入评论区、主播主页、复杂主题编辑器与备份包导入，保持轻巧专注。

## 2. 模块架构
- `XMProCore`（Swift 静态库，无 UI 依赖）：
  - `Crypto/`：`XmlyCrypto`（AES-128-ECB-PKCS7、MD5、TAC 票据、活动签名）、`ServerClock`（响应 Date/timestamp 校时）、`RSAMobileEncryptor`（1024 位 RSA PKCS#1 v1.5 手机号加密）。
  - `Network/`：`XmlyHttp`（`URLSession` 封装、429 源级冷却、只读重试/写入不重放、CDN 302 手动追踪并升级 HTTPS、响应体上限保护）。
  - `API/`：`XmlyClient`、`XmlyExperience`、`XmlyHistory`、`XmlyRewards`、`XmlyLogin`。
  - `Models/`：`Credentials`、`Track`、`Album`、`AlbumPage`、`SearchPage`、`Home*`、`Subscription*`、`Update*`、`HistoryRecord`、`Quota`、`ResolvedAudio`、`UserProfile`、`PlayPosition`、`XmlyException`。
  - `Storage/`：`KeychainCredentialStore`（凭据安全存入 macOS Keychain，带降级安全文件保护与单测内存实现）、`AppPreferencesStore`（JSON 偏好与本地专辑最近进度）。
- `XMProMac`（SwiftUI + AppKit 原生应用）：
  - `Player/`：`AudioPlayerEngine`（`AVPlayer` + 0.5×–3.0× 变速不变调 + 手动头尾比例跳过 + 实时静音检测跳过 + 睡眠定时 + 自动断流重连）、`NowPlayingBridge`（`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`）。
  - `State/`：`PlaybackClock`（独立 0.5s 进度时钟，隔离重绘）、`PlayerStore`（播放序号防竞态、队列分段、云端/本地进度同步）、`AppStore`（发现、搜索、专辑、书单、账号、听时自动补充）。
  - `Views/`：侧边栏主壳、发现页、搜索页、专辑详情与 100 集分段网格、书单页、悬浮毛玻璃播控条、沉浸播放抽屉（含队列/跳过/音质/定时）、菜单栏迷你播控卡片、账号听时与登录 Sheet（含受限 CSP 的 `WKWebView` 极验弹窗）。
  - `App/`：`XMProMacApp`、`AppDelegate`（关闭主窗保活、从菜单栏秒唤起主窗、空格暂停/播放等快捷键）。

## 3. 安全与容错策略
- 凭据（`token`、`deviceId`）绝不打日志、不进明文备份，存储于 macOS Keychain。
- 所有写请求（听时领取、删除历史、短信发送、订阅/收藏）均设置 `readOnly = false`，失败不自动重放。
- 播放切换使用递增 `playRequestId`，慢返回的旧解析自动丢弃。
- 书单四栏并行请求、各自容错，单栏短暂失败不抹掉已缓存列表。

## 4. 验证计划
- `XMProCoreTests` 使用 Swift 6 Testing 框架对拍原仓库全部加密、签名、Cookie 解析、标识符、历史签名测试向量。
- 运行 `swift test` 与 `swift build -c release` 确保零错误零警告阻塞。
- 对真实公开接口执行一次只读连通性验证（频道、搜索、专辑、音频直链解密）。
- 打包带自定义矢量图标与 ad-hoc 签名的 `dist/XMPro.app` 并实测启动稳定。
