import Foundation

@main struct SiteTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ ok: Bool, _ message: String) {
            checks += 1
            guard ok else { fatalError("FAIL: " + message) }
        }
        check(ProbeSite.all.count == 6 && Set(ProbeSite.all.map(\.id)).count == 6, "six selected sites")
        check(ProbeSite.all.prefix(6).map(\.id) == ["Google", "GitHub", "YouTube", "ChatGPT", "Claude", "bilibili"], "menu choices")
        check(ProbeSite.all.allSatisfy { URL(string: $0.url)?.scheme == "https" }, "HTTPS targets")
        let success = SiteReading.decode(output: "200 0.1234", exitCode: 0)
        check(success.milliseconds == 123 && success.reachable, "success ms")
        let blocked = SiteReading.decode(output: "403 0.487", exitCode: 0)
        check(blocked.milliseconds == 487 && !blocked.reachable && blocked.status == "受限", "restricted still shows real latency")
        check(!SiteReading.decode(output: "429 0.3", exitCode: 0).reachable, "rate limit not green")
        check(SiteReading.decode(output: "302 0.2", exitCode: 0).reachable, "redirect response no follow")
        check(SiteReading.decode(output: "500 0.9", exitCode: 0).status == "HTTP 500", "server error")
        let timeout = SiteReading.decode(output: "000 0.0", exitCode: 28)
        check(timeout.status == "超时" && timeout.milliseconds == nil, "timeout not made-up latency")
        check(SiteReading.decode(output: "000 0.0", exitCode: 60).status == "TLS 错误", "TLS enforced")
        check(SiteReading.decode(output: "000 0.0", exitCode: 7).milliseconds == nil, "connection failure")
        check(SiteReading.decode(output: "200 nan", exitCode: 0).milliseconds == nil, "nan rejected")
        check(SiteRoute.proxyPort(["mixed-port": 7890, "port": 8888]) == 7890, "actual mixed port priority")
        check(SiteRoute.proxyPort(["mixed-port": 0, "port": 8888]) == 8888, "http fallback")
        check(SiteRoute.proxyPort(["mixed-port": true, "port": 99999]) == nil, "invalid ports rejected")
        check(SiteRoute.proxy(7890).arguments == ["--proxy", "http://127.0.0.1:7890", "--noproxy", ""], "FlClash explicit proxy no bypass")
        check(SiteRoute.tunnel("utun7", "test").arguments.suffix(2) == ["--interface", "if!utun7"], "SR strictly bound to identified interface")
        check(SiteRoute.tunnel("utun7", "one") != SiteRoute.tunnel("utun7", "two"), "reconnect invalidates cached readings")
        check(CardSize.medium.dimensions.width == 344 && CardSize.medium.dimensions.height == 164, "medium preserved")
        check(CardSize.large.dimensions.height == 344 && CardSize.small.dimensions.width == 220, "size definitions")
        // Fail closed when an identified interface disappears; must not silently
        // use the normal network. This makes no remote HTTP connection.
        let failed = await SiteProbeProcess().run(site: ProbeSite.all[0], route: .tunnel("utun999999", "fixture"))
        check(failed.milliseconds == nil && failed.status == "连接失败", "missing tunnel does not fall back")
        // Disabled/small views must not start the full list; disconnected states
        // have no site readings, even when a list had been selected earlier.
        let monitor = SiteLatencyMonitor()
        monitor.configure(large: true, menuSite: "Google", snapshot: MonitorSnapshot())
        check(monitor.readings.isEmpty && monitor.routeLabel.contains("未连接"), "offline no probe")
        monitor.configure(large: false, menuSite: "GitHub", snapshot: MonitorSnapshot(client: .shadowrocket))
        check(monitor.readings.isEmpty && monitor.routeLabel.contains("Shadowrocket"), "source change no stale readings")
        monitor.stop()
        let now = Date()
        let old = SiteReading.decode(output:"403 0.343",exitCode:0,at:now.addingTimeInterval(-60))
        let pending = old.refreshing(at:now)
        check(pending.busy && pending.milliseconds == 343 && pending.status == "受限" && pending.httpCode == 403,"refresh retains result and color")
        check(old.refreshing(at:now.addingTimeInterval(61)).milliseconds == nil,"expired sample not retained")
        check(SiteReading().refreshing(at:now).busy,"first probe remains pending")
        check(SiteReading.decode(output:"000 0.0",exitCode:28,at:now).milliseconds == nil,"completed failure clears prior number")
        for (seconds,text) in [(86400.0 * 64,"距到期 64 天"),(86399,"距到期 23 小时"),(3599,"距到期 60 分钟"),(1,"距到期 1 分钟"),(0,"套餐已到期"),(-1,"套餐已到期")] {
            check(SubscriptionCountdown.text(expiry:now.addingTimeInterval(seconds),now:now) == text,"expiry boundary \(seconds)")
        }
        check(SubscriptionCountdown.text(expiry:nil,now:now) == "到期时间未知","missing expiry never fabricated")
        print("Passed \(checks) site/size/routing checks")
    }
}
