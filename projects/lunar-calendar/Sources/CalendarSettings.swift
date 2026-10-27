import AppKit
import SwiftUI
import ServiceManagement

struct CalendarGeneralSettings:View {
    @ObservedObject var model:CalendarModel
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("启动与运行").font(.headline)
            Toggle("登录时自动启动",isOn:Binding(get:{model.autoStart},set:model.setAutoStart))
            if !model.startupNote.isEmpty {Text(model.startupNote).font(.callout).foregroundStyle(.secondary)}
            if SMAppService.mainApp.status == .requiresApproval {Button("打开系统登录项设置") {SMAppService.openSystemSettingsLoginItems()}}
            Text("万年历保持独立运行。关闭日历窗口后，菜单栏与桌面卡片继续可用。").font(.callout).foregroundStyle(.secondary)
            Divider()
            CalendarSyncSettings(sync:model.cloudSync)
            Divider()
            Text("桌面小组件").font(.headline)
            Text("右键桌面 → 编辑小组件 → 搜索“万年历”，可添加小、中、大三种系统小组件。").font(.callout).foregroundStyle(.secondary)
            Text("假期数据来自 holiday-cn，按国务院通知整理。未收录年份不推算调休。").font(.callout).foregroundStyle(.secondary)
            Link("查看节假日数据来源",destination:URL(string:"https://github.com/NateScarlet/holiday-cn")!)
        }.onAppear {model.autoStart=SMAppService.mainApp.status == .enabled}
    }
}

struct CalendarDesktopSettings:View {
    @ObservedObject var desktop:LiveDesktopCard
    @AppStorage("calendarWeather.clock12Hour") private var clock12Hour=false
    @AppStorage("calendarWeather.trendRange") private var trendRange=0
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Toggle("显示桌面卡片",isOn:Binding(get:{!desktop.hidden},set:desktop.setVisible))
            Picker("卡片尺寸",selection:Binding(get:{desktop.size},set:desktop.setSize)) {
                Text("小号").tag("small");Text("中号").tag("medium");Text("大号").tag("large")
            }.pickerStyle(.segmented)
            Picker("中号内容",selection:Binding(get:{desktop.weatherLayout ? "weather":"calendar"},set:desktop.setLayout)) {
                Text("月历").tag("calendar");Text("日期与天气").tag("weather")
            }.pickerStyle(.segmented)
            Text("切换中号内容会同时将卡片调整为中号。").font(.caption).foregroundStyle(.secondary)
            Toggle("锁定卡片位置",isOn:Binding(get:{desktop.locked},set:desktop.setLocked))
            Toggle("置于其他窗口上方",isOn:Binding(get:{desktop.top},set:desktop.setTop))
            Button("移到屏幕中央",action:desktop.centerCard)
            Divider()
            Toggle("天气卡片使用 12 小时制",isOn:$clock12Hour)
            Picker("天气趋势",selection:$trendRange) {ForEach(WeatherTrendRange.allCases,id:\.rawValue) {range in Text(range.title).tag(range.rawValue)}}.pickerStyle(.segmented)
            Divider()
            DesktopAppearanceSettings(model:.shared)
        }
    }
}

