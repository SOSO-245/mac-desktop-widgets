import Foundation
@main struct WidgetTests {
    static func main() throws {
        var value=NikkiWidgetData.sample
        let now=value.generatedAt
        precondition(value.isFresh(at:now.addingTimeInterval(90)))
        precondition(!value.isFresh(at:now.addingTimeInterval(91)))
        precondition(!value.isFresh(at:now.addingTimeInterval(-1)))
        value.snapshot.isConnected=false
        precondition(!value.isFresh(at:now))
        let copy=try JSONDecoder().decode(NikkiWidgetData.self,from:JSONEncoder().encode(value))
        precondition(copy.sites.count==6 && copy.snapshot.totalBytes==value.snapshot.totalBytes)
        precondition(!NikkiWidgetData().isFresh(at:Date()))
        print("PASS 6 widget cache and freshness checks")
    }
}
