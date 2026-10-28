import SwiftUI
import AppKit

enum AtlasStyle {
    static let ink = Color(red: 0.028, green: 0.050, blue: 0.10)
    static let secondary = Color(red: 0.66, green: 0.73, blue: 0.85)
    static let mint = Color(red: 0.53, green: 0.94, blue: 0.82)
    static let blue = Color(red: 0.57, green: 0.73, blue: 1)
    static let violet = Color(red: 0.75, green: 0.65, blue: 1)
    static let gold = Color(red: 0.96, green: 0.83, blue: 0.59)
    static let line = Color.white.opacity(0.12)
}

struct LocalImage: View {
    let name: String
    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable() }
        }
    }
}

struct AtlasBackdrop: View {
    var body: some View {
        GeometryReader { bounds in
            ZStack {
                AtlasStyle.ink
                LocalImage(name: "glass-ribbons")
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped().opacity(0.64)
                LinearGradient(colors: [AtlasStyle.ink.opacity(0.1), AtlasStyle.ink.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            }
        }.ignoresSafeArea()
    }
}

struct GlassPanel<Content: View>: View {
    let accent: Color
    var selected = false
    var padding: CGFloat = 32
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.22).opacity(0.91), Color(red: 0.045, green: 0.068, blue: 0.13).opacity(0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(LinearGradient(colors: [accent.opacity(selected ? 0.9 : 0.5), .white.opacity(0.05), accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }
}

struct SectionHeading: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 26, weight: .medium))
                .foregroundStyle(accent).frame(width: 52, height: 52)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 28, weight: .semibold))
                Text(subtitle).font(.system(size: 18, weight: .medium)).foregroundStyle(AtlasStyle.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct NumberLine: View {
    let value: Double?
    var decimals = 0
    var unit = ""
    var size: CGFloat = 42
    var tint: Color = .white
    var prefix = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !prefix.isEmpty && value != nil {
                Text(prefix).font(.system(size: size * 0.58, weight: .medium, design: .rounded))
            }
            Text(HomeSnapshot.number(value, decimals: decimals))
                .font(.system(size: size, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit).font(.system(size: max(18, size * 0.32), weight: .medium))
                    .foregroundStyle(tint.opacity(0.72))
            }
        }.foregroundStyle(tint)
    }
}

