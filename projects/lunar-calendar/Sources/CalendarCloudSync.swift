import AppKit
import SwiftUI

@MainActor final class CalendarCloudSync:ObservableObject {
    @Published var enabled=false
    @Published var busy=false
    @Published var status="未开启 iCloud 同步"
    @Published var folderName=""
    private weak var model:CalendarModel?
    private var folder:URL?
    private var journal=CalendarSyncJournal()
    private var timer:Timer?
    private var observers:[NSObjectProtocol]=[]
    private var epoch=UUID()
    private var ready=false
    private var applying=false
    private let journalURL=CalendarDataStore.localURL.deletingLastPathComponent().appendingPathComponent("sync-journal.json")
    private let bookmarkKey="calendarSync.folderBookmark.v1"
    private let enabledKey="calendarSync.enabled.v1"
    func start(model:CalendarModel) {
        self.model=model
        do {
            if FileManager.default.fileExists(atPath:CalendarDataStore.localURL.path) {
                _ = try JSONDecoder().decode(CalendarUserData.self,from:Data(contentsOf:CalendarDataStore.localURL))
            }
            if FileManager.default.fileExists(atPath:journalURL.path) {
                let bytes=try Data(contentsOf:journalURL);guard bytes.count<8_000_000 else {throw SyncModelError.invalid}
                journal=try JSONDecoder().decode(CalendarSyncJournal.self,from:bytes)
                _ = try journal.document.validated()
                guard UUID(uuidString:journal.device) != nil else {throw SyncModelError.invalid}
            }
            ready=true;try capture()
        } catch {status="本地同步记录无法读取，已暂停同步；原数据保留。";return}
        if UserDefaults.standard.bool(forKey:enabledKey),let bookmark=UserDefaults.standard.data(forKey:bookmarkKey) {
            do {
                var stale=false
                let url=try URL(resolvingBookmarkData:bookmark,options:[.withSecurityScope],relativeTo:nil,bookmarkDataIsStale:&stale)
                if stale {UserDefaults.standard.set(try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil),forKey:bookmarkKey)}
                folder=url;folderName=url.lastPathComponent;enabled=true;sync()
            } catch {status="请重新选择 iCloud 同步文件夹"}
        }
        timer=Timer.scheduledTimer(withTimeInterval:30,repeats:true) {[weak self] _ in Task {@MainActor in self?.sync()}}
        observers.append(NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.localChanged()}})
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.sync()}})
    }
    private func extras() throws ->[String:Data] {
        ["menu":try CalendarSyncDocument.bytes(MenuCustomization.load()),"popup":try CalendarSyncDocument.bytes(UserDefaults.standard.string(forKey:"statusPopover.style") ?? "glass")]
    }
    private func capture() throws {
        guard let model else {return}
        let before=try CalendarSyncDocument.bytes(journal)
        journal.capture(try CalendarSyncDocument.values(model.data,extras:extras()))
        let bytes=try CalendarSyncDocument.bytes(journal)
        if bytes != before {try persist()}
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at:journalURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try CalendarSyncDocument.bytes(journal).write(to:journalURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:journalURL.path)
    }
    func localChanged() {
        guard ready,!applying else {return}
        do {try capture()} catch {status="本地同步记录未保存，下次同步会重试"}
    }
    func chooseFolder() {
        guard ready,!busy else {return}
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.allowsMultipleSelection=false
        panel.title="选择 iCloud 云盘中的同步文件夹";panel.prompt="开启同步"
        panel.message="请在 iCloud 云盘新建或选择“万年历同步”文件夹。其他 Mac 选择同一个文件夹；首次会合并生日、日程和显示设置。"
        let drive=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath:drive.path) {panel.directoryURL=drive}
        panel.begin { [weak self] response in
            guard response == .OK,let url=panel.url else {return}
            Task {@MainActor in
                guard let self else {return}
                let scope=url.startAccessingSecurityScopedResource();defer {if scope {url.stopAccessingSecurityScopedResource()}}
                do {
                    let ubiquitous=(try? url.resourceValues(forKeys:[.isUbiquitousItemKey]).isUbiquitousItem)==true
                    let path=url.resolvingSymlinksInPath().path;let root=drive.resolvingSymlinksInPath().path
                    guard ubiquitous || path.hasPrefix(root+"/") else {self.status="请选择 iCloud 云盘中的专用文件夹";return}
                    let bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
                    self.epoch=UUID();self.folder=url;self.folderName=url.lastPathComponent;self.enabled=true
                    UserDefaults.standard.set(bookmark,forKey:self.bookmarkKey);UserDefaults.standard.set(true,forKey:self.enabledKey)
                    self.sync()
                } catch {self.status="文件夹暂不可用，请检查 iCloud 云盘后重试"}
            }
        }
    }
    func disable() {
        enabled=false;epoch=UUID();UserDefaults.standard.set(false,forKey:enabledKey)
        status="已停止同步，本机和云端记录均保留"
    }
    func sync() {
        guard ready,enabled,!busy,let folder,let model else {return}
        do {try capture()} catch {status="本地同步记录未保存，请重试";return}
        busy=true;status="正在检查 iCloud…"
        let token=epoch
        Task {
            let scope=folder.startAccessingSecurityScopedResource()
            defer {if scope {folder.stopAccessingSecurityScopedResource()};busy=false}
            do {
                let documents=try await Task.detached(priority:.utility) {try CalendarCloudIO.read(folder)}.value
                guard enabled,token==epoch else {return}
                try capture() // Preserve edits made while iCloud was downloading.
                var merged=journal.document
                for document in documents {try merged.merge(document)}
                let (data,preferences)=try merged.materialize(preserving:model.data)
                let menu=try preferences["menu"].map {try JSONDecoder().decode(MenuCustomization.self,from:$0)}
                let popup=try preferences["popup"].map {try JSONDecoder().decode(String.self,from:$0)}
                let changed=try CalendarSyncDocument.bytes(data) != CalendarSyncDocument.bytes(model.data)
                if changed {
                    let backup=journalURL.deletingLastPathComponent().appendingPathComponent("同步前备份",isDirectory:true)
                    try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
                    try CalendarDataStore.save(model.data,url:backup.appendingPathComponent(UUID().uuidString+".json"))
                }
                applying=true
                defer {applying=false}
                if changed {guard model.apply(data) else {throw CocoaError(.fileWriteUnknown)}}
                if let menu,menu != MenuCustomization.load() {menu.save()}
                if let popup,popup != UserDefaults.standard.string(forKey:"statusPopover.style") {UserDefaults.standard.set(popup,forKey:"statusPopover.style")}
                journal.document=merged;journal.baseline=try CalendarSyncDocument.values(model.data,extras:extras());try persist()
                NotificationCenter.default.post(name:Notification.Name("CalendarSyncApplied"),object:nil)
                let outgoing=journal.document,device=journal.device
                let uploaded=try await Task.detached(priority:.utility) {try CalendarCloudIO.write(outgoing,device:device,folder:folder)}.value
                guard enabled,token==epoch else {return}
                status=uploaded ? "已与 iCloud 文件合并 · "+Date().formatted(date:.omitted,time:.shortened) : "已合并并保存，等待 iCloud 上传"
            } catch {
                guard enabled,token==epoch else {return}
                status="同步暂未完成，本地数据保留；请检查网络、iCloud 或同步文件后重试。"
            }
        }
    }
}

struct CalendarSyncSettings:View {
    @ObservedObject var sync:CalendarCloudSync
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Label("iCloud 多台 Mac 同步",systemImage:"icloud").font(.system(size:14,weight:.semibold))
            Text("同步生日、日程、配色和菜单栏设置；所有 Mac 选择同一个 iCloud 云盘文件夹。").font(.system(size:11)).foregroundStyle(.secondary)
            if sync.enabled {Text("文件夹："+sync.folderName).font(.system(size:11))}
            Text(sync.status).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(sync.enabled ? "更换文件夹…" : "选择文件夹并开启…") {sync.chooseFolder()}.disabled(sync.busy)
                if sync.enabled {
                    Button(sync.busy ? "同步中…" : "立即同步") {sync.sync()}.disabled(sync.busy)
                    Button("停止同步") {sync.disable()}.disabled(sync.busy)
                }
            }
            Text("应用运行时每 30 秒检查。云端传输由 iCloud 决定；不会重复写入通讯录或系统日历。").font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
    }
}
