import SwiftUI
@main struct CurveTests {
 static func main() {
  var checks=0
  func check(_ v:Bool){precondition(v);checks+=1}
  for values in [[18.0,19,18.5,22,21,24],[0,100,0,100,0],[12,12,12,12],[-3,-1,0,2]] {
   let rect=CGRect(x:8,y:11,width:310,height:48),path=SmoothLine(values:values).path(in:rect)
   var current=CGPoint.zero,lastSlope:Double?,curves=0
   path.forEach { element in
    switch element {
    case .move(to:let p): current=p
    case .curve(to:let end,control1:let c1,control2:let c2):
     let start=current,dx=end.x-start.x
     let beginSlope=(c1.y-start.y)/(c1.x-start.x),endSlope=(end.y-c2.y)/(end.x-c2.x)
     if let old=lastSlope {check(abs(old-beginSlope)<1e-7)}
     lastSlope=endSlope
     for t in stride(from:0.0,through:1,by:0.02) {
      let u=1-t,y=u*u*u*start.y+3*u*u*t*c1.y+3*u*t*t*c2.y+t*t*t*end.y
      check(y.isFinite && y>=min(start.y,end.y)-1e-7 && y<=max(start.y,end.y)+1e-7)
     }
     check(dx>0);current=end;curves+=1
    default:preconditionFailure("Expected cubic curves")
    }
   }
   check(curves==values.count-1)
  }
  check(SmoothLine(values:[]).path(in:CGRect(x:0,y:0,width:100,height:30)).isEmpty)
  check(SmoothLine(values:[1,.nan]).path(in:CGRect(x:0,y:0,width:100,height:30)).isEmpty)
  print("Curve geometry: \(checks) checks passed")
 }
}