struct EnergyPeriod: View {
    let title: String
    let energy: Double?
    let cost: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 21, weight: .medium)).foregroundStyle(AtlasStyle.secondary)
            NumberLine(value: energy, decimals: 2, unit: "度", size: 38)
            HStack(spacing: 12) {
                Text("电费估算").font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
                NumberLine(value: cost, decimals: 2, size: 26, tint: AtlasStyle.gold, prefix: "¥")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EnergyPanel: View {
    let data: HomeSnapshot
    var selected = false
    var body: some View {
        GlassPanel(accent: AtlasStyle.gold, selected: selected, padding: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(icon: "bolt.fill", title: "家庭用电", subtitle: "住宅电表 ＋ 中控室电表", accent: AtlasStyle.gold)
                HStack(alignment: .center, spacing: 30) {
                    VStack(alignment: .leading, spacing: 0) {
                        NumberLine(value: data.power, unit: "W", size: 96, tint: AtlasStyle.gold)
                            .accessibilityLabel("住宅合计实时功率 " + HomeSnapshot.number(data.power) + " 瓦")
                    }.frame(width: 308, height: 142, alignment: .leading)
                    Rectangle().fill(AtlasStyle.line).frame(width: 1, height: 92)
                    EnergyPeriod(title: "今日合计", energy: data.energyToday, cost: data.costToday)
                    EnergyPeriod(title: "本月合计", energy: data.energyMonth, cost: data.costMonth)
                }
                Rectangle().fill(AtlasStyle.line).frame(height: 1)
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        Text("分户明细").gridColumnAlignment(.leading)
                        Text("实时功率")
                        Text("今日用电")
                        Text("今日估算")
                        Text("本月用电")
                        Text("本月估算")
                    }.font(.system(size: 18, weight: .medium)).foregroundStyle(AtlasStyle.secondary)
                    ForEach(data.accounts) { account in
                        GridRow {
                            HStack(spacing: 10) {
                                Circle().fill(account.name == "住宅电表" ? AtlasStyle.gold : AtlasStyle.blue).frame(width: 6, height: 6)
                                Text(account.name).font(.system(size: 22, weight: .medium))
                            }
                            NumberLine(value: account.power, unit: "W", size: 28, tint: AtlasStyle.gold).frame(maxWidth: .infinity, alignment: .trailing)
                            accountValue(account.todayEnergy, decimals: 2, unit: "度")
                            accountValue(account.todayCost, decimals: 2, prefix: "¥")
                            accountValue(account.monthEnergy, decimals: 2, unit: "度")
                            accountValue(account.monthCost, decimals: 2, prefix: "¥")
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private func accountValue(_ value: Double?, decimals: Int, unit: String = "", prefix: String = "") -> some View {
        NumberLine(value: value, decimals: decimals, unit: unit, size: 25, prefix: prefix)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct EnvironmentPanel: View {
    let data: HomeSnapshot
    var selected = false
    var body: some View {
        GlassPanel(accent: AtlasStyle.mint, selected: selected, padding: 28) {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(icon: "leaf", title: "室内环境", subtitle: "室内传感器 · 客厅空气净化器", accent: AtlasStyle.mint)
                HStack(alignment: .top, spacing: 20) {
                    environmentValue("温度", data.temperature, decimals: 1, unit: "°C", tint: AtlasStyle.mint)
                    environmentValue("湿度", data.humidity, unit: "%", tint: AtlasStyle.blue)
                    environmentValue("PM2.5", data.pm25, unit: "μg/m³", tint: .white)
                }
                Rectangle().fill(AtlasStyle.line).frame(height: 1)
                ClimateHistoryChart(points: data.history, isStale: data.state == .stale, caption: data.historyNote)
                Text(data.pmNote)
                    .font(.system(size: 16)).foregroundStyle(data.pm25 == nil ? Color.orange : AtlasStyle.secondary)
            }
        }
    }
    private func environmentValue(_ label: String, _ value: Double?, decimals: Int = 0, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 20)).foregroundStyle(AtlasStyle.secondary)
            NumberLine(value: value, decimals: decimals, unit: unit, size: 44, tint: tint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GaragePanel: View {
    let data: HomeSnapshot
    var body: some View {
        GlassPanel(accent: AtlasStyle.blue, padding: 26) {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(icon: "ev.charger", title: "车库合计", subtitle: "电瓶车支路 ＋ 已记录家充", accent: AtlasStyle.blue)
                GaragePeriod(title: "今日合计", energy: data.garageEnergyToday, cost: data.garageCostToday)
                Rectangle().fill(AtlasStyle.line).frame(height: 1)
                GaragePeriod(title: "本月合计", energy: data.garageEnergyMonth, cost: data.garageCostMonth)
            }
        }
    }
}

struct GaragePeriod: View {
    let title: String
    let energy: Double?
    let cost: Double?
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
                NumberLine(value: energy, decimals: 2, unit: "度", size: 34)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 8) {
                Text("电费估算").font(.system(size: 17)).foregroundStyle(AtlasStyle.secondary)
                NumberLine(value: cost, decimals: 2, size: 28, tint: AtlasStyle.blue, prefix: "¥")
            }
        }
    }
}

struct ChargingPanel: View {
    let data: HomeSnapshot
    var body: some View {
        GlassPanel(accent: AtlasStyle.mint, padding: 26) {
            VStack(alignment: .leading, spacing: 17) {
                SectionHeading(icon: "car.side", title: "特斯拉家充", subtitle: data.chargeStatus, accent: AtlasStyle.mint)
                HStack(alignment: .firstTextBaseline) {
                    NumberLine(value: data.carBattery, unit: "%", size: 52, tint: AtlasStyle.mint)
                    Spacer()
                    Text("目标 " + HomeSnapshot.number(data.chargeTarget) + "%")
                        .font(.system(size: 19)).foregroundStyle(AtlasStyle.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        if let battery = data.carBattery {
                            Capsule().fill(AtlasStyle.mint.opacity(0.8))
                                .frame(width: geometry.size.width * min(max(battery, 0), 100) / 100)
                        }
                        if let target = data.chargeTarget {
                            Rectangle().fill(.white.opacity(0.9)).frame(width: 2, height: 16)
                                .offset(x: (geometry.size.width - 2) * min(max(target, 0), 100) / 100)
                        }
                    }
                }.frame(height: 10)
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("家充功率").font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
                        NumberLine(value: data.chargingPower, decimals: 1, unit: "kW", size: 31)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("预估续航").font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
                        NumberLine(value: data.carRange, unit: "km", size: 31)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct NASPanel: View {
    let data: HomeSnapshot
    var selected = false
    var body: some View {
        GlassPanel(accent: AtlasStyle.violet, selected: selected, padding: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(icon: "server.rack", title: "NAS", subtitle: "Synology DS1525+", accent: AtlasStyle.violet)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("系统温度").font(.system(size: 17)).foregroundStyle(AtlasStyle.secondary)
                        NumberLine(value: data.nasTemperature, unit: "°C", size: 32)
                    }
                }
                HStack(spacing: 26) {
                    compactMeter("CPU", data.cpu, AtlasStyle.blue)
                    compactMeter("内存", data.memory, AtlasStyle.violet)
                }
                HStack(spacing: 26) {
                    compactMeter("卷 1 已用", data.volume1Used, AtlasStyle.blue)
                    compactMeter("卷 3 已用", data.volume3Used, AtlasStyle.violet)
                }
                Rectangle().fill(AtlasStyle.line).frame(height: 1)
                HStack(spacing: 26) {
                    transfer("上传", icon: "arrow.up", value: data.nasUpload)
                    transfer("下载", icon: "arrow.down", value: data.nasDownload)
                }
                Text(data.nasNote).font(.system(size: 14)).foregroundStyle(AtlasStyle.secondary).lineLimit(1)
            }
        }
    }
    private func compactMeter(_ title: String, _ value: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
                Spacer()
                NumberLine(value: value, unit: "%", size: 27)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    if let value {
                        Capsule().fill(tint.opacity(0.8)).frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
                    }
                }
            }.frame(height: 5)
        }.frame(maxWidth: .infinity)
    }
    private func transfer(_ title: String, icon: String, value: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
            Spacer(minLength: 0)
            NumberLine(value: value, decimals: 1, unit: "MB/s", size: 29)
        }.frame(maxWidth: .infinity)
    }
}

