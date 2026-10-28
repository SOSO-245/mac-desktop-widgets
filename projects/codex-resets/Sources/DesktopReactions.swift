import AppKit
import SwiftUI
import Combine

/// Resolves the badge icon in its own card coordinates, including resized layouts.
struct DesktopReactionOrigin:View {
    var origin:Anchor<CGRect>?
    var report:(CGPoint)->Void
    var body:some View {
        GeometryReader { proxy in
            if let origin {
                let rect=proxy[origin],point=CGPoint(x:rect.midX,y:rect.midY)
                Color.clear.onAppear{report(point)}.onChange(of:point){_,value in report(value)}
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

final class ReactionOverlayPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}

struct DesktopReactionCanvas:View {
    @ObservedObject var feed:LiveReactions
    var source:CGRect
    var target:CGRect?
    var origin:CGPoint
    var fixedTime:Date?=nil
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:fixedTime != nil)) { timeline in
            Canvas { context,_ in
                var allowed=Path(roundedRect:source,cornerRadius:28)
                if let target=ReactionCrossing.validTarget(target,source:source) {
                    allowed.addRoundedRect(in:target,cornerSize:CGSize(width:28,height:28))
                    let gap=CGRect(x:target.maxX-1,y:max(source.minY,target.minY)+20,width:source.minX-target.maxX+2,height:max(0,min(source.maxY,target.maxY)-max(source.minY,target.minY)-40))
                    allowed.addRect(gap)
                }
                context.clip(to:allowed)
                for heart in feed.hearts {
                    let age=max(0,(fixedTime ?? timeline.date).timeIntervalSince(heart.born))
                    if let target,let entry=ReactionCrossing.entry(origin:origin,drift:heart.drift,rise:heart.rise,source:source,target:target),age>=entry.seconds {
                        let burst=(age-entry.seconds)/0.95
                        guard burst<1 else{continue}
                        // Stable random directions belong to the original heart, not each frame.
                        for branch in 0..<2 {
                            let angle=heart.burstAngle+(branch==0 ? 0:heart.burstSpread)
                            let travel=1-pow(1-burst,2)
                            let point=ReactionCrossing.burstPoint(entry:entry.point,target:target,angle:angle,distance:heart.burstDistance,progress:burst,padding:heart.size*0.65+3)
                            var bolt=context
                            bolt.clip(to:Path(roundedRect:target,cornerRadius:28))
                            bolt.opacity=0.9*pow(1-burst,1.2)
                            bolt.translateBy(x:point.x,y:point.y)
                            bolt.rotate(by:.degrees(heart.tilt*travel*(branch==0 ? 1:-1)))
                            let icon=Text(Image(systemName:"bolt.fill")).font(.system(size:heart.size*0.78,weight:.semibold)).foregroundColor(Color(red:1,green:0.83,blue:0.36))
                            bolt.draw(bolt.resolve(icon),at:.zero)
                        }
                        continue
                    }
                    let t=min(1,age/1.9)
                    guard t<1 else{continue}
                    let travel=1-pow(1-t,2)
                    let point=CGPoint(x:origin.x+heart.drift*travel,y:origin.y-heart.rise*travel)
                    guard let symbol=ReactionCrossing.symbol(at:point,drift:heart.drift,source:source,target:target) else{continue}
                    let bolt=symbol == .bolt
                    let color=bolt ? Color(red:1,green:0.83,blue:0.36):Color(red:1,green:0.35,blue:0.64)
                    let icon=Text(Image(systemName:bolt ? "bolt.fill":"heart.fill")).font(.system(size:heart.size,weight:.semibold)).foregroundColor(color)
                    var particle=context
                    particle.opacity=0.95*(1-t)
                    particle.translateBy(x:point.x,y:point.y)
                    particle.rotate(by:.degrees(heart.tilt*travel))
                    let scale=0.6+0.6*travel;particle.scaleBy(x:scale,y:scale)
                    particle.draw(particle.resolve(icon),at:.zero)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A passive transparent layer above our desktop cards. No global input hooks,
/// screen capture, foreign-window manipulation, HA data or extra network requests.
#if !REACTION_RENDER_TEST
@MainActor final class DesktopReactionOverlay {
    private let feed:LiveReactions
    private var subscription:AnyCancellable?
    private var panel:ReactionOverlayPanel?
    private var host:NSHostingView<DesktopReactionCanvas>?
    private var origin:CGPoint?
    private var active=false
    private var timer:Timer?
    private var latest:[ReactionHeart]=[]
    private var hitBranches:Set<String>=[]
    private var lastImpactCheck=Date()
    private var waterRecordName="home-water.json"
    private func impacts(source:CGRect,target:CGRect?,area:CGRect,origin:CGPoint) {
        let now=Date();defer{lastImpactCheck=now}
        let alive=Set(latest.flatMap{[$0.id.uuidString+"-0",$0.id.uuidString+"-1"]});hitBranches.formIntersection(alive)
        guard let target,let data=try? Data(contentsOf:GridPreferences.folder.appendingPathComponent("status/"+waterRecordName)),
         let record=try? JSONSerialization.jsonObject(with:data) as? [String:Double],let stamp=record["updated"],abs(now.timeIntervalSince1970-stamp)<3,
         let x=record["x"],let y=record["y"],let w=record["width"],let h=record["height"], [x,y,w,h].allSatisfy({$0.isFinite}),w>0,h>0 else{return}
        let water=CGRect(x:x-area.minX,y:area.maxY-y-h,width:w,height:h)
        guard target.contains(water) else{return}
        for heart in latest {
            guard let entry=ReactionCrossing.entry(origin:origin,drift:heart.drift,rise:heart.rise,source:source,target:target) else{continue}
            let age=now.timeIntervalSince(heart.born)-entry.seconds
            guard age>=0,age<=1.2 else{continue}
            let oldAge=max(0,lastImpactCheck.timeIntervalSince(heart.born)-entry.seconds)
            for branch in 0..<2 {
                let id=heart.id.uuidString+"-"+String(branch);guard !hitBranches.contains(id) else{continue}
                let angle=heart.burstAngle+(branch==0 ? 0:heart.burstSpread)
                let from=ReactionCrossing.burstPoint(entry:entry.point,target:target,angle:angle,distance:heart.burstDistance,progress:min(1,oldAge/0.95),padding:heart.size*0.65+3)
                let to=ReactionCrossing.burstPoint(entry:entry.point,target:target,angle:angle,distance:heart.burstDistance,progress:min(1,age/0.95),padding:heart.size*0.65+3)
                if let point=ReactionCrossing.waterImpact(from:from,to:to,water:water,radius:heart.size*0.39) {
                    hitBranches.insert(id)
                    DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.homeatlas.duck.impact.v1"),object:nil,userInfo:["x":point.x+area.minX,"y":area.maxY-point.y,"time":now.timeIntervalSince1970],deliverImmediately:true)
                }
            }
        }
    }
    init(feed:LiveReactions) {
        self.feed=feed
        subscription=feed.$hearts.sink {[weak self] hearts in
            self?.latest=hearts;self?.update()
        }
    }
    func setOrigin(_ point:CGPoint) {
        guard point.x.isFinite,point.y.isFinite,origin != point else{return}
        origin=point;update()
    }
    func setActive(_ enabled:Bool) {active=enabled;update()}
    private func waterTargetFrame(source:NSRect,screen:NSScreen)->NSRect? {
        let candidates=["local.homeatlas.HomeEnergy":"home-water.json","local.homeatlas.MacVitals":"mac-water.json"]
        var frames:[String:CGRect]=[:]
        let running=Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for (id,waterFile) in candidates {
            let file=GridPreferences.folder.appendingPathComponent("status/"+id+".json")
            guard running.contains(id),let bytes=try? Data(contentsOf:file),bytes.count<8192,
                  let presence=try? JSONDecoder().decode(CardPresence.self,from:bytes),presence.id==id,
                  presence.visible,presence.frame.valid,abs(presence.updated.timeIntervalSinceNow)<5,
                  screen.frame.contains(presence.frame.rect) else{continue}
            do {
                let waterURL=GridPreferences.folder.appendingPathComponent("status/"+waterFile)
                guard let bytes=try? Data(contentsOf:waterURL),bytes.count<8192,
                      let water=try? JSONSerialization.jsonObject(with:bytes) as? [String:Double],
                      let stamp=water["updated"],stamp.isFinite,abs(Date().timeIntervalSince1970-stamp)<3,
                      let x=water["x"],let y=water["y"],let w=water["width"],let h=water["height"],
                      [x,y,w,h].allSatisfy({$0.isFinite}),w>0,h>0,
                      presence.frame.rect.contains(CGRect(x:x,y:y,width:w,height:h)) else{continue}
            }
            frames[id]=presence.frame.rect
        }
        guard let id=ReactionCrossing.nearestTarget(frames,source:source) else{return nil}
        waterRecordName=candidates[id]!
        return frames[id]
    }
    private func update() {
        guard active,!latest.isEmpty,!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let sourceWindow=ToolboxBridge.shared.panel,sourceWindow.isVisible,
              let screen=sourceWindow.screen,let origin else {
            panel?.orderOut(nil);timer?.invalidate();timer=nil;return
        }
        let source=sourceWindow.frame,target=waterTargetFrame(source:source,screen:screen)
        let area=source.union(target ?? source).intersection(screen.frame)
        guard area.width>0,area.height>0 else{return}
        func converted(_ rect:CGRect)->CGRect {CGRect(x:rect.minX-area.minX,y:area.maxY-rect.maxY,width:rect.width,height:rect.height)}
        let localOrigin=CGPoint(x:source.minX-area.minX+origin.x,y:area.maxY-source.maxY+origin.y)
        impacts(source:converted(source),target:target.map(converted),area:area,origin:localOrigin)
        let view=DesktopReactionCanvas(feed:feed,source:converted(source),target:target.map(converted),origin:localOrigin)
        if panel==nil {
            let p=ReactionOverlayPanel(contentRect:area,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.ignoresMouseEvents=true
            p.isReleasedWhenClosed=false;p.hidesOnDeactivate=false;p.isExcludedFromWindowsMenu=true
            p.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
            p.identifier=NSUserInterfaceItemIdentifier("CodexReactionOverlay")
            let h=NSHostingView(rootView:view);p.contentView=h;panel=p;host=h
        }
        panel?.level=sourceWindow.level
        panel?.setFrame(area,display:false);host?.rootView=view
        panel?.orderFrontRegardless()
        if timer==nil {
            timer=Timer(timeInterval:0.25,repeats:true){[weak self] _ in Task{@MainActor in self?.update()}}
            RunLoop.main.add(timer!,forMode:.common)
        }
    }
}
#endif
