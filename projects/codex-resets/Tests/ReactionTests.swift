import Foundation
@main struct Tests {
 static func main() throws {
  var tracker=ReactionTracker(),checks=0
  func test(_ value:Bool) {precondition(value);checks+=1}
  func event(_ count:Int,_ cycle:String="one",_ since:String="2026-10-25T06:06:16.000Z") throws ->ReactionCount {
   let data=try JSONSerialization.data(withJSONObject:["count":count,"cycle_id":cycle,"since":since]);return try JSONDecoder().decode(ReactionCount.self,from:data)
  }
  test(try tracker.accept(event(24047),animate:true)==0)
  test(try tracker.accept(event(24048),animate:true)==1)
  test(try tracker.accept(event(24051),animate:true)==3)
  test(try tracker.accept(event(24051),animate:true)==0)
  test(try tracker.accept(event(24040),animate:true)==0 && tracker.value?.count==24051)
  test(try tracker.accept(event(25000),animate:false)==0)
  test(try tracker.accept(event(25001),animate:true)==1)
  test(try tracker.accept(event(5,"two","2026-10-26T06:00:00Z"),animate:true)==0)
  test(try tracker.accept(event(25020),animate:true)==0 && tracker.value?.count==5)
  test(try tracker.accept(event(-1,"two","2026-10-26T06:00:00Z"),animate:true)==0 && tracker.value?.count==5)
  let source=CGRect(x:180,y:0,width:164,height:164),home=CGRect(x:0,y:0,width:164,height:164)
  test(ReactionCrossing.symbol(at:CGPoint(x:200,y:130),drift:-60,source:source,target:home) == .heart)
  test(ReactionCrossing.symbol(at:CGPoint(x:170,y:90),drift:-60,source:source,target:home) == .heart)
  test(ReactionCrossing.symbol(at:CGPoint(x:155,y:70),drift:-60,source:source,target:home) == .bolt)
  test(ReactionCrossing.symbol(at:CGPoint(x:155,y:70),drift:60,source:source,target:home)==nil)
  test(ReactionCrossing.symbol(at:CGPoint(x:355,y:70),drift:60,source:source,target:home)==nil)
  test(ReactionCrossing.symbol(at:CGPoint(x:200,y:-5),drift:-60,source:source,target:home)==nil)
  test(ReactionCrossing.symbol(at:CGPoint(x:155,y:70),drift:-60,source:source,target:nil)==nil)
  test(ReactionCrossing.validTarget(CGRect(x:360,y:0,width:164,height:164),source:source)==nil)
  test(ReactionCrossing.validTarget(CGRect(x:0,y:200,width:164,height:164),source:source)==nil)
  let entry=ReactionCrossing.entry(origin:CGPoint(x:200,y:130),drift:-65,rise:75,source:source,target:home)!
  test(abs(entry.point.x-home.maxX)<0.001 && entry.seconds>0 && entry.seconds<1.9)
  test(ReactionCrossing.entry(origin:CGPoint(x:200,y:130),drift:65,rise:75,source:source,target:home)==nil)
  test(ReactionCrossing.entry(origin:CGPoint(x:200,y:130),drift:-12,rise:75,source:source,target:home)==nil)
  test(ReactionCrossing.entry(origin:CGPoint(x:200,y:10),drift:-65,rise:155,source:source,target:home)==nil)
  for y in [0.0,10,82,154,164] {
   for angle in stride(from:0.0,to:Double.pi*2,by:0.1) {
    var previousX=164.0
    for progress in stride(from:0.0,through:1.0,by:0.05) {
     let point=ReactionCrossing.burstPoint(entry:CGPoint(x:164,y:y),target:home,angle:angle,distance:44,progress:progress,padding:17)
     test(home.insetBy(dx:17,dy:17).contains(point) && point.x<=previousX+0.001)
     previousX=point.x
    }
   }
  }
  let water=CGRect(x:20,y:100,width:100,height:12)
  test(ReactionCrossing.waterImpact(from:CGPoint(x:50,y:80),to:CGPoint(x:50,y:130),water:water)==CGPoint(x:50,y:100))
  test(ReactionCrossing.waterImpact(from:CGPoint(x:10,y:80),to:CGPoint(x:10,y:130),water:water)==nil)
  test(ReactionCrossing.waterImpact(from:CGPoint(x:30,y:90),to:CGPoint(x:100,y:90),water:water)==nil)
  test(ReactionCrossing.waterImpact(from:CGPoint(x:30,y:110),to:CGPoint(x:100,y:110),water:water) != nil)
  test(ReactionCrossing.waterImpact(from:CGPoint(x:50,y:80),to:CGPoint(x:50,y:97),water:water,radius:4)==CGPoint(x:50,y:100))
  test(ReactionCrossing.waterImpact(from:CGPoint(x:50,y:80),to:CGPoint(x:50,y:94),water:water,radius:4)==nil)
  print("PASS \(checks) reaction delta and left-only crossing checks")
 }
}
