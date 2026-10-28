import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class ToolboxModel:ObservableObject {
    @Published var states:[String:CardPresence]=[:]
    @Published var selected:Set<String>=[]
    @Published var sizes:[String:String]=[:]
    @Published var screenIndex=0
    @Published var edge="left"
    @Published var snap=true
    @Published var automatic=false
    @Published var note="先预览，再应用。不会改变卡片内容或数据连接。"
    @Published var busy=false
    @Published var unifiedAppearance=false
    @Published var glass=true
    @Published var brightness = -45.0
    @Published var transparency=20.0
    @Published var zoomToCards=true
    @Published var undoAvailable=false
    private var timer:Timer?
    private var discovery=ToolboxSelectionDiscovery()
    @Published var edited=false
    private var appliedOrder:[String]=[]
    private var appliedScreen=0
    private var appliedEdge="left"
    private var lastAppliedSizes:[String:String]=[:]
    private var lastAppliedDimensions:[String:NSSize]=[:]
    private var undo:[String:CardPresence]=[:]
    var screens:[NSScreen]{NSScreen.screens}
    var area:NSRect {let i=min(max(0,screenIndex),max(0,screens.count-1));return screens.isEmpty ? NSRect(x:0,y:0,width:1440,height:900):screens[i].visibleFrame}
    var running:Set<String>{Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))}
    @Published var order:[String]=ToolModule.all.map(\.id)
    var modules:[ToolModule]{order.compactMap{id in ToolModule.all.first{$0.id==id}}}
    func reorder(_ id:String,_ delta:Int){guard let i=order.firstIndex(of:id),order.indices.contains(i+delta) else{return};order.swapAt(i,i+delta);edited=true}
    init(){
        sizes=Dictionary(uniqueKeysWithValues:ToolModule.all.map{($0.id,["local.homeatlas.HomeEnergy","local.homeatlas.CodexResets"].contains($0.id) ? "small":(["local.homeatlas.FlClashMonitor","local.homeatlas.MacVitals"].contains($0.id) ? "large":"medium"))})
        let p=GridPreferences.read();if FileManager.default.fileExists(atPath:GridPreferences.folder.appendingPathComponent("grid.json").path){snap=p.snap;automatic=p.automatic}
        if let d=try? Data(contentsOf:GridPreferences.folder.appendingPathComponent("draft.json")),
           let saved=try? JSONDecoder().decode(ToolboxDraft.self,from:d),
           let draft=saved.normalized(moduleIDs:ToolModule.all.map(\.id),screenCount:screens.count) {
            selected=draft.selected;sizes.merge(draft.sizes){_,new in new};order=draft.order
            screenIndex=draft.screenIndex;edge=draft.edge;snap=draft.snap;automatic=draft.automatic
            unifiedAppearance=draft.unifiedAppearance;glass=draft.glass;brightness=draft.brightness
            transparency=draft.transparency;zoomToCards=draft.zoomToCards;edited=true
        }
        if let d=try? Data(contentsOf:GridPreferences.folder.appendingPathComponent("undo.json")),let u=try? JSONDecoder().decode([String:CardPresence].self,from:d){undo=u;undoAvailable = !u.isEmpty}
        poll();timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in Task{@MainActor in self?.poll()}}
    }
    func poll(){
        var fresh:[String:CardPresence]=[:]
        for m in ToolModule.all where running.contains(m.id) {
            let url=GridPreferences.folder.appendingPathComponent("status/"+m.id+".json")
            if let d=try? Data(contentsOf:url),d.count<8192,let s=try? JSONDecoder().decode(CardPresence.self,from:d),s.id==m.id,s.frame.valid,Date().timeIntervalSince(s.updated)<10 {fresh[m.id]=s}
        }
        states=fresh
        let added=discovery.discover(fresh.mapValues(\.visible),frozen:edited || !lastAppliedSizes.isEmpty)
        selected.formUnion(added)
        for id in added {sizes[id]=fresh[id]?.size}
        for (id,s) in fresh where sizes[id]==nil {sizes[id]=s.size}
        if automatic && GridPreferences.read().automatic && !busy && !lastAppliedSizes.isEmpty && selected==Set(lastAppliedSizes.keys) && order==appliedOrder && screenIndex==appliedScreen && edge==appliedEdge && selected.allSatisfy({fresh[$0] != nil && sizes[$0]==lastAppliedSizes[$0]}) {
            let live=fresh.filter{selected.contains($0.key)}.mapValues(\.size)
            let dimensions=fresh.filter{selected.contains($0.key)}.mapValues{$0.frame.rect.size}
            if live != lastAppliedSizes || dimensions != lastAppliedDimensions {sizes.merge(live){_,new in new};apply(saveUndo:false)}
        }
    }
    func dimensions(_ id:String)->NSSize {
        let size=sizes[id] ?? states[id]?.size ?? "medium"
        let narrow=["local.homeatlas.HomeEnergy","local.homeatlas.CodexResets","local.homeatlas.LunarCalendar"].contains(id)
        let reported=states[id]?.smallWidth
        let width=reported.flatMap{($0.isFinite && (100...344).contains($0)) ? $0:nil} ?? (narrow ? 164:220)
        return NSSize(width:size=="small" ? width:344,height:size=="large" ? 344:164)
    }
    var readiness:ToolboxReadiness{ToolboxReadiness.evaluate(selected:selected,responding:Set(states.keys),running:running)}
    var ready:Bool{readiness == .ready}
    var canApply:Bool{ready && placements.count==selected.count}
    var readinessMessage:String? {
        func names(_ ids:[String])->String {ids.map{id in ToolModule.all.first{$0.id==id}?.name ?? id}.joined(separator:"、")}
        switch readiness {
        case .empty:return "勾选已启动的卡片后，即可预览并应用排列。"
        case .stopped(let ids):return "请先启动所选软件："+names(ids)+"；也可取消勾选，排列其余卡片。"
        case .waiting(let ids):return "正在等待卡片响应："+names(ids)+"。请确认已更新软件并打开桌面卡片。"
        case .ready:return canApply ? nil : "当前屏幕放不下所选卡片，请减小尺寸或减少选择。"
        }
    }
    var draft:ToolboxDraft {ToolboxDraft(selected:selected,sizes:sizes,order:order,screenIndex:screenIndex,edge:edge,snap:snap,automatic:automatic,unifiedAppearance:unifiedAppearance,glass:glass,brightness:brightness,transparency:transparency,zoomToCards:zoomToCards)}
    func saveDraft(){
        try? FileManager.default.createDirectory(at:GridPreferences.folder,withIntermediateDirectories:true)
        if let d=try? JSONEncoder().encode(draft){try? d.write(to:GridPreferences.folder.appendingPathComponent("draft.json"),options:.atomic)}
    }
    var previewArea:NSRect {
        guard zoomToCards,let first=placements.values.first else{return area}
        return placements.values.reduce(first){$0.union($1)}.insetBy(dx:-24,dy:-24)
    }
    var placements:[String:NSRect] {
        let a=area.insetBy(dx:20,dy:20)
        let x=edge=="right" ? a.maxX-344:a.minX
        return CardGrid.pack(Dictionary(uniqueKeysWithValues:selected.map{($0,dimensions($0))}),order:order,area:a,anchor:NSPoint(x:x,y:a.maxY))
    }
    func send(_ id:String,_ action:String,_ extra:[String:Any]=[:]){var u=extra;u["target"]=id;u["action"]=action;DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.homeatlas.toolbox.command.v1"),object:nil,userInfo:u,deliverImmediately:true)}
    func settings(_ id:String,_ page:String="general") {send(id,"settings",["page":page])}
    func launch(_ m:ToolModule){let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/"+m.appName+".app");NSWorkspace.shared.open(url)}
    func setVisible(_ id:String,_ visible:Bool){send(id,visible ? "show":"hide")}
    func appearanceCommand(_ id:String){send(id,"appearance",["glass":glass,"brightness":brightness,"transparency":transparency])}
    func applyAppearanceOnly(){
        guard ready,!busy else{return}
        undo=states.filter{selected.contains($0.key)};saveUndoRecord()
        for id in selected{appearanceCommand(id)}
        note="已发送外观设置，正在核对…";busy=true
        DispatchQueue.main.asyncAfter(deadline:.now()+2.5){self.poll();let ok=self.selected.allSatisfy{id in guard let s=self.states[id] else{return false};return s.brightness==self.brightness && s.transparency==self.transparency && (s.glass==self.glass || id=="local.homeatlas.LunarCalendar")};self.note=ok ? "外观已更新并核对，卡片位置保持不变。":"部分卡片未确认外观，请检查软件是否已更新。";self.busy=false}
    }
    func saveUndoRecord(){undoAvailable=true;try? FileManager.default.createDirectory(at:GridPreferences.folder,withIntermediateDirectories:true);if let d=try? JSONEncoder().encode(undo){try? d.write(to:GridPreferences.folder.appendingPathComponent("undo.json"),options:.atomic)}}
    func apply(saveUndo:Bool=true){
        let target=placements
        guard !busy,!selected.isEmpty,target.count==selected.count,selected.allSatisfy({states[$0] != nil}) else {note="屏幕空间不足或部分软件尚未启动，请调整尺寸或选择。";return}
        busy=true;edited=true
        appliedOrder=order;appliedScreen=screenIndex;appliedEdge=edge
        if saveUndo {undo=states.filter{selected.contains($0.key)};undoAvailable=true;try? FileManager.default.createDirectory(at:GridPreferences.folder,withIntermediateDirectories:true);if let d=try? JSONEncoder().encode(undo){try? d.write(to:GridPreferences.folder.appendingPathComponent("undo.json"),options:.atomic)}}
        let a=area.insetBy(dx:20,dy:20);var p=GridPreferences.read();p.snap=snap;p.automatic=automatic;p.anchorX=edge=="right" ? a.maxX-344:a.minX;p.anchorTop=a.maxY;p.save()
        for id in selected{send(id,"size",["size":sizes[id] ?? "medium"]);send(id,"show");if unifiedAppearance{appearanceCommand(id)}}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35){
            for (id,r) in target {self.send(id,"place",["x":r.minX,"y":r.minY])}
            self.lastAppliedSizes=Dictionary(uniqueKeysWithValues:self.selected.map{($0,self.sizes[$0] ?? "medium")});self.lastAppliedDimensions=target.mapValues(\.size);self.note="正在核对实际位置…"
            DispatchQueue.main.asyncAfter(deadline:.now()+2.5){
                self.poll()
                let verified=target.allSatisfy {id,r in guard let actual=self.states[id]?.frame.rect else{return false};return abs(actual.minX-r.minX)<2 && abs(actual.minY-r.minY)<2 && abs(actual.width-r.width)<2 && abs(actual.height-r.height)<2}
                self.note=verified ? "已按预览排列，位置已核对并保存。":"部分卡片未完成排列，请检查是否已更新并启动；可恢复上次位置。"
                self.busy=false
            }
        }
    }
    func restore(){guard !undo.isEmpty else{return};busy=true
        var p=GridPreferences.read();p.automatic=false;p.snap=false;p.save();automatic=false;snap=false;lastAppliedSizes=[:]
        for (id,s) in undo{send(id,"size",["size":s.size]);send(id,s.visible ? "show":"hide");if let g=s.glass,let b=s.brightness,let t=s.transparency{send(id,"appearance",["glass":g,"brightness":b,"transparency":t])}}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35){for (id,s) in self.undo{self.send(id,"place",["x":s.frame.x,"y":s.frame.y])};self.sizes.merge(self.undo.mapValues(\.size)){_,new in new};self.note="已恢复上次位置与尺寸。";self.busy=false}
    }
}
private struct ToolboxPreviewTile:View {
    let module:ToolModule
    let frame:NSRect
    let area:NSRect
    let scale:CGFloat
    let unified:Bool
    let glass:Bool
    let brightness:Double
    let transparency:Double
    var body:some View {
        let material = unified && glass
        let tint:Color = material && brightness<0 ? .black:.white
        let alpha:Double = material ? (0.3+abs(brightness)*0.005)*(1-transparency/100):0.12
        let corner:CGFloat = max(6,24*scale)
        VStack(spacing:3) {
            Image(systemName:module.symbol).font(.system(size:max(9,15*scale)))
            Text(module.name).font(.system(size:max(8,12*scale),weight:.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white).frame(width:frame.width*scale,height:frame.height*scale)
        .background(tint.opacity(alpha),in:RoundedRectangle(cornerRadius:corner))
        .overlay(RoundedRectangle(cornerRadius:corner).stroke(.mint.opacity(0.65),lineWidth:1))
        .offset(x:(frame.minX-area.minX)*scale,y:(area.maxY-frame.maxY)*scale)
    }
}
struct ToolboxView:View {
    @ObservedObject var model:ToolboxModel
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:14){
                Label("桌面预览",systemImage:"rectangle.3.group").font(.title2.bold())
                HStack {Text("示意预览 · 使用真实卡片尺寸").font(.caption).foregroundStyle(.secondary);Spacer();Toggle("聚焦卡片",isOn:$model.zoomToCards).toggleStyle(.checkbox).font(.caption)}
                GeometryReader {g in
                    let a=model.previewArea;let scale=min(g.size.width/a.width,g.size.height/a.height)
                    ZStack(alignment:.topLeading){
                        RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[Color(red:0.06,green:0.13,blue:0.24),Color(red:0.16,green:0.14,blue:0.29)],startPoint:.topLeading,endPoint:.bottomTrailing))
                        ForEach(ToolModule.all){m in
                            if let r=model.placements[m.id]{
                                ToolboxPreviewTile(module:m,frame:r,area:a,scale:scale,unified:model.unifiedAppearance,glass:model.glass,brightness:model.brightness,transparency:model.transparency)
                            }
                        }
                    }.frame(width:a.width*scale,height:a.height*scale)
                }
                Text("间距 16 点 · 小卡片可并排 · 高度不足时换列").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(.black.opacity(0.12))
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:16){
                    Text("桌面工具箱").font(.title.bold())
                    Text("六款独立运行，按需组合。").foregroundStyle(.secondary)
                    ForEach(model.modules){m in
                        VStack(alignment:.leading,spacing:8){
                            HStack{
                                Toggle(isOn:Binding(get:{model.selected.contains(m.id)},set:{v in model.edited=true;if v{model.selected.insert(m.id)}else{model.selected.remove(m.id)}})){Label(m.name,systemImage:m.symbol)}.toggleStyle(.checkbox)
                                Spacer()
                                Button{model.reorder(m.id,-1)}label:{Image(systemName:"chevron.up")}.help("向前排列").buttonStyle(.plain)
                                Button{model.reorder(m.id,1)}label:{Image(systemName:"chevron.down")}.help("向后排列").buttonStyle(.plain)
                                if model.states[m.id] != nil {Button("设置"){model.settings(m.id)}}else{Button(model.running.contains(m.id) ? "等待更新":"启动"){model.launch(m)}.disabled(model.running.contains(m.id))}
                            }
                            HStack{
                                Picker("尺寸",selection:Binding(get:{model.sizes[m.id] ?? "medium"},set:{model.edited=true;model.sizes[m.id]=$0})) {Text("小").tag("small");Text("中").tag("medium");Text("大").tag("large")}.pickerStyle(.segmented).labelsHidden()
                                if let s=model.states[m.id]{Button(s.visible ? "隐藏":"显示"){model.setVisible(m.id,!s.visible)}.font(.caption)}
                            }
                        }.padding(12).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                    }
                    Divider()
                    Toggle("统一所选卡片外观",isOn:$model.unifiedAppearance)
                    if model.unifiedAppearance {
                        Picker("背景",selection:$model.glass){Text("原有配色").tag(false);Text("毛玻璃").tag(true)}.pickerStyle(.segmented)
                        HStack{Text("明暗");Spacer();Text(String(format:"%+.0f",model.brightness)).monospacedDigit()}
                        Slider(value:$model.brightness,in:-100...100).disabled(!model.glass).accessibilityLabel("统一明暗预览")
                        HStack{Text("背景透明度");Spacer();Text(String(format:"%.0f%%",model.transparency)).monospacedDigit()}
                        Slider(value:$model.transparency,in:0...80).disabled(!model.glass).accessibilityLabel("统一透明度预览")
                        Text("只改变背景，文字保持清晰。万年历保留毛玻璃；预览为效果示意。").font(.caption).foregroundStyle(.secondary)
                        Button("仅应用外观，保持位置"){model.applyAppearanceOnly()}.disabled(!model.ready || model.busy)
                    }
                    Divider()
                    Picker("屏幕",selection:$model.screenIndex){ForEach(Array(model.screens.enumerated()),id:\.offset){i,s in Text(s.localizedName).tag(i)}}
                    Picker("起始位置",selection:$model.edge){Text("左上").tag("left");Text("右上").tag("right")}.pickerStyle(.segmented)
                    Toggle("拖动后吸附网格",isOn:$model.snap)
                    Toggle("应用后，尺寸变化自动重排",isOn:$model.automatic)
                    Text("勾选和尺寸修改仅影响预览；“应用排列”后生效。系统小组件不参与排列。").font(.caption).foregroundStyle(.secondary)
                    HStack{Button("恢复上次位置"){model.restore()}.disabled(!model.undoAvailable || model.busy);Spacer();Button("确认并应用排列"){model.apply()}.buttonStyle(.borderedProminent).disabled(model.busy || !model.canApply)}
                    if let message=model.readinessMessage {Text(message).font(.callout).foregroundStyle(.orange)}
                    if model.automatic {Text("自动重排会在确认应用排列后启用；勾选本身不会移动卡片。").font(.caption).foregroundStyle(.secondary)}
                    Text(model.note).font(.callout).foregroundStyle(.secondary)
                }.padding(24).disabled(model.busy)
            }.frame(width:380)
        }.frame(minWidth:850,minHeight:720).preferredColorScheme(.dark)
            .onChange(of:model.draft){_,_ in model.saveDraft()}
    }
}
@MainActor final class ToolboxDelegate:NSObject,NSApplicationDelegate {
    let model=ToolboxModel();var window:NSWindow!;var status:NSStatusItem!
    func applicationDidFinishLaunching(_ n:Notification){
        NSApp.setActivationPolicy(.accessory)
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="桌面工具箱";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:850,height:720);window.contentView=NSHostingView(rootView:ToolboxView(model:model));window.center();window.setFrameAutosaveName("ToolboxWindow")
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength);status.button?.image=NSImage(systemSymbolName:"square.grid.2x2",accessibilityDescription:"桌面工具箱");status.button?.target=self;status.button?.action=#selector(show)
        let menu=NSMenu();let app=NSMenuItem();menu.addItem(app);app.submenu=NSMenu();let quit=NSMenuItem(title:"退出桌面工具箱",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");app.submenu?.addItem(quit);NSApp.mainMenu=menu;show()
    }
    @objc func show(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func applicationShouldHandleReopen(_ s:NSApplication,hasVisibleWindows f:Bool)->Bool{show();return false}
}
@main struct ToolboxMain {static func main(){let app=NSApplication.shared;let delegate=ToolboxDelegate();app.delegate=delegate;app.run()}}
