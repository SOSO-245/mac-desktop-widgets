import SwiftUI
import AppKit
enum DuckSprite {
 static let images:[String:NSImage] = Dictionary(uniqueKeysWithValues:["duck-ai","duck-spring","duck-summer","duck-winter","duck-rain","duck-snow","duck-skeleton","duck-birthday","duck-rain-wet","duck-basketball"].compactMap { name in
  Bundle.main.url(forResource:name,withExtension:"png").flatMap{NSImage(contentsOf:$0)}.map{(name,$0)}
 })
 static func image(_ style:DuckWeather.Appearance)->NSImage? {
  let key = style == .rain ? "duck-rain-wet" : style == .snow ? "duck-winter" : [DuckWeather.Appearance.spring,.summer,.winter,.rain].contains(style) ? "duck-"+style.rawValue : "duck-ai"
  return images[key] ?? images["duck-ai"]
 }
}

struct DuckMotion {
    enum Action { case bob, swim }
    var action: Action = .bob
    var began: TimeInterval = -1e9
    var from = 0.5
    var target = 0.5
    struct Pose { var position:Double; var bounce=0.0; var depth=0.0; var opacity=1.0; var facing=1.0; var pitch=0.0 }
    func pose(at time:TimeInterval,share:Double)->Pose {
        let age=time-began
        guard age>=0 else { return Pose(position:share) }
        if action == .bob {
            guard age<1.1 else{return Pose(position:share)}
            return Pose(position:from,bounce:sin(age * .pi * 8) * 3.8 * pow(1-age/1.1,1.3))
        }
        let swim=0.8+abs(target-from)*1.6
        func ease(_ v:Double)->Double {let t=max(0,min(1,v));return t*t*(3-2*t)}
        if age<swim {return Pose(position:from+(target-from)*ease(age/swim),bounce:sin(age*13)*0.6,facing:target>=from ? 1:-1)}
        if age<swim+1.8 {
            let t=(age-swim)/1.8
            let depth:Double,pitch:Double
            if t<0.18 {depth=0;pitch=ease(t/0.18)}
            else if t<0.50 {depth=ease((t-0.18)/0.32);pitch=1}
            else if t<0.65 {depth=1;pitch=1}
            else {let rise=ease((t-0.65)/0.35);depth=1-rise;pitch=1-rise}
            return Pose(position:target,depth:depth*26,opacity:max(0,1-depth*1.5),facing:target>=from ? 1:-1,pitch:pitch * .pi/2)
        }
        if age<swim+3.8 {return Pose(position:target+(share-target)*ease((age-swim-1.8)/2),facing:share>=target ? 1:-1)}
        return Pose(position:share)
    }
    static func shockVisible(age:Double)->Bool { (0..<0.18).contains(age) || (0.36..<0.54).contains(age) }
}

