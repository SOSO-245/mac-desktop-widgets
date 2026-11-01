import Foundation
@main struct ProviderTests {
 static func main() throws {
  var n=0
  func check(_ b:Bool,_ s:String){n+=1;precondition(b,s)}
  let root:[String:Any] = ["root":["type":"Fallback","now":"provider-only","all":["provider-only"]]]
  let data:[String:[String:Any]]=["subscription":["proxies":[["name":"provider-only","type":"Vless","history":[["delay":87]]]]]]
  let c=ProxySelection.catalog(proxies:root,providers:data)
  let p=ProxySelection.resolve(proxies:c.entries,mode:"rule",currentGroup:"root")
  check(p?.nodeName=="provider-only","provider leaf resolves selected fallback")
  check(p?.latencyMS==87,"latest provider history is usable")
  check(c.providersByNode["provider-only"]=="subscription","provider identity retained for probes")
  let direct=try ClashLatencyProbe.request(nodeName:"ordinary",testURL:ClashLatencyProbe.fallbackURL)
  check(direct.url!.path=="/proxies/ordinary/delay","top-level nodes retain original endpoint")
  let req=try ClashLatencyProbe.request(nodeName:"node/a?#",testURL:ClashLatencyProbe.fallbackURL,provider:"sub/a?#")
  let parts=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!
  check(parts.percentEncodedPath=="/providers/proxies/sub%2Fa%3F%23/node%2Fa%3F%23/healthcheck","names cannot escape one path segment")
  check(req.httpMethod=="GET","provider probe never writes selection")
  check(parts.queryItems!.first(where:{$0.name=="url"})!.value==ClashLatencyProbe.fallbackURL,"URL stays a query value")
  var duplicate=data;duplicate["other"]=data["subscription"]
  let ambiguous=ProxySelection.catalog(proxies:root,providers:duplicate)
  check(ambiguous.entries["provider-only"]==nil,"duplicate names across providers are not guessed")
  check(ambiguous.providersByNode["provider-only"]==nil,"ambiguous probe destination not assigned")
  var existing=root;existing["provider-only"]=["type":"Trojan","history":[["delay":42]]]
  let preferred=ProxySelection.catalog(proxies:existing,providers:data)
  check(preferred.providersByNode["provider-only"]==nil,"top-level proxy takes precedence")
  check(ProxySelection.resolve(proxies:preferred.entries,mode:"rule",currentGroup:"root")?.latencyMS==42,"provider does not replace core entry")
  let absent=ProxySelection.catalog(proxies:root,providers:[:]);check(absent.entries["provider-only"]==nil,"missing provider remains unknown")
  print("PASS \(n) provider-node and read-only probe checks")
 }
}
