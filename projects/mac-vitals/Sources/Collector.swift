import Foundation
import Darwin
@MainActor final class Collector {
    var snapshot=Metrics()
    var onUpdate:((Metrics)->Void)?
    private var process:Process?, timer:Timer?, pipe:Pipe?
    private var pending=Data(), network=NetworkRate(), lastStart=Date.distantPast
    private var running=false
    func start(){running=true;launch();timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in Task{@MainActor in guard let self else{return};if Date().timeIntervalSince(self.snapshot.date)>10 {self.snapshot.message="等待采集恢复";self.onUpdate?(self.snapshot);if Date().timeIntervalSince(self.lastStart)>15{self.launch()}}}}}
    private func launch(){
        guard running else{return};stopProcess();lastStart=Date();pending=Data();network=NetworkRate()
        let p=Process(),output=Pipe();p.executableURL=Bundle.main.url(forResource:"macmon",withExtension:nil);p.arguments=["pipe","--soc-info","-i","1000"];p.standardOutput=output;p.standardError=FileHandle.nullDevice
        guard p.executableURL != nil else{snapshot.message="采集器缺失";onUpdate?(snapshot);return}
        process=p;pipe=output
        output.fileHandleForReading.readabilityHandler = {[weak self,weak p] handle in
            let data=handle.availableData
            if data.isEmpty{handle.readabilityHandler=nil;return}
            Task{@MainActor in guard let self,self.process === p else{return};self.receive(data)}
        }
        do{try p.run()}catch{snapshot.message="采集器无法启动";onUpdate?(snapshot)}
    }
    private func receive(_ bytes:Data){
        pending.append(bytes);if pending.count>1_000_000{pending=Data();return}
        while let i=pending.firstIndex(of:10){let line=Data(pending[..<i]);pending.removeSubrange(...i)
            guard var m=try? Metrics.parse(line) else{continue}
            let speeds=network.update(Self.counters(),at:ProcessInfo.processInfo.systemUptime);m.download=speeds.0;m.upload=speeds.1
            m.history=Array((snapshot.history+[m.power ?? 0]).suffix(60));snapshot=m;onUpdate?(m)
        }
    }
    static func counters()->[String:Counter]{
        var head:UnsafeMutablePointer<ifaddrs>?;guard getifaddrs(&head)==0 else{return[:]};defer{freeifaddrs(head)}
        var p=head,result:[String:Counter]=[:]
        while let item=p {defer{p=item.pointee.ifa_next};let a=item.pointee;let name=String(cString:a.ifa_name)
            guard name.hasPrefix("en"),a.ifa_flags & UInt32(IFF_UP|IFF_RUNNING)==UInt32(IFF_UP|IFF_RUNNING),a.ifa_addr?.pointee.sa_family==UInt8(AF_LINK),let data=a.ifa_data else{continue}
            let d=data.assumingMemoryBound(to:if_data.self).pointee;result[name]=Counter(incoming:UInt64(d.ifi_ibytes),outgoing:UInt64(d.ifi_obytes))
        };return result
    }
    private func stopProcess(){pipe?.fileHandleForReading.readabilityHandler=nil;if process?.isRunning==true{process?.terminate()};process=nil;pipe=nil}
    func stop(){running=false;timer?.invalidate();timer=nil;stopProcess()}
}