struct WaterDuck:View {
 let share:Double
 let time:Double
 var birthday=false
 var style:DuckWeather.Appearance = .original
 var pose:DuckMotion.Pose? = nil
 var snow=0.0
 var shock=false
 var clearedAge:Double? = nil
 var body:some View {
  GeometryReader { proxy in
  Canvas {ctx,size in
   let headroom=24.0
   let w=size.width,h=size.height-headroom
   guard w > 1, h >= 24 else { return }
   ctx.translateBy(x:0,y:headroom)
   let dx=max(20,min(w-20,w*(pose?.position ?? share))),period=Double.pi*2/4
   func surface(_ x:Double,_ layer:Int)->Double {
    23+sin(x/22-time*period+Double(layer)*1.4)*(layer==0 ? 1.7:2.2)+sin(x/11+time*period*0.5)*0.6+Double(layer)*1.1
   }
   let trough=Path(roundedRect:CGRect(x:0,y:19,width:w,height:h-19),cornerRadius:6)
   ctx.fill(trough,with:.color(.white.opacity(0.035)))
   for layer in 0..<3 {
    var wave=Path();wave.move(to:CGPoint(x:0,y:surface(0,layer)))
    for i in 1...Int(w*2) {let x=Double(i)/2;wave.addLine(to:CGPoint(x:x,y:surface(x,layer)))}
    var fill=wave;fill.addLine(to:CGPoint(x:w,y:h));fill.addLine(to:CGPoint(x:0,y:h));fill.closeSubpath()
    var water=ctx
    water.clip(to:Path(roundedRect:CGRect(x:0,y:14,width:w,height:h-14),cornerRadius:5))
    // A single continuous water surface; the duck marks the metered share.
    let middle=max(0.09,min(0.91,share))
    let gradient=Gradient(stops:[
      .init(color:Color(red:0.65,green:0.34,blue:1),location:0),
      .init(color:Color(red:0.56,green:0.36,blue:0.98),location:middle-0.08),
      .init(color:Color(red:0.39,green:0.44,blue:0.97),location:middle),
      .init(color:Color(red:0.26,green:0.60,blue:1),location:middle+0.08),
      .init(color:Color(red:0.20,green:0.76,blue:1),location:1)])
    water.opacity=[0.22,0.32,0.62][layer]
    water.fill(fill,with:.linearGradient(gradient,startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:w,y:0)))
    water.stroke(wave,with:.color(.white.opacity(layer==2 ? 0.45:0.15)),lineWidth:0.55)
   }
   let waterY=surface(dx,2)
   var wake=Path();wake.addEllipse(in:CGRect(x:dx-12,y:waterY-1,width:25,height:3))
   ctx.stroke(wake,with:.color(.cyan.opacity(0.22)),lineWidth:0.5)
   var duck=ctx
   if (pose?.depth ?? 0)>0 {duck.clip(to:Path(CGRect(x:0,y:0,width:w,height:waterY+2)))}
   duck.translateBy(x:dx,y:waterY-1+(pose?.bounce ?? 0)+(pose?.depth ?? 0))
   duck.opacity=pose?.opacity ?? 1
   duck.scaleBy(x:pose?.facing ?? 1,y:1)
   let slope=(surface(dx+1,2)-surface(dx-1,2))*0.5
   duck.rotate(by:.radians(slope*0.45+sin(time*period)*0.07))
   duck.translateBy(x:0,y:-7)
   duck.rotate(by:.radians(pose?.pitch ?? 0))
   duck.translateBy(x:0,y:7)
   if style == .football {
    if let ball=DuckSprite.images["duck-basketball"] {duck.draw(ctx.resolve(Image(nsImage:ball)),in:CGRect(x:-12,y:-21,width:24,height:24))}
   } else if birthday,!shock,let image=DuckSprite.images["duck-birthday"] {
    duck.draw(ctx.resolve(Image(nsImage:image)),in:CGRect(x:-16,y:-29,width:32,height:32))
   } else if shock {
    if let image=DuckSprite.images["duck-skeleton"] {
     duck.draw(ctx.resolve(Image(nsImage:image)),in:CGRect(x:-12,y:-22,width:24,height:24))
    }
   } else if let image=DuckSprite.image(style) {
    duck.draw(ctx.resolve(Image(nsImage:image)),in:CGRect(x:-12,y:-22,width:24,height:24))
    if style == .snow, snow>0,let snowy=DuckSprite.images["duck-snow"] {
     var accumulation=duck;accumulation.opacity *= min(1,max(0,snow))
     accumulation.draw(ctx.resolve(Image(nsImage:snowy)),in:CGRect(x:-12,y:-22,width:24,height:24))
    }
   }
   if style == .rain,!shock {
    for i in 0..<3 {
     let phase=(time*0.34+Double(i)*0.31).truncatingRemainder(dividingBy:1)
     let x = [-7.0,3.0,8.0][i],y = -19+phase*19
     let bead=CGRect(x:x,y:y,width:1.25,height:1.7+phase*0.5)
     var wet=duck;wet.opacity *= sin(phase * .pi)*0.72
     wet.fill(Path(ellipseIn:bead),with:.color(.cyan.opacity(0.30)))
     wet.stroke(Path(ellipseIn:bead),with:.color(.white.opacity(0.85)),lineWidth:0.35)
    }
   }
   if let age=clearedAge,age>=0,age<0.7 {
    for i in 0..<9 {
     let angle=Double(i)*2.4,x=dx+cos(angle)*age*22,y=waterY-12-sin(angle)*age*15+age*age*14
     ctx.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1.2,height:1.2)),with:.color(.white.opacity(1-age/0.7)))
    }
   }
  }.frame(width:proxy.size.width,height:proxy.size.height+24).offset(y:-24)
  }
 }
 static func football(_ c:inout GraphicsContext) {
  let sphere=Path(ellipseIn:CGRect(x:-9,y:-17,width:18,height:18))
  c.fill(sphere,with:.radialGradient(Gradient(colors:[.white,Color(white:0.68)]),center:CGPoint(x:-3,y:-13),startRadius:0,endRadius:21))
  var clipped=c;clipped.clip(to:sphere)
  for (x,y,r) in [(0.0,-9.0,3.3),(-8.0,-16.0,3.4),(8.0,-16.0,3.4),(-7.0,0.0,3.3),(7.0,0.0,3.3)] {
   var pentagon=Path()
   for i in 0..<5 {let angle=Double(i)*2*Double.pi/5-Double.pi/2;let p=CGPoint(x:x+cos(angle)*r,y:y+sin(angle)*r);if i==0{pentagon.move(to:p)}else{pentagon.addLine(to:p)}}
   pentagon.closeSubpath();clipped.fill(pentagon,with:.color(Color(white:0.12)))
  }
 }
}

