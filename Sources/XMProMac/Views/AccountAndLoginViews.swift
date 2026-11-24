import AppKit
import SwiftUI
import WebKit
import XMProCore

/// 账号、听时福利与轻量应用偏好页
struct AccountAndQuotaView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("账号与听时")
                    .font(.system(size: 22, weight: .bold))

                accountCard

                if store.signedIn {
                    quotaAndRewardsCard
                }

                preferencesCard
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }

    private var accountCard: some View {
        HStack(spacing: 16) {
            if store.signedIn {
                ArtworkImageView(urlString: store.profile?.avatarUrl, cornerRadius: 28, shadowRadius: 4)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.profile?.nickname.isEmpty == false ? store.profile!.nickname : "喜马拉雅用户")
                        .font(.system(size: 16, weight: .bold))
                    Text("UID: \(store.credentials?.uid ?? "-")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let intro = store.profile?.intro, !intro.isEmpty {
                        Text(intro)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("复制 Cookie") {
                    store.copyExportableCookie()
                }
                .buttonStyle(.bordered)

                Button("退出登录", role: .destructive) {
                    store.signOut()
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("未登录喜马拉雅账号")
                        .font(.system(size: 16, weight: .bold))
                    Text("登录后可同步订阅、历史、收藏，并解锁极速版听时额度与付费节目收听。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("立即登录") {
                    store.showLoginSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.036), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var quotaAndRewardsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前设备可用听时")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(store.quota.map { TimeFormatter.quotaDuration($0.remainingSeconds) } ?? "正在查询…")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        if store.quota?.newDevice == true {
                            Text("新设备首听保护")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await store.refreshAccountSummary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("刷新听时与任务状态")

                Button {
                    Task { await store.claimRewardsNow() }
                } label: {
                    if store.rewardsBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("立即领取听时", systemImage: "gift.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.rewardsBusy)
            }

            if !store.rewardStatusNote.isEmpty {
                Text(store.rewardStatusNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle("余额不足时在后台自动领取听时福利", isOn: $store.preferences.autoClaimRewards)
                .font(.system(size: 13))

            if !store.rewardTiers.isEmpty {
                Divider().opacity(0.45)
                Text("福利档位明细")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(store.rewardTiers) { tier in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tier.label)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tier.receiveTimeMillis > 0
                                 ? "最近到账：\(TimeFormatter.relativeDate(millis: tier.receiveTimeMillis))"
                                 : "待领取")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.036), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("轻量偏好设置")
                .font(.system(size: 15, weight: .bold))

            Toggle("关闭主窗口时退居菜单栏继续后台听书", isOn: $store.preferences.keepRunningInMenuBar)
                .font(.system(size: 13))

            HStack {
                Text("默认音质")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(
                    get: { store.preferences.quality },
                    set: { store.setQuality($0) }
                )) {
                    ForEach(["auto"] + xmlyQualities, id: \.self) { q in
                        Text(QualityLabel.title(for: q)).tag(q)
                    }
                }
                .frame(width: 170)
            }

            Toggle("跳过片头片尾（\(store.preferences.skipTrimMode.displayName)）", isOn: $store.preferences.skipTrimEnabled)
                .font(.system(size: 13))

            if store.preferences.skipTrimEnabled {
                Picker("跳过模式", selection: $store.preferences.skipTrimMode) {
                    ForEach(SkipTrimMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.036), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

/// 账号登录弹窗：支持 Cookie 导入与手机号短信登录（含原生隔离 WKWebView 极验滑块）
struct LoginSheetView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Int = 0 // 0: Cookie 导入, 1: 手机号短信
    @State private var cookieInput: String = ""
    @State private var mobileInput: String = ""
    @State private var smsCodeInput: String = ""
    @State private var challengeId: String? = nil
    @State private var busy: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showGeetestSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("登录喜马拉雅账号")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    store.loginClient.clear()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker("", selection: $tab) {
                Text("导入 Cookie").tag(0)
                Text("手机号短信登录").tag(1)
            }
            .pickerStyle(.segmented)

            if tab == 0 {
                cookieImportPanel
            } else {
                smsLoginPanel
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 440, height: 360)
        .sheet(isPresented: $showGeetestSheet) {
            GeetestChallengeSheet(captchaId: XmlyLogin.captchaId) { fields in
                showGeetestSheet = false
                sendSmsWithGeetest(fields)
            } onCancel: {
                showGeetestSheet = false
            }
        }
    }

    private var cookieImportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可直接粘贴 XMPro 导出的 Cookie 字符串（含 `1&_token` 与 `1&_device`）或 JSON 配置：")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            TextEditor(text: $cookieInput)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 112)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.6))

            HStack {
                Button("从剪贴板粘贴") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        cookieInput = text
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    submitCookie()
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("验证并登录")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var smsLoginPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入手机号后将弹出喜马拉雅官方安全滑块，请手动完成验证以发送短信验证码。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            TextField("手机号（如 13800138000）", text: $mobileInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                TextField("短信验证码", text: $smsCodeInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(challengeId == nil)

                Button(challengeId == nil ? "安全验证并发送" : "重新发送") {
                    errorMessage = nil
                    let trimmed = mobileInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count >= 6 else {
                        errorMessage = "请输入有效手机号"
                        return
                    }
                    showGeetestSheet = true
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }

            HStack {
                Spacer()
                Button {
                    verifySmsCode()
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("登录")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || challengeId == nil || smsCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            }
            .padding(.top, 4)
        }
    }

    private func submitCookie() {
        busy = true
        errorMessage = nil
        Task {
            do {
                try await store.importCookie(cookieInput)
                dismiss()
            } catch {
                errorMessage = (error as? XmlyException)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func sendSmsWithGeetest(_ fields: [String: String]) {
        busy = true
        errorMessage = nil
        Task {
            do {
                let id = try await store.loginClient.sendSms(mobile: mobileInput, geetest: fields)
                challengeId = id
                store.showToast("验证码已发送，请查收短信")
            } catch {
                errorMessage = (error as? XmlyException)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func verifySmsCode() {
        guard let cid = challengeId else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                let result = try await store.loginClient.verifySms(challengeId: cid, code: smsCodeInput)
                try await store.completeSmsLogin(result)
                dismiss()
            } catch {
                errorMessage = (error as? XmlyException)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }
}

/// 隔离式 GeeTest v4 安全滑块弹窗（由用户亲自完成人机交互，仅放行极验官方域名）
struct GeetestChallengeSheet: View {
    let captchaId: String
    let onSuccess: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var statusText: String = "正在加载安全验证…"

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("安全验证")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("关闭", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            GeetestWebViewRepresentable(
                captchaId: captchaId,
                onStatus: { statusText = $0 },
                onSuccess: onSuccess,
                onClose: onCancel
            )
            .frame(width: 360, height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .frame(width: 400, height: 420)
    }
}

private struct GeetestWebViewRepresentable: NSViewRepresentable {
    let captchaId: String
    let onStatus: (String) -> Void
    let onSuccess: ([String: String]) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(captchaId: captchaId, onStatus: onStatus, onSuccess: onSuccess, onClose: onClose)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "xmlyCaptcha")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        let html = buildHtml(captchaId: captchaId, nonce: context.coordinator.nonce)
        webView.loadHTMLString(html, baseURL: URL(string: "https://static.geetest.com"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func buildHtml(captchaId: String, nonce: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; connect-src https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; img-src data: blob: https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; style-src 'unsafe-inline' https://*.geetest.com; font-src data: https://*.geetest.com; frame-src https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>body{font:14px -apple-system,sans-serif;text-align:center;padding:16px;color:#555;background:transparent;}</style>
        </head><body><div id="box"></div>
        <script>
        (function(){
          var nonce = "\(nonce)";
          var cid = "\(captchaId)";
          function emit(kind, payload){
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.xmlyCaptcha) {
              window.webkit.messageHandlers.xmlyCaptcha.postMessage({nonce: nonce, kind: kind, payload: payload || null});
            }
          }
          function fail(){ emit('error', null); }
          function start(){
            if (typeof initGeetest4 !== 'function') { fail(); return; }
            initGeetest4({captchaId: cid, product: 'bind', language: 'zho', protocol: 'https://', onError: fail, offlineCb: fail}, function(captcha){
              captcha.onReady(function(){
                emit('ready', null);
                captcha.showCaptcha();
              }).onSuccess(function(){
                var v = captcha.getValidate();
                if (!v) { fail(); return; }
                emit('success', {
                  captcha_id: cid,
                  lot_number: v.lot_number,
                  pass_token: v.pass_token,
                  gen_time: v.gen_time,
                  captcha_output: v.captcha_output
                });
              }).onError(fail).onClose(function(){ emit('close', null); });
            });
          }
          var s = document.createElement('script');
          s.src = 'https://static.geetest.com/v4/gt4.js';
          s.onload = start; s.onerror = fail;
          document.head.appendChild(s);
        })();
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let captchaId: String
        let nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let onStatus: (String) -> Void
        let onSuccess: ([String: String]) -> Void
        let onClose: () -> Void
        private var finished = false

        init(
            captchaId: String,
            onStatus: @escaping (String) -> Void,
            onSuccess: @escaping ([String: String]) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.captchaId = captchaId
            self.onStatus = onStatus
            self.onSuccess = onSuccess
            self.onClose = onClose
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !finished,
                  let dict = message.body as? [String: Any],
                  dict["nonce"] as? String == nonce,
                  let kind = dict["kind"] as? String else { return }

            switch kind {
            case "ready":
                onStatus("请完成下方安全验证后继续")
            case "error":
                onStatus("安全验证加载失败，请关闭重试")
            case "close":
                finished = true
                onClose()
            case "success":
                guard let payload = dict["payload"] as? [String: String] else {
                    onStatus("验证结果格式无效")
                    return
                }
                for field in XmlyLogin.requiredCaptchaFields where payload[field]?.isEmpty != false {
                    onStatus("验证结果缺少字段")
                    return
                }
                finished = true
                onSuccess(payload)
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            let host = url.host?.lowercased() ?? ""
            let allowed = url.scheme == "https" && ["geetest.com", "geevisit.com", "gsensebot.com"].contains {
                host == $0 || host.hasSuffix(".\($0)")
            }
            decisionHandler(allowed ? .allow : .cancel)
        }
    }
}
