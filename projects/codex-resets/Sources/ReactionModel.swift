import Foundation
import CoreGraphics

/// Desktop-only crossing rule; never steers or attracts a particle toward a target.
enum ReactionCrossing {
    enum Symbol {case heart,bolt}
    static func nearestTarget(_ candidates:[String:CGRect],source:CGRect)->String? {
        candidates.filter{validTarget($0.value,source:source) != nil}.sorted {
            $0.value.maxX == $1.value.maxX ? $0.key < $1.key : $0.value.maxX > $1.value.maxX
        }.first?.key
    }
    static func validTarget(_ target:CGRect?,source:CGRect)->CGRect? {
        guard let target,target.width>0,target.height>0,
              target.maxX<=source.minX+1,source.minX-target.maxX<=180,
              min(source.maxY,target.maxY)>max(source.minY,target.minY) else{return nil}
        return target
    }
    static func symbol(at point:CGPoint,drift:Double,source:CGRect,target:CGRect?)->Symbol? {
        if source.contains(point) {return .heart}
        guard drift<0,point.x<source.minX,let target=validTarget(target,source:source) else{return nil}
        if target.contains(point) {return .bolt}
        // Only the horizontal gap shared by the two cards is open to a leftward heart.
        if point.x>=target.maxX,point.y>=max(target.minY,source.minY),point.y<=min(target.maxY,source.maxY) {return .heart}
        return nil
    }
    /// Scatter only inward, with both centers and glyph padding kept inside the target.
    static func burstPoint(entry:CGPoint,target:CGRect,angle:Double,distance:Double,progress:Double,padding:Double)->CGPoint {
        let margin=min(max(18,padding),min(target.width,target.height)/4)
        let safe=target.insetBy(dx:margin,dy:margin)
        let start=CGPoint(x:min(safe.maxX,max(safe.minX,entry.x)),y:min(safe.maxY,max(safe.minY,entry.y)))
        // Fold the random direction into the leftward half-plane, away from the entry edge.
        let dx = -max(0.28,abs(cos(angle))),dy=sin(angle)
        let length=sqrt(dx*dx+dy*dy)
        let end=CGPoint(x:max(safe.minX,start.x+dx/length*distance),y:min(safe.maxY,max(safe.minY,start.y+dy/length*distance)))
        let t=min(1,max(0,progress)),ease=1-pow(1-t,2)
        return CGPoint(x:start.x+(end.x-start.x)*ease,y:start.y+(end.y-start.y)*ease)
    }
    /// Swept collision avoids tunnelling across a thin water surface between frames.
    static func waterImpact(from:CGPoint,to:CGPoint,water:CGRect,radius:Double=0)->CGPoint? {
        guard water.width>0,water.height>0 else{return nil}
        let expanded=water.insetBy(dx:-max(0,radius),dy:-max(0,radius))
        var lower=0.0,upper=1.0
        for (start,delta,lo,hi) in [(from.x,to.x-from.x,expanded.minX,expanded.maxX),(from.y,to.y-from.y,expanded.minY,expanded.maxY)] {
            if abs(delta)<0.000001 {if start<lo || start>hi{return nil};continue}
            let a=(lo-start)/delta,b=(hi-start)/delta
            lower=max(lower,min(a,b));upper=min(upper,max(a,b))
        }
        guard lower<=upper else{return nil}
        return CGPoint(x:min(water.maxX,max(water.minX,from.x+(to.x-from.x)*lower)),y:min(water.maxY,max(water.minY,from.y+(to.y-from.y)*lower)))
    }
    /// First intersection of the unsteered heart trajectory with the target rectangle.
    /// Returns the common burst origin and elapsed time, so both bolts spawn once there.
    static func entry(origin:CGPoint,drift:Double,rise:Double,source:CGRect,target:CGRect?)->(point:CGPoint,seconds:Double)? {
        guard drift<0,let target=validTarget(target,source:source) else{return nil}
        var lower=0.0,upper=1.0
        for (start,delta,minValue,maxValue) in [(origin.x,drift,target.minX,target.maxX),(origin.y,-rise,target.minY,target.maxY)] {
            if abs(delta)<0.0001 {if start<minValue || start>maxValue{return nil};continue}
            let a=(minValue-start)/delta,b=(maxValue-start)/delta
            lower=max(lower,min(a,b));upper=min(upper,max(a,b))
        }
        guard lower<=upper,lower>=0,lower<1 else{return nil}
        return (CGPoint(x:origin.x+drift*lower,y:origin.y-rise*lower),(1-sqrt(1-lower))*1.9)
    }
}
struct ReactionCount:Decodable {
    let cycle_id:String
    let since:String?
    let count:Int
    var valid:Bool { !cycle_id.isEmpty && cycle_id.count<128 && count>=0 && count<=9_007_199_254_740_991 && (since==nil || date != nil) }
    var date:Date? {guard let since else{return nil};let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:since) ?? ISO8601DateFormatter().date(from:since)}
}
struct ReactionTracker {
    var value:ReactionCount?
    mutating func accept(_ next:ReactionCount,animate:Bool)->Int {
        guard next.valid else {return 0}
        if let old=value {
            if next.cycle_id==old.cycle_id {guard next.count>=old.count else{return 0}}
            else if (next.date ?? .distantPast)<(old.date ?? .distantPast) {return 0}
        }
        let delta = animate && value?.cycle_id==next.cycle_id ? max(0,next.count-(value?.count ?? next.count)):0
        value=next;return delta
    }
}
