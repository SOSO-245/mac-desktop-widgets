import Foundation
@main struct Tests {
 static func main() {
  let now = Date(timeIntervalSince1970: 100000)
  var count = 0
  func check(_ value: Bool) { precondition(value); count += 1 }
  check(SubscriptionRefreshPolicy.interval(nil) == 3600)
  check(SubscriptionRefreshPolicy.interval(-1) == 3600)
  check(SubscriptionRefreshPolicy.interval(0) == 0)
  check(!SubscriptionRefreshPolicy.due(now: now, updated: nil, attempted: nil, interval: 0))
  check(SubscriptionRefreshPolicy.due(now: now, updated: nil, attempted: nil, interval: 3600))
  check(!SubscriptionRefreshPolicy.due(now: now, updated: now.addingTimeInterval(-3599), attempted: nil, interval: 3600))
  check(SubscriptionRefreshPolicy.due(now: now, updated: now.addingTimeInterval(-3600), attempted: nil, interval: 3600))
  check(!SubscriptionRefreshPolicy.due(now: now, updated: nil, attempted: now.addingTimeInterval(-100), interval: 3600))
  check(!SubscriptionRefreshPolicy.due(now: now, updated: nil, attempted: now.addingTimeInterval(-601), interval: 3600))
  check(SubscriptionRefreshPolicy.due(now: now, updated: now.addingTimeInterval(-7200), attempted: now.addingTimeInterval(-3600), interval: 3600))
  check(SubscriptionRefreshPolicy.due(now: now, updated: now.addingTimeInterval(100), attempted: nil, interval: 3600))
  check(!SubscriptionRefreshPolicy.due(now: now, updated: nil, attempted: now, interval: 0, manual: true))
  check(SubscriptionRefreshPolicy.due(now: now, updated: now, attempted: now.addingTimeInterval(-11), interval: 0, manual: true))
  check(SubscriptionRefreshPolicy.key(endpoint:"http://localhost",provider:"A") != SubscriptionRefreshPolicy.key(endpoint:"http://localhost",provider:"B"))
  print("Subscription refresh: \(count) checks passed")
 }
}
