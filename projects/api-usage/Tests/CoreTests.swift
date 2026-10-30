import Foundation
final class Mock: URLProtocol {
    static var responses: [(Int, String)] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, json) = Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Tests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Mock.self]
        let c = APIClient(session: URLSession(configuration: config))
        var checks = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); checks += 1 }
        let month = Month(now: ISO8601DateFormatter().date(from:"2026-10-30T00:00:00Z")!)
        check(month.id == "2026-10", "UTC month")
        check(month.start == ISO8601DateFormatter().date(from:"2026-10-01T00:00:00Z"), "UTC month start")
        Mock.responses = [(200, #"{"data":[{"start_time":1790812800,"results":[{"amount":{"value":0.1,"currency":"usd"}}]}],"has_more":true,"next_page":"page-two"}"#), (200, #"{"data":[{"start_time":1790812800,"results":[{"amount":{"value":"0.2","currency":"usd"}},{"amount":{"value":3,"currency":"eur"}}]}],"has_more":false}"#)]
        let costs = try await c.costs(key:"test-only",month:month,project:"proj_test")
        check(costs["USD"] == Decimal(string:"0.3"), "decimal exact sum")
        check(costs["EUR"] == 3, "separate currencies")
        let query = URLComponents(url:Mock.requests.last!.url!,resolvingAgainstBaseURL:false)!.queryItems!
        check(query.contains { $0.name == "page" && $0.value == "page-two" }, "pagination")
        check(query.contains { $0.name == "project_ids" && $0.value == "proj_test" }, "project filter")
        check(Mock.requests.allSatisfy { $0.httpMethod == "GET" }, "GET only")
        check(Mock.requests.allSatisfy { !$0.url!.absoluteString.contains("test-only") }, "key excluded from URL")
        Mock.responses = [(200,#"{"data":[{"results":[{"input_tokens":100,"input_cached_tokens":80,"output_tokens":20,"num_model_requests":2}]}],"has_more":false}"#)]
        let usage = try await c.usage(key:"test-only",month:month,project:"")
        check(usage.total == 120, "cached tokens not double counted")
        check(usage.requests == 2, "request count")
        Mock.responses = [(200,#"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"},{"currency":"USD","total_balance":"1.23","granted_balance":"0.23","topped_up_balance":"1.00"}]}"#)]
        let (balances,available) = try await c.balance(key:"test-only")
        check(!available && balances.count == 2, "availability and currencies")
        check(balances[0].total == 0 && balances[1].total == Decimal(string:"1.23"), "real zero balance")
        for (status, expected) in [(401,"密钥"),(403,"权限"),(429,"受限"),(302,"重定向"),(500,"暂不可用")] {
            Mock.responses = [(status,"{}")]
            do { _ = try await c.balance(key:"test-only"); fatalError("expected failure") }
            catch { check(error.localizedDescription.contains(expected),"HTTP \(status)") }
        }
        Mock.responses = [(200,#"{"is_available":true,"balance_infos":[{"currency":"CNY"}]}"#)]
        do { _ = try await c.balance(key:"test-only"); fatalError("missing fields must not become zero") } catch { check(true,"malformed balance") }
        Mock.responses = [(200,#"{"data":[],"has_more":true,"next_page":"x"}"#),(200,#"{"data":[],"has_more":true,"next_page":"x"}"#)]
        do { _ = try await c.costs(key:"test-only",month:month,project:""); fatalError("cursor cycle") } catch { check(true,"pagination cycle rejected") }
        do { _ = try await c.get(URL(string:"https://example.com/")!,key:"test-only"); fatalError("host") } catch { check(true,"host allowlist") }
        do { _ = try await c.get(URL(string:"http://api.openai.com/")!,key:"test-only"); fatalError("scheme") } catch { check(true,"TLS required") }
        Mock.responses = [(200,#"{"data":[],"has_more":false}"#)]
        let empty = try await c.costs(key:"test-only",month:month,project:"")
        check(empty["USD"] == 0,"successful empty month is zero")
        Mock.responses = [(200, #"{"data":[{"start_time":1790812800,"results":[{"amount":{"value":1,"currency":"usd"}},{"amount":{"value":2,"currency":"usd"}}]},{"start_time":1790899200,"results":[]}],"has_more":false}"#)]
        let report = try await c.costReport(key:"test-only",month:month,project:"")
        check(report.points.count == 2, "daily line items combined")
        check(report.points[0].amount == 3 && report.points[1].amount == 0,"explicit empty bucket is zero")
        check(report.points[0].day < report.points[1].day,"chronological chart")
        let now = ISO8601DateFormatter().date(from:"2026-10-30T12:30:00Z")!
        let hour = Int(floor(now.timeIntervalSince1970 / 3600) * 3600)
        Mock.responses = [(200, "{\"data\":[{\"start_time\":\(hour),\"results\":[{\"input_tokens\":30,\"input_cached_tokens\":20,\"output_tokens\":10,\"num_model_requests\":4}]}],\"has_more\":false}")]
        let hourly = try await c.usageHistory(key:"test-only",now:now,project:"proj_test",hourly:true)
        check(hourly.first?.tokens == 40,"hourly tokens without cache double count")
        let hourlyQuery = URLComponents(url:Mock.requests.last!.url!,resolvingAgainstBaseURL:false)!.queryItems!
        check(hourlyQuery.contains { $0.name == "bucket_width" && $0.value == "1h" },"hour granularity")
        check(hourlyQuery.contains { $0.name == "start_time" && $0.value == String(hour - 23*3600) },"24 hour window")
        let day = Int(floor(now.timeIntervalSince1970 / 86400) * 86400)
        Mock.responses = [(200, "{\"data\":[{\"start_time\":\(day),\"results\":[]}],\"has_more\":false}")]
        let weekly = try await c.usageHistory(key:"test-only",now:now,project:"",hourly:false)
        check(weekly.first?.tokens == 0,"explicit empty usage bucket")
        let weeklyQuery = URLComponents(url:Mock.requests.last!.url!,resolvingAgainstBaseURL:false)!.queryItems!
        check(weeklyQuery.contains { $0.name == "start_time" && $0.value == String(day - 6*86400) },"7 day window")
        var snapshot = Snapshot(); snapshot.usage = Record(value:usage,date:Date(),period:month.id)
        let roundTrip = try JSONDecoder().decode(Snapshot.self,from:JSONEncoder().encode(snapshot))
        check(roundTrip.usage?.value == usage,"cache roundtrip")
        print("PASS: \(checks) API checks; all network responses isolated, no account requests")
    }
}
