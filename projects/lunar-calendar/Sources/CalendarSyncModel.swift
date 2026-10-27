import Foundation

// Independent of AppKit and iCloud: per-record Lamport revisions merge offline edits.
struct CalendarSyncRecord:Codable,Equatable {
    var revision:Int
    var author:String
    var payload:Data? // nil is a durable deletion, never removed by compaction.
    func wins(over other:Self)->Bool {
        if revision != other.revision {return revision>other.revision}
        if payload == nil && other.payload != nil {return true}
        if payload != nil && other.payload == nil {return false}
        if author != other.author {return author>other.author}
        return (payload?.base64EncodedString() ?? "") > (other.payload?.base64EncodedString() ?? "")
    }
}
struct CalendarSyncDocument:Codable,Equatable {
    var schema=1
    var records:[String:CalendarSyncRecord]=[:]
    static let preferenceKeys=["theme","menuIcon","showDate","showYear","showWeekday","showLunar","showHoliday"]
    static func bytes<T:Encodable>(_ value:T) throws ->Data {let e=JSONEncoder();e.outputFormatting = .sortedKeys;return try e.encode(value)}
    static func values(_ data:CalendarUserData,extras:[String:Data]) throws ->[String:Data] {
        var values:[String:Data]=[:]
        for var b in data.birthdays {b.contactID=nil;values["birthday/"+b.id.uuidString]=try bytes(b)}
        for var s in data.schedules {s.systemEventID=nil;values["schedule/"+s.id.uuidString]=try bytes(s)}
        let object=try JSONSerialization.jsonObject(with:bytes(data)) as! [String:Any]
        for key in preferenceKeys {values["display/"+key]=try JSONSerialization.data(withJSONObject:object[key]!,options:[.fragmentsAllowed,.sortedKeys])}
        for (key,value) in extras {values["extra/"+key]=value}
        return values
    }
    func validated() throws ->Self {
        guard schema==1,records.count<=10000 else {throw SyncModelError.invalid}
        let decoder=JSONDecoder()
        for (key,r) in records {
            guard (0...1_000_000_000).contains(r.revision),UUID(uuidString:r.author) != nil else {throw SyncModelError.invalid}
            let parts=key.split(separator:"/",maxSplits:1).map(String.init)
            guard parts.count==2 else {throw SyncModelError.invalid}
            switch parts[0] {
            case "birthday":
                guard let id=UUID(uuidString:parts[1]) else {throw SyncModelError.invalid}
                if let p=r.payload {let b=try decoder.decode(Birthday.self,from:p);guard b.id==id,b.valid,b.contactID==nil else {throw SyncModelError.invalid}}
            case "schedule":
                guard let id=UUID(uuidString:parts[1]) else {throw SyncModelError.invalid}
                if let p=r.payload {let s=try decoder.decode(ScheduleItem.self,from:p);guard s.id==id,s.valid,s.systemEventID==nil else {throw SyncModelError.invalid}}
            case "display":
                guard Self.preferenceKeys.contains(parts[1]),let p=r.payload,p.count<4096 else {throw SyncModelError.invalid}
                switch parts[1] {
                case "theme":_ = try decoder.decode(CalendarTheme.self,from:p)
                case "menuIcon":_ = try decoder.decode(MenuIconPreferences.self,from:p)
                default:_ = try decoder.decode(Bool.self,from:p)
                }
            case "extra":
                guard ["menu","popup"].contains(parts[1]) else {throw SyncModelError.invalid}
                if let p=r.payload {
                    guard p.count<64000 else {throw SyncModelError.invalid}
                    if parts[1]=="popup" {guard ["glass","native"].contains(try decoder.decode(String.self,from:p)) else {throw SyncModelError.invalid}}
                    else {guard (try JSONSerialization.jsonObject(with:p)) is [String:Any] else {throw SyncModelError.invalid}}
                }
            default:throw SyncModelError.invalid
            }
        }
        return self
    }
    mutating func merge(_ remote:Self) throws {
        _ = try remote.validated()
        for (key,value) in remote.records {if records[key]==nil || value.wins(over:records[key]!) {records[key]=value}}
        _ = try validated()
    }
    func materialize(preserving local:CalendarUserData) throws ->(CalendarUserData,[String:Data]) {
        _ = try validated()
        var result=local;result.birthdays=[];result.schedules=[]
        var object=try JSONSerialization.jsonObject(with:Self.bytes(local)) as! [String:Any]
        var extras:[String:Data]=[:]
        let contacts=Dictionary(local.birthdays.map{($0.id,$0.contactID)},uniquingKeysWith:{$1})
        let events=Dictionary(local.schedules.map{($0.id,$0.systemEventID)},uniquingKeysWith:{$1})
        for (key,record) in records {
            guard let payload=record.payload else {continue}
            if key.hasPrefix("birthday/") {var b=try JSONDecoder().decode(Birthday.self,from:payload);b.contactID=contacts[b.id] ?? nil;result.birthdays.append(b)}
            else if key.hasPrefix("schedule/") {var s=try JSONDecoder().decode(ScheduleItem.self,from:payload);s.systemEventID=events[s.id] ?? nil;result.schedules.append(s)}
            else if key.hasPrefix("display/") {object[String(key.dropFirst(8))]=try JSONSerialization.jsonObject(with:payload,options:.fragmentsAllowed)}
            else if key.hasPrefix("extra/") {extras[String(key.dropFirst(6))]=payload}
        }
        guard result.birthdays.count<=2000,result.schedules.count<=2000 else {throw SyncModelError.invalid}
        object["birthdays"]=try JSONSerialization.jsonObject(with:Self.bytes(result.birthdays.sorted{$0.id.uuidString<$1.id.uuidString}))
        object["schedules"]=try JSONSerialization.jsonObject(with:Self.bytes(result.schedules.sorted{$0.id.uuidString<$1.id.uuidString}))
        result=try JSONDecoder().decode(CalendarUserData.self,from:JSONSerialization.data(withJSONObject:object))
        guard try Self.bytes(result).count<1_000_000 else {throw SyncModelError.invalid}
        return (result,extras)
    }
}
enum SyncModelError:Error {case invalid}
struct CalendarSyncJournal:Codable {
    var device=UUID().uuidString
    var document=CalendarSyncDocument()
    var baseline:[String:Data]=[:]
    var initialized=false
    mutating func capture(_ values:[String:Data]) {
        let revision=(document.records.values.map(\.revision).max() ?? 0)+1
        for key in Set(values.keys).union(baseline.keys) where values[key] != baseline[key] {
            document.records[key]=CalendarSyncRecord(revision:initialized ? revision : 0,author:device,payload:values[key])
        }
        baseline=values;initialized=true
    }
}
