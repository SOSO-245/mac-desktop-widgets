import Foundation
@main struct OriginalPostTests {
 static func main() {
  for value in ["https://x.com/example/status/12345","https://twitter.com/example/status/12345?s=20"] {precondition(ResetNavigation.originalPostURL(value)?.absoluteString==value)}
  for value in [nil,"http://x.com/example/status/12345","https://x.com.evil.test/example/status/12345","https://x.com@evil.test/example/status/12345","https://x.com/example","https://x.com/example/status/nope","javascript:alert(1)","https://user:pass@x.com/example/status/12345"] as [String?] {precondition(ResetNavigation.originalPostURL(value)==nil)}
  print("PASS 10 original-post routing checks")
 }
}