/// Animations are local presentation only; taps do not change the measured ratio.
struct PowerWater:View {
 let share:Double
 var animated=false
 var interactive=false
 var weather:DuckWeather?=nil
 var timezone="Asia/Shanghai"
 @State private var motion=DuckMotion()
 @State private var progress=DuckProgressMotion()
 @State private var snowSince=Date()
 @State private var cleared:Date?=nil
 @State private var shockAt=Date.distantPast
 @State private var waterScreen=CGRect.zero
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 init(share:Double,animated:Bool=false,interactive:Bool=false,weather:DuckWeather?=nil,timezone:String="Asia/Shanghai") {
  self.share=share;self.animated=animated;self.interactive=interactive;self.weather=weather;self.timezone=timezone
  var initial=DuckProgressMotion();initial.reset(to:share,at:ProcessInfo.processInfo.systemUptime)
  _progress=State(initialValue:initial)
 }
 private func style(_ now:Date)->DuckWeather.Appearance {(weather ?? DuckWeather()).appearance(at:now,timezone:timezone)}
 private func tap(_ point:CGPoint,width:Double) {
  let now=Date(),appearance=style(now)
  guard interactive,appearance != .football,width>24 else{return}
  let t=now.timeIntervalSinceReferenceDate,current=progress.value(at:ProcessInfo.processInfo.systemUptime),pose=motion.pose(at:t,share:current),x=max(12,min(width-12,width*pose.position))
  let duckHit=abs(point.x-x)<18 && point.y<30
  if duckHit,appearance == .snow {snowSince=now;cleared=now}
  guard !reduceMotion,animated else{return}
  motion=DuckMotion(action:duckHit ? .bob:.swim,began:t,from:pose.position,target:max(12/width,min(1-12/width,point.x/width)))
 }
 var body:some View {
  GeometryReader { proxy in
   TimelineView(.animation(minimumInterval:1.0/30,paused:!animated || reduceMotion)) { timeline in
    let now=timeline.date,appearance=style(now),t=now.timeIntervalSinceReferenceDate
    let current=animated && !reduceMotion ? progress.value(at:ProcessInfo.processInfo.systemUptime):share
    WaterDuck(share:current,time:animated && !reduceMotion ? t:0,birthday:interactive && BirthdayBadgeSignal.current(at:now),style:appearance,
      pose:appearance == .football || !animated || reduceMotion ? nil:motion.pose(at:t,share:current),
      snow:appearance == .snow ? (interactive ? min(1,max(0,now.timeIntervalSince(snowSince)/90)):0.8):0,
      shock:!reduceMotion && appearance != .football && DuckMotion.shockVisible(age:now.timeIntervalSince(shockAt)),
      clearedAge:cleared.map{now.timeIntervalSince($0)})
   }
   .contentShape(Rectangle())
   .gesture(SpatialTapGesture().onEnded{tap($0.location,width:proxy.size.width)},including:interactive ? .all:.none)
   .onContinuousHover { phase in
    guard interactive,style(Date()) != .football else{return}
    switch phase {case .active: DuckPointer.cursor.set();case .ended:NSCursor.arrow.set()}
   }
   .background { if interactive { WaterFrameReporter(pointing:style(Date()) != .football,lastImpact:shockAt.timeIntervalSince1970) {if waterScreen != $0 {waterScreen=$0}} } }
  }
  .onChange(of:share){_,value in progress.retarget(value,at:ProcessInfo.processInfo.systemUptime)}
  .onChange(of:weather?.condition) { old,new in
   if old != new,new.map({DuckWeather.snow.contains($0)}) == true {snowSince=Date()}
   if new.map({DuckWeather.storms.contains($0)}) == true {motion=DuckMotion()}
  }
  .onReceive(DistributedNotificationCenter.default().publisher(for:Notification.Name("local.homeatlas.duck.impact.v1")).receive(on:RunLoop.main)) { notification in
   guard interactive,animated,!reduceMotion,let u=notification.userInfo,let x=u["x"] as? Double,let y=u["y"] as? Double,let stamp=u["time"] as? Double,
    x.isFinite,y.isFinite,stamp.isFinite,abs(Date().timeIntervalSince1970-stamp)<1,DuckImpact.contains(CGPoint(x:x,y:y),in:waterScreen),Date().timeIntervalSince(shockAt)>1.2 else{return}
   shockAt=Date()
  }
  .accessibilityElement(children:.ignore)
  .accessibilityLabel(style(Date()) == .football ? "水面上的篮球":"小黄鸭；点鸭子浮动或清雪，点水面游泳潜水")
  .accessibilityAction(named:Text("轻点小鸭子")){if style(Date()) == .snow {snowSince=Date();cleared=Date()};if interactive {let current=progress.value(at:ProcessInfo.processInfo.systemUptime);motion=DuckMotion(action:.bob,began:Date().timeIntervalSinceReferenceDate,from:current,target:current)}}
 }
}

