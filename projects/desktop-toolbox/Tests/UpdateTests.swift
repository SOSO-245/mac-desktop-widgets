import AppKit
import Sparkle
@main struct UpdateTests {
 static func main() {
  var n=0
  func check(_ b:Bool){n+=1;precondition(b)}
  let data=Data("<rss><channel><item><sparkle:version>20261030180000</sparkle:version><sparkle:shortVersionString>1.1.0</sparkle:shortVersionString></item><item><sparkle:version>1</sparkle:version></item></channel></rss>".utf8)
  let feed=SuiteFeed(),p=XMLParser(data:data);p.delegate=feed;p.shouldResolveExternalEntities=false
  check(p.parse());check(feed.build=="20261030180000");check(feed.version=="1.1.0")
  check(SuiteFeed.newer("20261030180000",than:"20261028120000"));check(!SuiteFeed.newer("20261028120000",than:"20261030180000"));check(!SuiteFeed.newer("",than:"1"));check(!SuiteFeed.newer("1",than:"1"));check(SuiteFeed.newer("10",than:"9"))
  check(Set(SuiteProduct.all.map(\.id)).count==8);check(Set(SuiteProduct.all.map(\.slug)).count==8)
  check(SuiteProduct.all.allSatisfy{!$0.slug.contains("/")})
  print("PASS \(n) update discovery and version checks; no live installer invoked")
 }
}
