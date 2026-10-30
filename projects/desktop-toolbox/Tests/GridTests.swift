import AppKit
@main struct Tests {
 static func main(){
 var n=0
 func check(_ b:Bool,_ label:String){n+=1;if !b{fatalError(label)}}
 let small=NSSize(width:164,height:164),medium=NSSize(width:344,height:164),large=NSSize(width:344,height:344)
 let sizes=["calendar":medium,"home":small,"reset":small,"nikki":medium,"vpn":large,"mac":large]
 let order=["calendar","home","reset","nikki","vpn","mac"]
 for a in [NSRect(x:0,y:0,width:1440,height:900),NSRect(x:-1920,y:100,width:1920,height:1080),NSRect(x:0,y:0,width:1800,height:450)] {
  for right in [false,true] {
   let r=CardGrid.pack(sizes,order:order,area:a,anchor:NSPoint(x:right ? a.maxX-344:a.minX,y:a.maxY))
   check(r.count==6,"all cards packed")
   for (id,rect) in r{check(a.contains(rect),"inside screen");check(rect.size==sizes[id],"preserve size");for(other,v)in r where other != id{check(!rect.intersects(v),"no overlap")}}
  }
 }
 let r=CardGrid.pack(sizes,order:order,area:NSRect(x:0,y:0,width:1440,height:1800),anchor:NSPoint(x:20,y:1780))
 check(r["home"]!.minY==r["reset"]!.minY,"two smalls share row")
 check(r["reset"]!.minX-r["home"]!.maxX==16,"consistent gap")
 let tiny=CardGrid.pack(sizes,order:order,area:NSRect(x:0,y:0,width:300,height:200),anchor:.zero)
 check(tiny.count<6,"insufficient area")
 let snap=CardGrid.snapped(NSRect(x:-12,y:-10,width:344,height:344),area:NSRect(x:0,y:0,width:1000,height:800),anchor:NSPoint(x:20,y:780))
 check(snap.minX>=0 && snap.minY>=0,"snap clamps")
 let obstacle=NSRect(x:20,y:866,width:344,height:164)
 let area=NSRect(x:20,y:20,width:2520,height:1370)
 let reserved=CardGrid.pack(["vpn":large,"api":medium],order:["vpn","api"],area:area,anchor:NSPoint(x:20,y:1030),obstacles:[obstacle])
 check(reserved.count==2,"unselected Nikki reserves space")
 for rect in reserved.values {check(!rect.intersects(obstacle),"selected windows cannot cover unselected Nikki");check(area.contains(rect),"obstacle avoidance stays on screen")}
 for blockers in [[NSRect(x:0,y:0,width:344,height:900)],[NSRect(x:0,y:0,width:1440,height:900)], [NSRect(x:0,y:400,width:344,height:100),NSRect(x:360,y:300,width:344,height:180)]] {
  let area=NSRect(x:0,y:0,width:1440,height:900)
  let layout=CardGrid.pack(sizes,order:order,area:area,anchor:NSPoint(x:0,y:900),obstacles:blockers)
  for (id,rect) in layout {check(area.contains(rect),"blocked layout bounds");for b in blockers {check(!rect.intersects(b),"blocked area clear")};for (other,r) in layout where id != other {check(!rect.intersects(r),"selected pairs remain separated")}}
 }
 print("GridTests: \(n) checks passed")
 }
}