/// App-local illustrated pointer. Its hotspot is measured at the opaque fingertip.
enum DuckImpact {
 static func contains(_ point:CGPoint,in water:CGRect)->Bool {
  guard water.width>0,water.height>0,point.x.isFinite,point.y.isFinite else{return false}
  // A falling particle first touches maxY in AppKit coordinates. CGRect.contains
  // excludes that edge; include the contact boundary with a sub-pixel tolerance.
  return water.insetBy(dx:-0.75,dy:-0.75).contains(point)
 }
}

enum DuckPointer {
 static let cursor:NSCursor = {
  guard let url=Bundle.main.url(forResource:"duck-cursor",withExtension:"png"),let bytes=try? Data(contentsOf:url),let image=NSImage(data:bytes),let pixels=NSBitmapImageRep(data:bytes) else{return .pointingHand}
  let side=32.0,w=pixels.pixelsWide,h=pixels.pixelsHigh
  var hotspot=NSPoint(x:side*0.30,y:side*0.15)
  // Find the first substantial alpha row; ignore isolated antialiasing pixels.
  outer: for y in 0..<(h/2) {
   var xs:[Int]=[]
   for x in 0..<w {if (pixels.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.65 {xs.append(x)}}
   if xs.count>=max(4,w/160) {hotspot=NSPoint(x:Double(xs.reduce(0,+))/Double(xs.count)/Double(w)*side,y:Double(y)/Double(h)*side);break outer}
  }
  image.size=NSSize(width:side,height:side)
  return NSCursor(image:image,hotSpot:hotspot)
 }()
}

/// Report only this application's visible desktop water bounds, never another app's windows.
protocol DuckWaterWindow:AnyObject {var duckWaterRegion:NSRect? {get set}}

struct WaterFrameReporter:NSViewRepresentable {
 var pointing=true
 var lastImpact:Double=0
 var report:(CGRect)->Void
 func makeNSView(context:Context)->Reporter {Reporter()}
 static func dismantleNSView(_ view:Reporter,coordinator:()) {
  (view.window as? DuckWaterWindow)?.duckWaterRegion=nil
  try? FileManager.default.removeItem(at:GridPreferences.folder.appendingPathComponent("status/mac-water.json"))
 }
 func updateNSView(_ view:Reporter,context:Context) {view.report=report;view.pointing=pointing;view.lastImpact=lastImpact;view.window?.invalidateCursorRects(for:view);DispatchQueue.main.async{view.publish()}}
 final class Reporter:NSView {
  var report:((CGRect)->Void)?
  var pointing=true
  var lastImpact:Double=0
  private var hoverArea:NSTrackingArea?
  private var mouseMonitor:Any?
  private var pointerOwned=false
  deinit {if let mouseMonitor {NSEvent.removeMonitor(mouseMonitor)}}
  override func viewDidMoveToWindow() {
   super.viewDidMoveToWindow()
   if let mouseMonitor {NSEvent.removeMonitor(mouseMonitor);self.mouseMonitor=nil}
   guard let window else{return}
   window.acceptsMouseMovedEvents=true
   updateTrackingAreas()
   // Non-key desktop panels need activeAlways; cursor rectangles alone only
   // update reliably in key windows and can be reset by the SwiftUI link below.
   mouseMonitor=NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.cursorUpdate]) {[weak self] event in
    guard let self,event.window === self.window else{return event}
    DispatchQueue.main.async {[weak self] in self?.updatePointer()}
    return event
   }
   publish()
  }
  override func updateTrackingAreas() {
   super.updateTrackingAreas()
   if let hoverArea {removeTrackingArea(hoverArea)}
   let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.mouseMoved,.cursorUpdate,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
   addTrackingArea(area);hoverArea=area
  }
  private func updatePointer() {
   guard let window,window.isVisible else{return}
   let point=convert(window.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
   if pointing,bounds.contains(point) {DuckPointer.cursor.set();pointerOwned=true}
   else if pointerOwned {NSCursor.arrow.set();pointerOwned=false}
  }
  override func mouseEntered(with event:NSEvent) {updatePointer()}
  override func mouseMoved(with event:NSEvent) {updatePointer()}
  override func cursorUpdate(with event:NSEvent) {updatePointer()}
  override func mouseExited(with event:NSEvent) {if pointerOwned {NSCursor.arrow.set();pointerOwned=false}}
  override func resetCursorRects(){if pointing {addCursorRect(bounds,cursor:DuckPointer.cursor)}}
  var last=Date.distantPast
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func layout(){super.layout();publish()}
  func publish() {
   guard let window,window.isVisible,window.identifier?.rawValue=="MacVitalsCard",bounds.width>0,bounds.height>20 else{return}
   let local=convert(bounds,to:nil)
   (window as? DuckWaterWindow)?.duckWaterRegion=local
   let rect=window.convertToScreen(local)
   // Native screen coordinates have a bottom-left origin; only the lower water strip is wet.
   let water=CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:15)
   report?(water)
   guard Date().timeIntervalSince(last)>1 else{return};last=Date()
   let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HomeAtlasToolbox/status")
   try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   let data:[String:Double]=["x":water.minX,"y":water.minY,"width":water.width,"height":water.height,"updated":last.timeIntervalSince1970,"lastImpact":max(0,lastImpact)]
   if let bytes=try? JSONSerialization.data(withJSONObject:data){try? bytes.write(to:folder.appendingPathComponent("mac-water.json"),options:.atomic)}
  }
 }
}

