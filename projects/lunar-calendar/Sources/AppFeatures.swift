import AppKit
import SwiftUI
import Contacts
import ContactsUI
import EventKit
import CoreText

// Render one shared image for both settings previews and the real menu bar.
enum MenuIconRenderer {
    static func image(_ settings:MenuIconPreferences)->NSImage {
        let symbol=NSImage(systemSymbolName:settings.resolvedSymbol,accessibilityDescription:"万年历")!
            .withSymbolConfiguration(.init(pointSize:15,weight:.semibold))!
        let tint=settings.resolvedMode=="system" ? NSColor.black : NSColor(Color(calendarHex:settings.color))
        let colored=symbol.withSymbolConfiguration(.init(paletteColors:[settings.resolvedMode=="colorful" ? .white : tint])) ?? symbol
        let image=NSImage(size:NSSize(width:18,height:18),flipped:false) {bounds in
            var rect=bounds.insetBy(dx:1,dy:1)
            if settings.resolvedMode=="colorful" {
                let colors:[NSColor]
                switch settings.resolvedSymbol {
                case "sun.max.fill":colors=[.systemPink,.systemYellow]
                case "moon.stars.fill":colors=[.systemIndigo,.systemTeal]
                case "leaf.fill":colors=[.systemTeal,.systemGreen]
                case "star.fill":colors=[.systemPurple,.systemPink]
                case "calendar.badge.clock":colors=[.systemBlue,.systemCyan]
                default:colors=[.systemPink,.systemOrange]
                }
                NSGradient(colors:colors)?.draw(in:NSBezierPath(roundedRect:bounds,xRadius:4,yRadius:4),angle:55)
                rect=bounds.insetBy(dx:3,dy:3)
            }
            let ratio=min(rect.width/colored.size.width,rect.height/colored.size.height)
            let size=NSSize(width:colored.size.width*ratio,height:colored.size.height*ratio)
            colored.draw(in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height))
            return true
        }
        image.isTemplate=settings.resolvedMode=="system"
        return image
    }
    static func statusImage(_ settings:MenuIconPreferences,title:String,font:NSFont,foreground:NSColor)->NSImage {
        let icon=image(settings)
        let line=CTLineCreateWithAttributedString(NSAttributedString(string:title,attributes:[.font:font,.foregroundColor:foreground]))
        let ink=CTLineGetBoundsWithOptions(line,[.useGlyphPathBounds])
        let advance=CGFloat(CTLineGetTypographicBounds(line,nil,nil,nil))
        let width:CGFloat=title.isEmpty ? 18 : 18+7+ceil(advance)
        let result=NSImage(size:NSSize(width:width,height:20),flipped:false) {bounds in
            icon.draw(in:NSRect(x:0,y:1,width:18,height:18))
            if !title.isEmpty,let context=NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.textMatrix = .identity
                context.textPosition=CGPoint(x:25,y:(bounds.height-ink.height)/2-ink.minY)
                CTLineDraw(line,context)
                context.restoreGState()
            }
            return true
        }
        result.isTemplate=settings.resolvedMode=="system"
        result.accessibilityDescription="万年历 "+title
        return result
    }

}

