import Foundation

// Isolated fake router: the production scheduler runs without credentials or networking.
struct MonitorSnapshot { var routeIdentity="node-a";var isConnected=true }
struct TestSettings {var group="test"}
enum NikkiData {static func number(_ v:Any?)->Double?{v as? Double}}
@MainActor final class FakeAPI {
    var count=0
    func json(_ path:[String],query:[URLQueryItem]) async throws -> [String:Any] {
        count += 1
        try await Task.sleep(nanoseconds:2_000_000)
        return ["delay":123.0]
    }
}
@MainActor final class MonitorCoordinator {
    var api:FakeAPI?=FakeAPI();var settings=TestSettings();var proxies:[String:Int]=[:]
}
@main struct PreviewProbeTests {
    @MainActor static func main() async throws {
        let owner=MonitorCoordinator(),sites=SiteLatencyMonitor();sites.monitor=owner
        var snapshot=MonitorSnapshot();var checks=0
        func check(_ v:Bool,_ reason:String){checks += 1;precondition(v,reason)}
        func settle() async throws {try await Task.sleep(nanoseconds:150_000_000)}
        sites.configure(large:true,menuSite:"Google",snapshot:snapshot);try await settle()
        check(owner.api!.count==6,"first expanded view probes six sites")
        let date=sites.readings["YouTube"]?.checkedAt
        for _ in 0..<5 {sites.configure(large:false,menuSite:"Google",snapshot:snapshot);sites.configure(large:true,menuSite:"Google",snapshot:snapshot)}
        try await settle()
        check(owner.api!.count==6,"reopening does not repeat fresh requests")
        check(sites.readings["YouTube"]?.checkedAt==date,"reopening retains timestamp")
        sites.configure(large:false,menuSite:"Claude",snapshot:snapshot);try await settle()
        check(owner.api!.count==6,"switch menu site reuses fresh value")
        sites.refresh(siteID:"Claude");try await settle();check(owner.api!.count==7,"manual refresh still probes")
        snapshot.routeIdentity="node-b";sites.configure(large:true,menuSite:"Claude",snapshot:snapshot);try await settle()
        check(owner.api!.count==13,"changed route invalidates all old results")
        snapshot.isConnected=false;sites.configure(large:true,menuSite:"Claude",snapshot:snapshot)
        check(sites.readings.isEmpty,"disconnect removes old data")
        snapshot.isConnected=true;sites.configure(large:false,menuSite:"Google",snapshot:snapshot)
        sites.configure(large:true,menuSite:"Google",snapshot:snapshot);try await settle()
        check(owner.api!.count==19,"expanding during a pending probe fills remaining sites once")
        let now=Date();check(!SiteReading(checkedAt:now.addingTimeInterval(-59)).needsRefresh(at:now),"fresh cache")
        check(SiteReading(checkedAt:now.addingTimeInterval(-60)).needsRefresh(at:now),"minute boundary")
        check(SiteReading(checkedAt:now.addingTimeInterval(1)).needsRefresh(at:now),"clock rollback")
        check(SiteReading().needsRefresh(at:now),"missing sample")
        sites.stop();print("PASS \(checks) preview probe lifecycle checks")
    }
}