struct CalendarMenuDefaults:View {
    @ObservedObject var model:CalendarModel
    private func binding<Value>(_ key:WritableKeyPath<CalendarUserData,Value>)->Binding<Value> {
        Binding(get:{model.data[keyPath:key]},set:{value in var next=model.data;next[keyPath:key]=value;_ = model.apply(next)})
    }
    private var iconColor:Binding<Color> {
        Binding(get:{Color(calendarHex:model.data.menuIcon.color)},set:{value in
            guard let color=NSColor(value).usingColorSpace(.deviceRGB) else{return}
            var next=model.data;next.menuIcon.color=String(format:"#%02X%02X%02X",Int(color.redComponent*255),Int(color.greenComponent*255),Int(color.blueComponent*255));_ = model.apply(next)
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("默认显示").font(.headline)
            Text("未启用下方自定义菜单栏时，使用这里的图标与显示项目。").font(.caption).foregroundStyle(.secondary)
            Picker("默认图标",selection:binding(\.menuIcon.symbol)) {
                ForEach(MenuIconPreferences.choices,id:\.symbol) {choice in Label(choice.title,systemImage:choice.symbol).tag(choice.symbol)}
            }
            Picker("图标配色",selection:binding(\.menuIcon.mode)) {
                Text("跟随系统").tag("system");Text("自选颜色").tag("custom");Text("彩色图标").tag("colorful")
            }.pickerStyle(.segmented)
            if model.data.menuIcon.mode=="custom" {ColorPicker("图标颜色",selection:iconColor,supportsOpacity:false)}
            HStack(spacing:18) {
                Toggle("日期",isOn:binding(\.showDate));Toggle("年份",isOn:binding(\.showYear)).disabled(!model.data.showDate);Toggle("星期",isOn:binding(\.showWeekday))
            }
            HStack(spacing:18) {Toggle("农历",isOn:binding(\.showLunar));Toggle("假期名称",isOn:binding(\.showHoliday))}
            if !model.storageNote.isEmpty {Text(model.storageNote).font(.caption).foregroundStyle(.secondary)}
        }
    }
}

struct CalendarDataSettings:View {
    @ObservedObject var model:CalendarModel
    @ObservedObject var weather:CalendarWeatherStore
    private func setTheme(_ theme:CalendarTheme) {var next=model.data;next.theme=theme;_ = model.apply(next)}
    private func colorBinding(_ key:WritableKeyPath<CalendarTheme,String>)->Binding<Color> {
        Binding(get:{Color(calendarHex:model.data.theme[keyPath:key])},set:{value in
            guard let color=NSColor(value).usingColorSpace(.deviceRGB) else{return}
            var theme=model.data.theme;theme[keyPath:key]=String(format:"#%02X%02X%02X",Int(color.redComponent*255),Int(color.greenComponent*255),Int(color.blueComponent*255));theme.name="自选配色";setTheme(theme)
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("日历配色").font(.headline)
            HStack(spacing:12) {
                ForEach(CalendarTheme.presets,id:\.name) {theme in
                    Button {setTheme(theme)} label:{
                        VStack(spacing:6) {
                            RoundedRectangle(cornerRadius:9).fill(LinearGradient(colors:[Color(calendarHex:theme.start),Color(calendarHex:theme.glow).opacity(0.6)],startPoint:.bottomTrailing,endPoint:.topLeading)).frame(width:62,height:36)
                                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(model.data.theme==theme ? Color.accentColor:.secondary.opacity(0.3),lineWidth:2))
                            Text(theme.name).font(.caption)
                        }
                    }.buttonStyle(.plain)
                }
            }
            HStack {ColorPicker("起始",selection:colorBinding(\.start),supportsOpacity:false);ColorPicker("结束",selection:colorBinding(\.end),supportsOpacity:false);ColorPicker("光晕",selection:colorBinding(\.glow),supportsOpacity:false)}
            Text("立即保存，并用于日历窗口、菜单栏月历和系统桌面小组件。").font(.caption).foregroundStyle(.secondary)
            if !model.storageNote.isEmpty {Text(model.storageNote).font(.caption).foregroundStyle(.secondary)}
            Divider()
            CalendarWeatherSettings(weather:weather)
            if !model.data.birthdays.isEmpty {
                Divider()
                DisclosureGroup("已保存生日（\(model.data.birthdays.count)）") {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(model.data.birthdays) {birthday in
                            HStack {
                                VStack(alignment:.leading) {Text(birthday.name);Text(birthday.dateLabel).font(.caption).foregroundStyle(.secondary)}
                                Spacer()
                                Button {model.removeBirthday(birthday.id)} label:{Image(systemName:"trash")}.help("仅移除万年历记录，不删除通讯录生日")
                            }
                        }
                    }.padding(.top,8)
                }
            }
        }
    }
}