struct ContactChooseButton:NSViewRepresentable {
    var selected:(String,String)->Void
    func makeCoordinator()->Coordinator {Coordinator(selected:selected)}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(title:"选择通讯录联系人",target:context.coordinator,action:#selector(Coordinator.choose(_:)))
        button.bezelStyle = .rounded;button.focusRingType = .none
        return button
    }
    func updateNSView(_ view:NSButton,context:Context) {context.coordinator.selected=selected}
    final class Coordinator:NSObject,CNContactPickerDelegate {
        var selected:(String,String)->Void
        let picker=CNContactPicker()
        init(selected:@escaping(String,String)->Void) {self.selected=selected;super.init();picker.delegate=self;picker.displayedKeys=[]}
        @objc func choose(_ sender:NSButton) {picker.showRelative(to:sender.bounds,of:sender,preferredEdge:.maxY)}
        func contactPicker(_ picker:CNContactPicker,didSelect contact:CNContact) {
            let given=contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : ""
            let family=contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
            let organization=contact.isKeyAvailable(CNContactOrganizationNameKey) ? contact.organizationName : ""
            let name=(family+given).isEmpty ? organization : family+given
            selected(contact.identifier,name.isEmpty ? "朋友" : name);picker.close()
        }
    }
}
struct BirthdayEditor:View {
    @ObservedObject var model:CalendarModel
    @Environment(\.dismiss) var dismiss
    @State private var name:String
    @State private var lunar:Bool
    @State private var leap:Bool
    @State private var month:Int
    @State private var day:Int
    @State private var contactID:String?
    @State private var writeContact=true
    @State private var error=""
    @State private var busy=false
    @State private var pending:CNMutableContact?
    @State private var confirmOverwrite=false
    @State private var oldBirthday=""
    let existing:Birthday?
    private let store=CNContactStore()
    init(model:CalendarModel,existing:Birthday?=nil) {
        self.model=model;self.existing=existing
        _name=State(initialValue:existing?.name ?? "")
        _lunar=State(initialValue:existing?.lunar ?? false)
        _leap=State(initialValue:existing?.leap ?? false)
        _month=State(initialValue:existing?.month ?? Almanac.gregorian.component(.month,from:model.selected))
        _day=State(initialValue:existing?.day ?? Almanac.day(model.selected))
        _contactID=State(initialValue:existing?.contactID)
    }
    var record:Birthday {Birthday(id:existing?.id ?? UUID(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),month:month,day:day,lunar:lunar,leap:lunar && leap,contactID:contactID)}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Image(systemName:"gift.fill").foregroundStyle(jade);Text(existing==nil ? "添加朋友生日" : "编辑朋友生日").font(.system(size:22,weight:.semibold));Spacer()}
            TextField("朋友姓名",text:$name).textFieldStyle(.roundedBorder).font(.system(size:16))
            HStack {ContactChooseButton {id,title in contactID=id;name=title};if contactID != nil {Label("已关联",systemImage:"person.crop.circle.badge.checkmark").font(.system(size:11)).foregroundStyle(jade)}}
            Picker("生日历法",selection:$lunar) {Text("公历生日").tag(false);Text("农历生日").tag(true)}.pickerStyle(.segmented)
                .onChange(of:lunar) {_,new in
                    if existing==nil {let p=Almanac.lunarParts(model.selected);month=new ? p.month : Almanac.gregorian.component(.month,from:model.selected);day=new ? p.day : Almanac.day(model.selected);leap=new && p.leap}
                    else {day=min(day,new ? 30 : 31)}
                }
            HStack(spacing:20) {
                Picker("月",selection:$month) {ForEach(1...12,id:\.self) {m in Text(lunar ? Almanac.lunarMonths[m-1] : "\(m)月").tag(m)}}
                Picker("日",selection:$day) {ForEach(1...(lunar ? 30 : 31),id:\.self) {d in Text(lunar ? Almanac.lunarDays[d-1] : "\(d)日").tag(d)}}
            }
            if lunar {Toggle("闰月生日",isOn:$leap)}
            if contactID != nil {Toggle("同时写入此联系人的生日",isOn:$writeContact)}
            Text("不足该日的年份按当月最后一天显示；闰月生日遇到无对应闰月时，按普通同月显示。仅记录月、日，不推断出生年份。")
                .font(.system(size:11)).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
            if !error.isEmpty {Text(error).font(.system(size:12)).foregroundStyle(workRed).fixedSize(horizontal:false,vertical:true)}
            HStack {
                Button("取消") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(busy ? "保存中…" : contactID != nil && writeContact ? "写入通讯录并保存" : "保存生日") {Task {await save()}}
                    .buttonStyle(.borderedProminent).tint(jade).disabled(!record.valid || busy).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width:430).background(CalendarBackground()).environment(\.calendarData,model.data).foregroundStyle(.white).preferredColorScheme(.dark).environment(\.locale,Locale(identifier:"zh_CN"))
         .alert("替换联系人的生日？",isPresented:$confirmOverwrite) {
            Button("取消",role:.cancel) {pending=nil;busy=false}
            Button("替换并保存") {if let contact=pending {commit(contact)}}
         } message:{Text("\(name)原来是\(oldBirthday)，将改为\(record.dateLabel)。其他联系信息保持原样。")}
    }
    @MainActor func save() async {
        guard record.valid else {return};busy=true;error=""
        guard let id=contactID,writeContact else {saveLocal();return}
        do {
            guard try await store.requestAccess(for:.contacts) else {error="未获得通讯录权限。可以关闭“同时写入”后只保存在万年历。";busy=false;return}
            let keys:[CNKeyDescriptor]=[CNContactIdentifierKey as CNKeyDescriptor,CNContactBirthdayKey as CNKeyDescriptor,CNContactNonGregorianBirthdayKey as CNKeyDescriptor]
            let contact=try store.unifiedContact(withIdentifier:id,keysToFetch:keys).mutableCopy() as! CNMutableContact
            if let birthday=contact.nonGregorianBirthday ?? contact.birthday {
                oldBirthday=(contact.nonGregorianBirthday != nil ? "农历" : "公历")+"\(birthday.month ?? 0)月\(birthday.day ?? 0)日"
                pending=contact;confirmOverwrite=true
            } else {commit(contact)}
        } catch {self.error="未能读取所选联系人：\(error.localizedDescription)";busy=false}
    }
    @MainActor func commit(_ contact:CNMutableContact) {
        // Only birthday fields on the user-selected contact are changed.
        var components=DateComponents();components.calendar=lunar ? Almanac.chinese : Almanac.gregorian
        components.month=month;components.day=day;if lunar {components.isLeapMonth=leap}
        if lunar {contact.nonGregorianBirthday=components;contact.birthday=nil}
        else {contact.birthday=components;contact.nonGregorianBirthday=nil}
        do {let request=CNSaveRequest();request.update(contact);try store.execute(request);pending=nil;saveLocal(contactWritten:true)}
        catch {self.error="通讯录生日未写入：\(error.localizedDescription)";busy=false}
    }
    @MainActor func saveLocal(contactWritten:Bool=false) {
        if model.addBirthday(record) {dismiss()}
        else {error=(contactWritten ? "通讯录已写入，但" : "")+"本地记录未保存，请重试。"}
        busy=false
    }
}
struct DisplaySettings:View {
    @ObservedObject var model:CalendarModel
    @Environment(\.dismiss) var dismiss
    @State private var draft:CalendarUserData
    init(model:CalendarModel) {self.model=model;_draft=State(initialValue:model.data)}
    func colorBinding(_ key:WritableKeyPath<CalendarTheme,String>)->Binding<Color> {
        Binding(get:{Color(calendarHex:draft.theme[keyPath:key])},set:{value in
            guard let c=NSColor(value).usingColorSpace(.deviceRGB) else {return}
            draft.theme[keyPath:key]=String(format:"#%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255));draft.theme.name="自选配色"
        })
    }
    var iconColor:Binding<Color> {
        Binding(get:{Color(calendarHex:draft.menuIcon.color)},set:{value in
            guard let c=NSColor(value).usingColorSpace(.deviceRGB) else {return}
            draft.menuIcon.color=String(format:"#%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255))
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("显示与外观").font(.system(size:23,weight:.semibold))
            Text("菜单栏图标").font(.system(size:13,weight:.semibold)).foregroundStyle(jade)
            HStack(spacing:8) {
                ForEach(MenuIconPreferences.choices,id:\.symbol) {choice in
                    Button {draft.menuIcon.symbol=choice.symbol} label:{
                        VStack(spacing:5) {
                            Image(nsImage:MenuIconRenderer.image(MenuIconPreferences(symbol:choice.symbol,mode:draft.menuIcon.mode,color:draft.menuIcon.color))).frame(width:22,height:22)
                            Text(choice.title).font(.system(size:11))
                        }.frame(width:58,height:50).background(RoundedRectangle(cornerRadius:9).fill(draft.menuIcon.resolvedSymbol==choice.symbol ? jade.opacity(0.22) : .white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(draft.menuIcon.resolvedSymbol==choice.symbol ? jade : .clear))
                    }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(choice.title+"图标")
                }
            }
            Picker("图标颜色",selection:$draft.menuIcon.mode) {
                Text("跟随系统").tag("system");Text("自选颜色").tag("custom");Text("彩色图标").tag("colorful")
            }.pickerStyle(.segmented)
            if draft.menuIcon.mode=="custom" {ColorPicker("图标颜色",selection:iconColor,supportsOpacity:false)}
            HStack(spacing:8) {
                Image(nsImage:MenuIconRenderer.image(draft.menuIcon))
                Text(draft.menuTitle(now:Date(),holidays:model.holidays).isEmpty ? "仅显示图标" : draft.menuTitle(now:Date(),holidays:model.holidays)).font(.system(size:12)).lineLimit(1)
            }.padding(8).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
            Button("自定义菜单栏文字、图标与颜色…") { NotificationCenter.default.post(name:Notification.Name("CalendarCustomizeMenu"),object:nil) }
            Text("菜单栏显示项目").font(.system(size:13,weight:.semibold)).foregroundStyle(jade)
            HStack(spacing:16) {Toggle("日期",isOn:$draft.showDate);Toggle("年份",isOn:$draft.showYear).disabled(!draft.showDate);Toggle("星期",isOn:$draft.showWeekday)}
            HStack(spacing:16) {Toggle("农历",isOn:$draft.showLunar);Toggle("假期名称",isOn:$draft.showHoliday)}
            Divider()
            Text("背景配色").font(.system(size:13,weight:.semibold)).foregroundStyle(jade)
            HStack(spacing:8) {ForEach(CalendarTheme.presets,id:\.name) {theme in Button {draft.theme=theme} label:{VStack(spacing:6) {RoundedRectangle(cornerRadius:9).fill(LinearGradient(colors:[Color(calendarHex:theme.start),Color(calendarHex:theme.glow).opacity(0.6)],startPoint:.bottomTrailing,endPoint:.topLeading)).frame(width:62,height:36).overlay(RoundedRectangle(cornerRadius:9).strokeBorder(draft.theme==theme ? jade : .white.opacity(0.2),lineWidth:1.5));Text(theme.name).font(.system(size:10))}}.buttonStyle(.plain)}}
            HStack {ColorPicker("起始",selection:colorBinding(\.start),supportsOpacity:false);ColorPicker("结束",selection:colorBinding(\.end),supportsOpacity:false);ColorPicker("光晕",selection:colorBinding(\.glow),supportsOpacity:false)}
            Text("同步用于窗口、菜单栏月历和桌面组件。").font(.system(size:11)).foregroundStyle(muted)
            Toggle("登录时自动启动",isOn:Binding(get:{model.autoStart},set:{model.setAutoStart($0)}))
            if !model.data.birthdays.isEmpty {
                DisclosureGroup("已保存生日（\(model.data.birthdays.count)）") {
                    ScrollView {VStack(alignment:.leading,spacing:9) {ForEach(model.data.birthdays) {birthday in HStack {VStack(alignment:.leading) {Text(birthday.name);Text(birthday.dateLabel).font(.system(size:10)).foregroundStyle(muted)};Spacer();Button {model.removeBirthday(birthday.id)} label:{Image(systemName:"trash")}.help("仅移除万年历记录，不删除通讯录生日")}}}}.frame(maxHeight:120)
                }
            }
            if !model.storageNote.isEmpty {Text(model.storageNote).font(.system(size:11)).foregroundStyle(workRed)}
            HStack {Button("取消") {dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("保存设置") {draft.birthdays=model.data.birthdays;draft.schedules=model.data.schedules;if model.apply(draft) {dismiss()}}.buttonStyle(.borderedProminent).tint(jade).keyboardShortcut(.defaultAction)}
        }.padding(26).frame(width:460).background(CalendarBackground()).environment(\.calendarData,draft).foregroundStyle(.white).preferredColorScheme(.dark).environment(\.locale,Locale(identifier:"zh_CN"))
    }
}

struct ScheduleEditor:View {
    @ObservedObject var model:CalendarModel
    @Environment(\.dismiss) var dismiss
    @State private var title=""
    @State private var start:Date
    @State private var end:Date
    @State private var allDay=false
    @State private var location=""
    @State private var notes=""
    @State private var reminder = -1
    @State private var recurrence="none"
    @State private var writeSystem=true
    @State private var busy=false
    @State private var error=""
    @State private var writtenID:String?
    private let store=EKEventStore()
    init(model:CalendarModel) {
        self.model=model
        let time=Almanac.gregorian.date(bySettingHour:9,minute:0,second:0,of:model.selected)!
        _start=State(initialValue:time);_end=State(initialValue:time.addingTimeInterval(3600))
    }
    var item:ScheduleItem {
        let begin=allDay ? Almanac.gregorian.startOfDay(for:start) : start
        let finish=allDay ? Almanac.gregorian.date(byAdding:.day,value:1,to:Almanac.gregorian.startOfDay(for:end))! : end
        return ScheduleItem(title:title.trimmingCharacters(in:.whitespacesAndNewlines),start:begin,end:finish,allDay:allDay,location:location,notes:notes,reminderMinutes:reminder<0 ? nil : reminder,systemEventID:writtenID,recurrence:recurrence)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Label("添加日程",systemImage:"calendar.badge.plus").font(.system(size:22,weight:.semibold)).foregroundStyle(jade)
            TextField("日程标题",text:$title).textFieldStyle(.roundedBorder).font(.system(size:16))
            Toggle("全天",isOn:$allDay)
            Picker("重复",selection:$recurrence) {ForEach(ScheduleItem.repeatChoices,id:\.0) {item in Text(item.1).tag(item.0)}}.pickerStyle(.segmented)
            if recurrence=="monthly" || recurrence=="yearly" {Text("按原日期重复；没有对应日期的月份或年份跳过。").font(.system(size:11)).foregroundStyle(muted)}
            DatePicker("开始",selection:$start,displayedComponents:allDay ? [.date] : [.date,.hourAndMinute])
            DatePicker("结束",selection:$end,displayedComponents:allDay ? [.date] : [.date,.hourAndMinute])
            TextField("地点（可选）",text:$location).textFieldStyle(.roundedBorder)
            TextField("备注（可选）",text:$notes,axis:.vertical).lineLimit(3...5).textFieldStyle(.roundedBorder)
            Toggle("同时添加到 Mac 系统日历",isOn:$writeSystem)
            if writeSystem {
                Picker("提醒",selection:$reminder) {Text("不提醒").tag(-1);Text("开始时").tag(0);Text("提前5分钟").tag(5);Text("提前15分钟").tag(15);Text("提前30分钟").tag(30);Text("提前1小时").tag(60)}
                Text("保存到系统默认日历；仅请求添加权限，不读取其他日程。").font(.system(size:11)).foregroundStyle(muted)
            } else {Text("只保存在万年历中，不发送系统提醒。").font(.system(size:11)).foregroundStyle(muted)}
            if !error.isEmpty {Text(error).foregroundStyle(workRed).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)}
            if !item.valid && !title.isEmpty {Text("请检查标题长度和时间：结束时间需晚于开始时间。").font(.system(size:11)).foregroundStyle(workRed)}
            HStack {Button("取消") {dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button(busy ? "保存中…" : "添加日程") {Task {await save()}}.buttonStyle(.borderedProminent).tint(jade).disabled(!item.valid || busy).keyboardShortcut(.defaultAction)}
        }.padding(26).frame(width:450).background(CalendarBackground()).environment(\.calendarData,model.data).foregroundStyle(.white).preferredColorScheme(.dark).environment(\.locale,Locale(identifier:"zh_CN")).environment(\.timeZone,Almanac.zone).environment(\.calendar,Almanac.gregorian)
    }
    @MainActor func save() async {
        guard item.valid else {return};busy=true;error=""
        defer{busy=false}
        if writeSystem && writtenID==nil {
            do {
                guard try await store.requestWriteOnlyAccessToEvents() else {error="未获得日历添加权限；可以关闭“同时添加”后仅保存到万年历。";return}
                guard let calendar=store.defaultCalendarForNewEvents,calendar.allowsContentModifications else {error="系统中没有可写的默认日历，请先在日历 App 中创建或设置默认日历。";return}
                let event=EKEvent(eventStore:store),draft=item
                event.calendar=calendar;event.title=draft.title;event.startDate=draft.start;event.endDate=draft.end;event.isAllDay=draft.allDay;event.timeZone=Almanac.zone
                event.location=draft.location;event.notes=draft.notes
                if let minutes=draft.reminderMinutes {event.addAlarm(EKAlarm(relativeOffset:TimeInterval(-minutes*60)))}
                let frequencies:[String:EKRecurrenceFrequency]=["weekly":.weekly,"monthly":.monthly,"yearly":.yearly]
                if let frequency=frequencies[draft.recurrence] {event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith:frequency,interval:1,end:nil))}
                try store.save(event,span:.thisEvent,commit:true)
                writtenID=event.eventIdentifier ?? event.calendarItemIdentifier
            } catch {self.error="日程未添加到系统日历：\(error.localizedDescription)";return}
        }
        if model.addSchedule(item) {dismiss()}
        else {error=writtenID != nil ? "系统日历已添加，本地记录保存失败。重试不会重复添加系统日程。" : "本地记录未保存，请重试。"}
    }
}
struct AgendaSheet:View {
    @ObservedObject var model:CalendarModel
    @Environment(\.dismiss) var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(Almanac.key(model.selected)+" · 日程表").font(.system(size:21,weight:.semibold))
            Text("显示在万年历添加的日程；系统日历中的后续修改暂不同步回来。").font(.system(size:11)).foregroundStyle(muted)
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    ForEach(model.selectedSchedules) {event in
                        VStack(alignment:.leading,spacing:7) {
                            HStack {Text(event.title).font(.system(size:16,weight:.semibold));Spacer();Text(event.timeLabel).foregroundStyle(jade)}
                            if event.recurrence != "none" {Label(event.recurrenceLabel,systemImage:"repeat").font(.system(size:11)).foregroundStyle(jade)}
                            if !event.location.isEmpty {Label(event.location,systemImage:"mappin.and.ellipse").font(.system(size:12))}
                            if !event.notes.isEmpty {Text(event.notes).font(.system(size:12)).foregroundStyle(muted)}
                            Text(event.systemEventID==nil ? "仅万年历" : "已添加到系统日历").font(.system(size:10)).foregroundStyle(muted)
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                    }
                    if model.selectedSchedules.isEmpty {Text("当天没有日程").foregroundStyle(muted)}
                }
            }.frame(maxHeight:350)
            HStack {Button("关闭") {dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("添加日程") {dismiss();DispatchQueue.main.asyncAfter(deadline:.now()+0.25) {model.showScheduleEditor=true}}.buttonStyle(.borderedProminent).tint(jade)}
        }.padding(26).frame(width:470).background(CalendarBackground()).environment(\.calendarData,model.data).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