struct WeatherSummary: View {
    let data: HomeSnapshot
    var body: some View {
        HStack(spacing: 23) {
            Image(systemName: data.weatherSymbol)
                .symbolRenderingMode(.hierarchical).font(.system(size: 41)).foregroundStyle(AtlasStyle.gold)
            weatherValue("今日天气 · " + data.weatherText, value: data.outdoorTemperature, unit: "°C")
            Rectangle().fill(AtlasStyle.line).frame(width: 1, height: 49)
            weatherValue("风速", value: data.windSpeed, decimals: 1, unit: "m/s")
            weatherValue("室外 PM2.5", value: data.outdoorPM25, unit: "μg/m³")
        }.padding(.horizontal, 25).padding(.vertical, 17)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.13)))
    }
    private func weatherValue(_ label: String, value: Double?, decimals: Int = 0, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
            NumberLine(value: value, decimals: decimals, unit: unit, size: 32)
        }
    }
}

struct UsageMeter: View {
    let title: String
    let value: Double?
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 21)).foregroundStyle(AtlasStyle.secondary)
                Spacer()
                NumberLine(value: value, unit: "%", size: 34)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    if let value {
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.6), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
                    }
                }
            }.frame(height: 8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AtlasBrand: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "house.fill").font(.system(size: 36, weight: .medium))
                .foregroundStyle(AtlasStyle.mint)
                .frame(width: 72, height: 72)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 8) {
                Text("家庭概览").font(.system(size: 40, weight: .semibold))
                Text("HOME ATLAS").font(.system(size: 15, weight: .semibold, design: .rounded)).tracking(4).foregroundStyle(AtlasStyle.secondary)
            }
        }
    }
}

/// A single coordinate system keeps the brand, date and weather aligned while resizing.
struct AtlasHeader: View {
    let data: HomeSnapshot
    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            AtlasBrand()
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 10) {
                Text(data.dateText).font(.system(size: 23, weight: .medium))
                Text(data.status).font(.system(size: 18)).foregroundStyle(AtlasStyle.secondary)
            }
            WeatherSummary(data: data)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    }
}

struct OverviewScene: View {
    let data: HomeSnapshot
    var body: some View {
        ZStack {
            AtlasBackdrop()
            VStack(spacing: 24) {
                AtlasHeader(data: data).frame(height: 104).padding(.bottom, 12)
                HStack(spacing: 24) {
                    EnergyPanel(data: data).frame(width: 1028)
                    EnvironmentPanel(data: data)
                }.frame(height: 450)
                HStack(spacing: 24) {
                    GaragePanel(data: data).frame(width: 502)
                    ChargingPanel(data: data).frame(width: 502)
                    NASPanel(data: data)
                }.frame(height: 328)
            }.padding(.horizontal, 80).padding(.vertical, 40)
        }.foregroundStyle(.white).frame(width: 1920, height: 1080)
    }
}

struct AspectStage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 1920, geo.size.height / 1080)
            content.frame(width: 1920, height: 1080)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: 1920 * scale, height: 1080 * scale, alignment: .topLeading)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }.background(AtlasStyle.ink)
    }
}
