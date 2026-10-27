import Foundation
import AppKit
final class ReactionStub:URLProtocol {
 static var requests:[URLRequest]=[]
 static var fail=false
 override class func canInit(with request:URLRequest)->Bool {true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading() {
  Self.requests.append(request)
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:Self.fail ? 503:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Data("{\"cycle_id\":\"test\",\"since\":null,\"count\":1}".utf8));client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
@main struct Tests {
 @MainActor static func main() async throws {
  let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[ReactionStub.self]
  let demo=LiveReactions(demo:true,session:URLSession(configuration:c))
  demo.setActive(true);let initial=demo.count;demo.thank()
  try await Task.sleep(for:.milliseconds(30))
  precondition(demo.count==(initial ?? 0)+1 && ReactionStub.requests.isEmpty && !demo.sending)
  demo.setActive(false)
  let feed=LiveReactions(session:URLSession(configuration:c))
  feed.thank();feed.thank()
  for _ in 0..<100 {if !feed.sending {break};try await Task.sleep(for:.milliseconds(10))}
  precondition(!feed.sending && !feed.sendError && ReactionStub.requests.count==1)
  let r=ReactionStub.requests[0]
  precondition(r.httpMethod=="POST" && r.url?.absoluteString=="https://codex-resets.com/api/reset-requests")
  precondition(r.value(forHTTPHeaderField:"Content-Type")=="application/json")
  let body:Data
  if let data=r.httpBody {body=data} else {let stream=r.httpBodyStream!;stream.open();var data=Data(),buf=[UInt8](repeating:0,count:1024);while stream.hasBytesAvailable {let n=stream.read(&buf,maxLength:buf.count);if n<=0 {break};data.append(contentsOf:buf.prefix(n))};stream.close();body=data}
  let o=try JSONSerialization.jsonObject(with:body) as! [String:Any]
  precondition(o["n"] as? Int==1 && UUID(uuidString:o["request_id"] as! String) != nil)
  ReactionStub.fail=true;feed.thank()
  for _ in 0..<100 {if !feed.sending {break};try await Task.sleep(for:.milliseconds(10))}
  precondition(feed.sendError && ReactionStub.requests.count==2)
  try await Task.sleep(for:.milliseconds(50));precondition(ReactionStub.requests.count==2)
  print("PASS: demo sends zero requests; thank request format, in-flight duplicate guard, response, failure without retry; no network writes")
 }
}