struct WaterSurfaceAnchor:PreferenceKey {
 static var defaultValue:Anchor<CGRect>?=nil
 static func reduce(value:inout Anchor<CGRect>?,nextValue:()->Anchor<CGRect>?) {value=nextValue() ?? value}
}
struct AfterRainRainbow:View {
 var strength:Double
 var water:CGRect
 var body:some View {
  Canvas {ctx,size in
   guard strength>0 else{return}
   let colors:[Color]=[.red,.orange,.yellow,.green,.cyan,.blue,.purple]
   let surface=water.minY+25
   let center=CGPoint(x:water.minX+water.width*0.79,y:surface),radius=water.width*0.58,band=max(1.5,water.width*0.012)
   ctx.clip(to:Path(CGRect(x:0,y:0,width:size.width,height:surface)))
   for (i,color) in colors.enumerated() {
    var arc=Path();arc.addArc(center:center,radius:radius-Double(i)*band,startAngle:.degrees(180),endAngle:.degrees(360),clockwise:false)
    ctx.stroke(arc,with:.linearGradient(Gradient(colors:[color.opacity(0.13*strength),.clear]),startPoint:CGPoint(x:0,y:surface-10),endPoint:CGPoint(x:0,y:surface)),style:StrokeStyle(lineWidth:band*1.4,lineCap:.round))
   }
  }.blur(radius:2.2).accessibilityHidden(true)
 }
}

/// Only a same-day boolean is shared; no contact or birthday details leave Calendar.
enum BirthdayBadgeSignal {
    struct Payload:Codable {let active:Bool;let generatedAt:Double;let validUntil:Double}
    static var lastCheck=Date.distantPast
    static var cached:Payload?
    static func isActive(_ payload:Payload?,at now:Date)->Bool {
        guard let p=payload,p.generatedAt.isFinite,p.validUntil.isFinite else{return false}
        let t=now.timeIntervalSince1970
        return p.active && p.generatedAt<=t+5 && t-p.generatedAt<26*3600 && p.validUntil>t && p.validUntil-p.generatedAt<=26*3600
    }
    static func current(at now:Date)->Bool {
        if abs(now.timeIntervalSince(lastCheck))>15 {
            lastCheck=now
            let file=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox/status/calendar-birthday.json")
            cached=(try? Data(contentsOf:file)).flatMap{data in data.count<1024 ? try? JSONDecoder().decode(Payload.self,from:data):nil}
        }
        return isActive(cached,at:now)
    }
}

