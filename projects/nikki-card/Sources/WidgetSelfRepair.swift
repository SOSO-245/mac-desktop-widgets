import AppKit
import WidgetKit
import Darwin

/// In-process repair of this app's own widget registration. No global cache deletion.
@MainActor final class WidgetSelfRepair {
    static let shared=WidgetSelfRepair()
    private var timer:Timer?, observer:NSObjectProtocol?
    private var busy=false
    nonisolated static func temporaryDuplicate(_ path:String,identifier:String,expected:String)->Bool {
        let p=URL(fileURLWithPath:path).standardizedFileURL
        guard p.path != URL(fileURLWithPath:expected).standardizedFileURL.path,
              p.pathExtension=="appex",p.path.hasPrefix("/private/var/folders/") || p.path.hasPrefix("/var/folders/") || p.path.hasPrefix("/tmp/"),p.path.contains("/T/") || p.path.hasPrefix("/tmp/") else{return false}
        return Bundle(url:p)?.bundleIdentifier==identifier
    }
    func start(){
        guard timer==nil,Bundle.main.bundleURL.path.contains("/Applications/") else{return}
        check()
        timer=Timer.scheduledTimer(withTimeInterval:900,repeats:true){[weak self] _ in Task{@MainActor in self?.check()}}
        observer=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.check()}}
    }
    private func check(){
        guard !busy,let id=Bundle.main.bundleIdentifier else{return}
        let app=Bundle.main.bundleURL
        let directory=app.appendingPathComponent("Contents/PlugIns")
        let plugins=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        guard !plugins.isEmpty else{return}
        busy=true
        let stamp=Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let changed=UserDefaults.standard.string(forKey:"widgetRepairVersion") != stamp
        Task.detached(priority:.utility){
            var repaired=false
            for plugin in plugins where plugin.pathExtension=="appex" {
                guard let bundle=Bundle(url:plugin),let widgetID=bundle.bundleIdentifier,widgetID.hasPrefix(id+".") else{continue}
                let listing=Self.run("/usr/bin/pluginkit",["-m","-Av","-i",widgetID]).1
                var duplicate=false
                for line in listing.split(separator:"\n") {
                    guard let path=line.split(separator:"\t").last.map(String.init),Self.temporaryDuplicate(path,identifier:widgetID,expected:plugin.path) else{continue}
                    if Self.run("/usr/bin/pluginkit",["-r",path]).0==0 {
                        let url=URL(fileURLWithPath:path);let oldApp=url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        if oldApp.pathExtension=="app"{_ = Self.run(Self.registrar,["-u",oldApp.path])}
                        duplicate=true
                    }
                }
                if duplicate || changed {
                    guard Self.run(Self.registrar,["-f",app.path]).0==0 else{continue}
                    _ = Self.run("/usr/bin/pluginkit",["-a",plugin.path])
                    // Stop only this installed extension so the replacement binary is loaded.
                    if let executable=bundle.executableURL?.path {
                        for row in Self.run("/bin/ps",["-axo","pid=,comm="]).1.split(separator:"\n") {
                            let cols=row.trimmingCharacters(in:.whitespaces).split(separator:" ",maxSplits:1,omittingEmptySubsequences:true)
                            if cols.count==2,cols[1].trimmingCharacters(in:.whitespaces)==executable,let pid=Int32(cols[0]){_ = Darwin.kill(pid,SIGTERM)}
                        }
                    }
                    repaired=true
                }
            }
            let didRepair=repaired
            await MainActor.run {
                if didRepair{UserDefaults.standard.set(stamp,forKey:"widgetRepairVersion");WidgetCenter.shared.reloadAllTimelines()}
                self.busy=false
            }
        }
    }
    nonisolated private static let registrar="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    nonisolated private static func run(_ path:String,_ args:[String])->(Int32,String){
        let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:path);p.arguments=args;p.standardOutput=pipe;p.standardError=FileHandle.nullDevice
        do{try p.run()}catch{return(-1,"")}
        let timeout=DispatchWorkItem{if p.isRunning{p.terminate()}}
        DispatchQueue.global().asyncAfter(deadline:.now()+8,execute:timeout)
        let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();timeout.cancel()
        return(p.terminationStatus,String(data:data,encoding:.utf8) ?? "")
    }
}
