import SwiftUI
import Charts

/// Daily billed cost, not a balance difference. Missing buckets are left absent.
struct CostChart: View {
    let points: [CostPoint]
    var height: CGFloat = 42
    var currency: String { points.contains { $0.currency == "USD" } ? "USD" : points.first?.currency ?? "USD" }
    var values: [CostPoint] { points.filter { $0.currency == currency } }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if values.isEmpty {
                HStack(spacing: 5) { Image(systemName: "chart.xyaxis.line"); Text("等待本月费用数据") }
                    .font(.system(size: 9)).foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: height)
            } else {
                Chart(values) { p in
                    LineMark(x: .value("日期", p.day), y: .value("费用", NSDecimalNumber(decimal: p.amount).doubleValue))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round)).foregroundStyle(mint)
                    if values.count == 1 {
                        PointMark(x: .value("日期", p.day), y: .value("费用", NSDecimalNumber(decimal: p.amount).doubleValue)).symbolSize(20).foregroundStyle(mint)
                    }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: height)
                .chartYScale(domain: .automatic(includesZero: true))
                HStack { Text("本月每日消耗 · \(currency)"); Spacer(); Text("官网明细 ↗") }.font(.system(size: 8)).foregroundStyle(muted)
            }
        }.accessibilityLabel("OpenAI 本月每日费用趋势，点击打开官方用量页")
    }
}

struct UsageBars: View {
    @ObservedObject var store: Store
    var height: CGFloat = 40
    @AppStorage("chartRange") private var range = "24h"
    var record: Record<[UsagePoint]>? { range == "24h" ? store.snapshot.hourly : store.snapshot.weekly }
    var error: String? { store.errors[range == "24h" ? "history24" : "history7"] }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text("Token 消耗").lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Button { range = range == "24h" ? "7d" : "24h" } label: {
                    Text(range == "24h" ? "24小时 ⇄" : "7天 ⇄").foregroundStyle(.cyan)
                }.buttonStyle(.plain).help("点击切换 24 小时 / 7 天，不额外请求")
            }.font(.system(size: 9)).foregroundStyle(muted)
            if let record, !record.value.isEmpty {
                Chart(record.value) { p in
                    BarMark(x: .value("时间", p.date, unit: range == "24h" ? .hour : .day), y: .value("Token", p.tokens))
                        .foregroundStyle(Color(red: 0.52, green: 0.38, blue: 0.96)).cornerRadius(2)
                }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: height)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.52, green: 0.38, blue: 0.96)).frame(height: 1.2).allowsHitTesting(false) }
                .chartYScale(domain: .automatic(includesZero: true))
                .help("\(range == "24h" ? "24 小时（含当前未完整小时）" : "7 天（UTC，含今天）") · \(compact(record.value.reduce(0) { $0 + $1.tokens })) Token · 更新 \(record.date.formatted())")
                if error != nil { Text("刷新失败 · 保留上次趋势").font(.system(size: 8)).foregroundStyle(.orange) }
            } else {
                Text(error == nil ? (record == nil ? "等待用量数据" : "此时间段暂无统计") : "趋势读取失败")
                    .font(.system(size: 9)).foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: height)
            }
        }
    }
}
