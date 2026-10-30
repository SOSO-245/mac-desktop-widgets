import AppKit
import SwiftUI
import WebKit

/// Isolated website session. Authentication is retained only in this app's Keychain.
/// No password, page storage, HTML, or cookie values are written to disk or logs.
@MainActor final class SiliconWebLogin: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = SiliconWebLogin()
    private static let account = "siliconflow.web.session.v1"
    static let hosts: Set<String> = ["cloud.siliconflow.cn", "account.siliconflow.cn"]
    @Published var status = "请在官方页面登录，进入费用账单后点击保存登录。"
    @Published var remember = true
    @Published private(set) var hasSavedSession = false
    private var window: NSWindow?
    var onReading: ((SiliconPageReading) -> Void)?
    var onForget: (() -> Void)?
    private var revision = 0
    private(set) var dataStore = WKWebsiteDataStore.nonPersistent()
    lazy var web: WKWebView = {
        let c = WKWebViewConfiguration(); c.websiteDataStore = dataStore
        let v = WKWebView(frame: .zero, configuration: c)
        v.navigationDelegate = self; v.uiDelegate = self
        return v
    }()
    static func allowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && hosts.contains(url.host ?? "") && url.user == nil && url.password == nil
    }
    private override init() { super.init() }
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            w.title = "硅基流动 · 官方登录与账单"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SiliconLoginPage(model: self)); w.center(); window = w
            Task { await restoreAndOpen() }
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    private func restoreAndOpen() async {
        let token = revision
        do {
            if let saved = try Vault.read(Self.account), let data = Data(base64Encoded: saved),
               let rows = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String:Any]] {
                for row in rows {
                    guard token == revision else { return }
                    let props = Dictionary(uniqueKeysWithValues: row.map { (HTTPCookiePropertyKey(rawValue: $0.key), $0.value) })
                    if let cookie = HTTPCookie(properties: props), Self.isSessionCookie(cookie) {
                        await dataStore.httpCookieStore.setCookie(cookie)
                    }
                }
                guard token == revision else { return }
                hasSavedSession = true; status = "已恢复本机登录；若官网要求验证，请重新登录。"
            }
        } catch { status = "未能恢复登录，请重新登录；钥匙串可能需要授权。" }
        guard token == revision else { return }
        web.load(URLRequest(url: URL(string: "https://cloud.siliconflow.cn/")!))
    }
    private static func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cookie.isSecure && cookie.isHTTPOnly && (domain == "siliconflow.cn" || hosts.contains(domain)) && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }
    private static func sessionIdentity(_ rows: [[String:Any]]) -> [String:String] {
        var result: [String:String] = [:]
        for row in rows {
            guard let name = row[HTTPCookiePropertyKey.name.rawValue] as? String,
                  let domain = row[HTTPCookiePropertyKey.domain.rawValue] as? String,
                  let path = row[HTTPCookiePropertyKey.path.rawValue] as? String,
                  let value = row[HTTPCookiePropertyKey.value.rawValue] as? String else { continue }
            result[domain + "|" + path + "|" + name] = value
        }
        return result
    }
    func saveLogin() {
        guard web.url?.host == "cloud.siliconflow.cn", Self.allowed(web.url) else {
            status = "请先完成登录，进入官方控制台后再保存。"; return
        }
        guard remember else { status = "本次登录只在当前运行期间保留。"; return }
        let token = revision
        Task {
            let cookies = await dataStore.httpCookieStore.allCookies()
            guard token == revision else { return }
            let rows = cookies.filter(Self.isSessionCookie).compactMap { cookie -> [String:Any]? in
                cookie.properties.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
            }
            guard !rows.isEmpty else { status = "尚未发现可保存的安全登录会话，请完成登录后重试。"; return }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: rows, format: .binary, options: 0)
                let encoded = data.base64EncodedString()
                if let previous = try Vault.read(Self.account), let old = Data(base64Encoded: previous),
                   let oldRows = try PropertyListSerialization.propertyList(from: old, format: nil) as? [[String:Any]],
                   Self.sessionIdentity(oldRows) != Self.sessionIdentity(rows) { onForget?() }
                try Vault.save(encoded, account: Self.account)
                hasSavedSession = true
                status = "登录会话已保存到本机钥匙串。请停留在费用账单页，以便验证同步字段。"
            } catch { status = "登录保存失败，请检查钥匙串授权。" }
        }
    }
    // Reads only the two financial regions observed on the official console.
    // It neither requests internal endpoints nor collects page storage or API keys.
    func capture() {
        let token = revision
        guard Self.allowed(web.url), web.url?.host == "cloud.siliconflow.cn" else {
            status = "登录已失效，请重新登录；此前缓存仍保留。"; return
        }
        let script = #"""
        (() => {
            const visible = e => !!e && e.getClientRects().length > 0;
            const text = e => (e?.innerText || '').replace(/\s+/g,' ').trim();
            const leaves = [...document.querySelectorAll('span,div,p')].filter(e => e.children.length === 0 && visible(e));
            const authenticated = [...document.querySelectorAll('a')].some(e => visible(e) && new URL(e.getAttribute('href') || '', location.href).pathname === '/me/bills');
            let values = [];
            if (location.pathname === '/me/expensebill') {
                values = [...document.querySelectorAll('[role="tab"]')].filter(e => visible(e) && /^余额\s*¥/.test(text(e))).map(e => ({kind:'balance',text:text(e)}));
            } else if (location.pathname === '/me/bills') {
                const month = [...document.querySelectorAll('input[placeholder="选择月份"]')].filter(visible);
                const labels = leaves.filter(e => text(e) === '账单金额');
                const unfiltered = leaves.some(e => text(e) === '请选择产品');
                if (month.length === 1 && labels.length === 1) {
                    const label = labels[0];
                    const candidates = [label.nextElementSibling,
                        label.parentElement?.children.length === 1 ? label.parentElement.nextElementSibling : null]
                        .filter(visible).map(text).filter(t => /^¥\s*-?[0-9]+(?:\.[0-9]+)?$/.test(t));
                    const amounts = [...new Set(candidates)];
                    if (amounts.length === 1) values = [{kind:'monthly',text:amounts[0],period:month[0].value,unfiltered}];
                }
            }
            return {authenticated,values};
        })()
        """#
        web.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor in
                guard let self, token == self.revision else { return }
                do {
                    guard error == nil, let raw = result as? [String:Any] else { throw APIProblem(message: "网页读取失败，保留缓存") }
                    let reading = try SiliconPageReading.parse(raw, url: self.web.url)
                    self.onReading?(reading)
                    self.status = "已缓存官网显示的" + (reading.kind == "balance" ? "余额" : (reading.period ?? "") + "账单金额") + " · " + Date().formatted(date: .omitted, time: .shortened)
                } catch { self.status = (error as? APIProblem)?.message ?? "页面无法识别，保留缓存" }
            }
        }
    }
    func forget() {
        revision += 1; web.stopLoading()
        do { try Vault.delete(Self.account) }
        catch { status = "钥匙串清除失败，请重试。"; return }
        hasSavedSession = false; onForget?()
        let oldStore = dataStore
        web.navigationDelegate = nil; web.uiDelegate = nil
        dataStore = .nonPersistent()
        let c = WKWebViewConfiguration(); c.websiteDataStore = dataStore
        web = WKWebView(frame: .zero, configuration: c); web.navigationDelegate = self; web.uiDelegate = self
        window?.contentView = NSHostingView(rootView: SiliconLoginPage(model: self))
        Task {
            await oldStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            web.load(URLRequest(url: URL(string: "https://cloud.siliconflow.cn/")!))
            status = "本机登录会话已清除。"
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let target = navigationAction.targetFrame
        if target == nil || target?.isMainFrame == true {
            guard Self.allowed(navigationAction.request.url) else {
                status = "请使用官方控制台或账号登录页；此窗口不打开其他网站。"; decisionHandler(.cancel); return
            }
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if Self.allowed(navigationAction.request.url) { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status = "官网暂时无法加载，请检查网络后重新打开。" }
    }
}
private struct SiliconLoginPage: View {
    @ObservedObject var model: SiliconWebLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("硅基流动官网").font(.headline)
                Spacer()
                Toggle("记住登录（本机钥匙串）", isOn: $model.remember).toggleStyle(.checkbox)
                Button("保存登录") { model.saveLogin() }
                Button("缓存当前账单") { model.capture() }
                Button("退出并清除登录") { model.forget() }
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("仅保留安全登录会话；不会读取或保存输入的密码。进入余额页，或费用明细选择“按月”，点击“缓存当前账单”。只缓存当前网页显示值，不估算费用。").font(.caption).foregroundStyle(.secondary)
            SiliconWebView(web: model.web)
        }.padding(14).frame(minWidth: 800, minHeight: 600)
    }
}
private struct SiliconWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
