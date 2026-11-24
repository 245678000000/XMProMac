import AppKit
import SwiftUI
import XMProCore

/// 管理 macOS 原生窗口关闭转入菜单栏保活、重新激活与退出清理
@MainActor
final class XMProAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var store: AppStore?
    private weak var trackedMainWindow: NSWindow?

    func attachMainWindow(_ window: NSWindow) {
        if trackedMainWindow !== window {
            trackedMainWindow = window
            window.delegate = self
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
        }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let win = trackedMainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if store?.preferences.keepRunningInMenuBar == true {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.handleApplicationWillTerminate()
    }
}

/// 用于把 SwiftUI 主窗口引用绑定给 AppDelegate 的轻量桥接器
private struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onAttach(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onAttach(window)
            }
        }
    }
}

/// 主窗口壳：苹果播客磨砂侧边栏 + 统一工具栏搜索 + 内容路由 + 悬浮毛玻璃播控条
struct MainShellView: View {
    @Bindable var store: AppStore
    let onAttachWindow: (NSWindow) -> Void

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 196, ideal: 214, max: 250)
        } detail: {
            ZStack(alignment: .bottom) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                FloatingPlayerBar(store: store, clock: store.clock)
            }
            .overlay(alignment: .top) {
                if let toast = store.toastMessage {
                    ToastBannerView(message: toast) {
                        store.toastMessage = nil
                    }
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.8), value: store.toastMessage)
                }
            }
        }
        .searchable(
            text: $store.searchQuery,
            placement: .toolbar,
            prompt: "搜索专辑、主播或声音…"
        )
        .onSubmit(of: .search) {
            Task { await store.performSearch(reset: true) }
        }
        .onChange(of: store.searchQuery) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.showingSearchResults {
                store.showingSearchResults = false
            }
        }
        .sheet(isPresented: $store.showPlayerDrawer) {
            PlayerDrawerSheet(store: store, clock: store.clock)
        }
        .sheet(isPresented: $store.showLoginSheet) {
            LoginSheetView(store: store)
        }
        .background(WindowAccessor(onAttach: onAttachWindow))
        .frame(minWidth: 920, minHeight: 620)
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { store.selectedSection },
                set: { next in
                    store.selectedSection = next
                    store.openedAlbumId = nil
                    store.showingSearchResults = false
                }
            )) {
                Section("浏览") {
                    sidebarRow(.discover)
                }

                Section("我的书单") {
                    sidebarRow(.updates)
                    sidebarRow(.subscriptions)
                    sidebarRow(.history)
                    sidebarRow(.favorites)
                }

                Section("账户") {
                    sidebarRow(.account)
                }
            }
            .listStyle(.sidebar)

            Divider().opacity(0.4)

            // 侧边栏底部极简账号与听时胶囊
            Button {
                if store.signedIn {
                    store.selectedSection = .account
                    store.openedAlbumId = nil
                    store.showingSearchResults = false
                } else {
                    store.showLoginSheet = true
                }
            } label: {
                HStack(spacing: 10) {
                    if store.signedIn {
                        ArtworkImageView(urlString: store.profile?.avatarUrl, cornerRadius: 15, shadowRadius: 2)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(store.profile?.nickname.isEmpty == false ? store.profile!.nickname : "已登录")
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            Text(store.quota.map { "听时 \(TimeFormatter.quotaDuration($0.remainingSeconds))" } ?? "点击查看听时")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("登录喜马拉雅")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("同步书单与听时")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.rawValue, systemImage: section.icon)
            .font(.system(size: 13.5, weight: .medium))
            .tag(section)
    }

    @ViewBuilder
    private var detailContent: some View {
        if store.openedAlbumId != nil {
            AlbumDetailView(store: store)
        } else if store.showingSearchResults {
            SearchResultsView(store: store)
        } else {
            switch store.selectedSection {
            case .discover:
                DiscoverView(store: store)
            case .updates, .subscriptions, .history, .favorites:
                LibrarySectionView(store: store, section: store.selectedSection)
            case .account:
                AccountAndQuotaView(store: store)
            }
        }
    }
}

@main
struct XMProMacApp: App {
    @NSApplicationDelegateAdaptor(XMProAppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @State private var didBootstrap = false

    var body: some Scene {
        Window("XMPro", id: "main") {
            MainShellView(store: store) { window in
                appDelegate.store = store
                appDelegate.attachMainWindow(window)
            }
            .onAppear {
                appDelegate.store = store
                if !didBootstrap {
                    didBootstrap = true
                    store.bootstrap()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandMenu("播放") {
                Button(store.isPlaying ? "暂停" : "播放") {
                    store.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("下一集") {
                    store.playNext()
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("上一集") {
                    store.playPrevious()
                }
                .keyboardShortcut("[", modifiers: [.command])

                Divider()

                Button("快进 15 秒") {
                    store.skip(by: 15)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("快退 15 秒") {
                    store.skip(by: -15)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Divider()

                Button("打开沉浸播放与队列") {
                    if store.currentTrack != nil {
                        store.showPlayerDrawer.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }

        // 常驻菜单栏迷你播控卡片
        MenuBarExtra {
            MenuBarPlayerView(store: store, clock: store.clock) {
                appDelegate.showMainWindow()
            }
        } label: {
            Image(systemName: store.isPlaying ? "waveform.circle.fill" : "waveform.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
