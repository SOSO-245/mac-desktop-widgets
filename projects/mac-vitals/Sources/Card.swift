import SwiftUI
let neon=Color(red:0.40,green:1,blue:0.70)
let violet=Color(red:0.69,green:0.55,blue:1)
/// Monotone cubic interpolation keeps samples and prevents overshoot.
struct SmoothLine:Shape {
    var values:[Double]
    func path(in r:CGRect)->Path {
        var p=Path()
        guard values.count>1,r.width>0,r.height>0,values.allSatisfy({$0.isFinite}) else{return p}
        let lo=min(0,values.min() ?? 0),hi=max(1,values.max() ?? 1)
        let points=values.enumerated().map{CGPoint(x:r.minX+r.width*Double($0.offset)/Double(values.count-1),y:r.minY+r.height*(1-($0.element-lo)/(hi-lo)))}
        let dx=r.width/Double(values.count-1)
        let slopes=(0..<(points.count-1)).map{(points[$0+1].y-points[$0].y)/dx}
        var tangents=Array(repeating:0.0,count:points.count)
        tangents[0]=slopes[0];tangents[points.count-1]=slopes.last!
        if points.count>2 {
            for i in 1..<(points.count-1) {
                let a=slopes[i-1],b=slopes[i]
                tangents[i]=a*b<=0 ? 0:2*a*b/(a+b)
            }
        }
        // Bound tangent length so controls remain inside each sample interval.
        for i in slopes.indices {
            if slopes[i]==0 {tangents[i]=0;tangents[i+1]=0;continue}
            let a=tangents[i]/slopes[i],b=tangents[i+1]/slopes[i],length=hypot(a,b)
            if length>3 {let factor=3/length;tangents[i]=factor*a*slopes[i];tangents[i+1]=factor*b*slopes[i]}
        }
        p.move(to:points[0])
        for i in slopes.indices {
            p.addCurve(to:points[i+1],control1:CGPoint(x:points[i].x+dx/3,y:points[i].y+tangents[i]*dx/3),control2:CGPoint(x:points[i+1].x-dx/3,y:points[i+1].y-tangents[i+1]*dx/3))
        }
        return p
    }
}
struct VitalsCard:View {
    var menuSurface=false
    let data:Metrics
    var size="medium",widget=false,locked=false
    var onLock:(()->Void)?=nil,onMenu:(()->Void)?=nil,onHide:(()->Void)?=nil
    private var small:Bool{size=="small"};private var large:Bool{size=="large"}
    private var fresh:Bool{data.fresh()}
    private func metric(_ title:String,_ value:String,_ color:Color = .white)->some View {
        VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:small ? 10:11,weight:.medium)).foregroundStyle(.white.opacity(0.60));Text(value).font(.system(size:small ? 17:23,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    var body:some View {
        Group {if widget {widgetBody} else {desktopBody}}
    }
    private func desktopMetric(_ title:String,_ value:String,_ color:Color = .white)->some View {
        VStack(alignment:.leading,spacing:2) {
            Text(title).font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.60))
            Text(value).font(.system(size:large ? 21:18,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var temperatureValue:some View {
        HStack(spacing:5) {
            TemperatureFace(value:fresh ? data.cpuTemp:nil,displayMood:fresh ? data.temperatureDisplayMood:-1).frame(width:large ? 22:18,height:large ? 22:18)
            Text(Metrics.value(fresh ? data.cpuTemp:nil," °C",decimals:1)).monospacedDigit()
        }
    }
    private var desktopBody:some View {
        VStack(alignment:.leading,spacing:large ? 7:4) {
            HStack(spacing:7) {
                Image(systemName:"desktopcomputer").foregroundStyle(neon)
                Text(small ? "Mac 状态":"Mac 实时监测").font(.system(size:small ? 12:15,weight:.bold)).lineLimit(1)
                Spacer(minLength:0)
                Button(action:{onLock?()}) {Image(systemName:locked ? "lock.fill":"lock.open").foregroundStyle(.cyan)}.help(locked ? "解锁位置":"锁定位置")
            }.buttonStyle(.plain).frame(height:20)
            HStack(alignment:.center,spacing:10) {
                VStack(alignment:.leading,spacing:1) {
                    Text(data.powerLabel).font(.system(size:9)).foregroundStyle(.white.opacity(0.60))
                    HStack(alignment:.firstTextBaseline,spacing:3) {
                        Text(Metrics.value(fresh ? data.power:nil,decimals:1)).font(.system(size:large ? 39:30,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text("W").font(.system(size:11,weight:.semibold))
                    }.foregroundStyle(neon)
                }
                Spacer(minLength:0)
                if large {
                    VStack(alignment:.trailing,spacing:3) {
                        Text(data.chip).font(.system(size:10)).foregroundStyle(.white.opacity(0.6))
                        temperatureValue.font(.system(size:20,weight:.semibold,design:.rounded)).foregroundStyle(.cyan)
                        Text("CPU 温度").font(.system(size:9)).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    VStack(alignment:.trailing,spacing:4) {
                        Text("CPU "+Metrics.value(fresh ? data.cpu:nil,"%")+" · 内存 "+Metrics.value(fresh ? data.memoryPercent:nil,"%"))
                        temperatureValue.foregroundStyle(.cyan)
                    }.font(.system(size:small ? 10:12,weight:.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if large {HStack(spacing:10) {
                desktopMetric("CPU",Metrics.value(fresh ? data.cpu:nil,"%"))
                desktopMetric("内存",Metrics.value(fresh ? data.memoryPercent:nil,"%"),violet)
                desktopMetric("内存已用",Metrics.value(fresh ? data.memoryUsed.map{$0/1073741824}:nil," GB",decimals:1))
            }}
            Divider().overlay(.white.opacity(0.10))
            HStack(spacing:12) {
                HStack(spacing:6) { FlowTrail(reverse:false,tint:.cyan,active:fresh && (data.download ?? 0)>0).frame(width:12,height:32); desktopMetric("下载",Metrics.rate(fresh ? data.download:nil),.cyan) }
                HStack(spacing:6) { FlowTrail(reverse:true,tint:violet,active:fresh && (data.upload ?? 0)>0).frame(width:12,height:32); desktopMetric("上传",Metrics.rate(fresh ? data.upload:nil),violet) }
            }
            if large {
                VStack(alignment:.leading,spacing:5) {
                    Text("最近一分钟 · 功率").font(.system(size:10)).foregroundStyle(.white.opacity(0.6))
                    GlowPower(values:fresh ? data.history:[]).frame(height:32)
                }.padding(8).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                HStack {
                    Text("芯片 "+Metrics.value(fresh ? data.chipPower:nil," W",decimals:1)).foregroundStyle(neon)
                    Spacer()
                    Text("GPU "+Metrics.value(fresh ? data.gpuTemp:nil," °C",decimals:1)).foregroundStyle(violet)
                }.font(.system(size:12,weight:.medium)).monospacedDigit()
                HStack(spacing:5) {
                    Image(systemName:"fanblades").foregroundStyle(.cyan)
                    Text("风扇").foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength:2)
                    Text(fresh ? data.fanText:"—").monospacedDigit().foregroundStyle(.white.opacity(0.85))
                }.font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength:0)
            HStack(spacing:4) {
                Circle().fill(fresh ? neon:.gray).frame(width:4,height:4)
                Text(fresh ? (large ? "每秒更新":"风扇 "+data.fanText):"数据已过期，请打开应用")
                Spacer(minLength:0)
                if data.date != .distantPast {Text(data.date,style:.time)}
            }.font(.system(size:8,weight:.medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }.padding(14).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background {
            if !menuSurface {RoundedRectangle(cornerRadius:28).fill(LinearGradient(colors:[Color(red:0.18,green:0.17,blue:0.34),Color(red:0.055,green:0.075,blue:0.13),Color(red:0.13,green:0.11,blue:0.26)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay {RoundedRectangle(cornerRadius:28).strokeBorder(LinearGradient(colors:[.white.opacity(0.4),.white.opacity(0.06),violet.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1)}}
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private var widgetBody:some View {
        VStack(alignment:.leading,spacing:small ? 9:13){
            HStack(spacing:7){Image(systemName:"desktopcomputer").foregroundStyle(neon);Text(small ? "Mac 状态":"Mac 实时监测").font(.system(size:small ? 12:15,weight:.bold)).lineLimit(1);Spacer(minLength:0)
                if !widget {Button(action:{onLock?()}){Image(systemName:locked ? "lock.fill":"lock.open").foregroundStyle(.cyan)}.help(locked ? "解锁位置":"锁定位置")}
            }.buttonStyle(.plain)
            HStack(alignment:.firstTextBaseline){
                VStack(alignment:.leading,spacing:3){Text(data.powerLabel).font(.system(size:10)).foregroundStyle(.white.opacity(0.60));HStack(alignment:.firstTextBaseline,spacing:4){Text(Metrics.value(fresh ? data.power:nil,decimals:1)).font(.system(size:small ? 30:40,weight:.medium,design:.rounded));Text("W").font(.system(size:13,weight:.semibold)).foregroundStyle(.white.opacity(0.65))}.foregroundStyle(neon)}
                Spacer(minLength:8)
                if !small {VStack(alignment:.trailing,spacing:7){Text(data.chip).font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.6));temperatureValue.font(.system(size:19,weight:.semibold,design:.rounded)).foregroundStyle(.cyan);Text("CPU 温度").font(.system(size:9)).foregroundStyle(.white.opacity(0.5))}}
            }
            HStack(spacing:12){metric("CPU",Metrics.value(fresh ? data.cpu:nil,"%"),.white);metric("内存",Metrics.value(fresh ? data.memoryPercent:nil,"%"),violet)
                if !small {metric("内存已用",Metrics.value(fresh ? data.memoryUsed.map{$0/1073741824}:nil," GB",decimals:1),.white)}
            }
            if !small {Divider().overlay(.white.opacity(0.10));HStack(spacing:12){metric("↓ 下载",Metrics.rate(fresh ? data.download:nil),.cyan);metric("↑ 上传",Metrics.rate(fresh ? data.upload:nil),violet)}}
            if large {
                VStack(alignment:.leading,spacing:8){HStack{Text("最近一分钟 · 功率");Spacer();Text(data.powerLabel)}.font(.system(size:10)).foregroundStyle(.white.opacity(0.6));SmoothLine(values:data.history).stroke(neon,style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round)).frame(height:52)}.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
                HStack{metric("芯片功率",Metrics.value(fresh ? data.chipPower:nil," W",decimals:1),neon);metric("GPU 温度",Metrics.value(fresh ? data.gpuTemp:nil," °C",decimals:1),violet)}
            }
            HStack(spacing:4){Circle().fill(fresh ? neon:.gray).frame(width:4,height:4);Text(fresh ? "风扇 "+data.fanText : "数据已过期，请打开应用");Spacer(minLength:0);if data.date != .distantPast {Text(data.date,style:.time)}}.font(.system(size:small ? 8:9,weight:.medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }.padding(small ? 14:18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background {
            if !widget && !menuSurface {RoundedRectangle(cornerRadius:28).fill(LinearGradient(colors:[Color(red:0.18,green:0.17,blue:0.34),Color(red:0.055,green:0.075,blue:0.13),Color(red:0.13,green:0.11,blue:0.26)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay{RoundedRectangle(cornerRadius:28).strokeBorder(LinearGradient(colors:[.white.opacity(0.4),.white.opacity(0.06),violet.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1)}}
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
}

struct FlowTrailFrame:View {
 let time:Double;let reverse:Bool;let tint:Color
 var body:some View {
  Canvas { context,size in
   let x=size.width/2
   for i in 0..<3 {
    let p=(time/3+Double(i)/3).truncatingRemainder(dividingBy:1)
    let y=4+(size.height-8)*(reverse ? 1-p:p)
    let fade=sin(p*Double.pi)
    var chevron=Path();let d=reverse ? -1.0:1.0
    chevron.move(to:CGPoint(x:x-3,y:y-d*2));chevron.addLine(to:CGPoint(x:x,y:y+d*1));chevron.addLine(to:CGPoint(x:x+3,y:y-d*2))
    context.stroke(chevron,with:.color(tint.opacity(fade*0.8)),style:StrokeStyle(lineWidth:1.2,lineCap:.round,lineJoin:.round))
   }
  }
 }
}
struct GlowPowerFrame:View {
 let values:[Double];let time:Double
 var body:some View {
  GeometryReader { g in
   let hi=max(1,values.max() ?? 1)
   let y=g.size.height*(1-(values.last ?? 0)/hi)
   let pulse=0.5+0.5*sin(time*Double.pi)
   ZStack(alignment:.topLeading) {
    SmoothLine(values:values).stroke(neon.opacity(0.22),lineWidth:5).blur(radius:2)
    SmoothLine(values:values).stroke(neon,style:StrokeStyle(lineWidth:1.6,lineCap:.round,lineJoin:.round))
    if !values.isEmpty { Circle().fill(neon.opacity(0.14+0.12*pulse)).frame(width:12+3*pulse,height:12+3*pulse).blur(radius:3).position(x:g.size.width,y:y)
    Circle().fill(.white).frame(width:3.5,height:3.5).position(x:g.size.width,y:y) }
   }
  }
 }
}

struct FlowTrail:View {
 let reverse:Bool
 let tint:Color
 var active=true
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 var body:some View {
  if !active { Color.clear }
  else if reduceMotion { FlowTrailFrame(time:0.75,reverse:reverse,tint:tint) }
  else { TimelineView(.animation(minimumInterval:1.0/24)) { context in
   FlowTrailFrame(time:context.date.timeIntervalSinceReferenceDate,reverse:reverse,tint:tint)
  } }
 }
}
struct GlowPower:View {
 let values:[Double]
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 var body:some View {
  if reduceMotion { GlowPowerFrame(values:values,time:0) }
  else { TimelineView(.animation(minimumInterval:1.0/24)) { context in
   GlowPowerFrame(values:values,time:context.date.timeIntervalSinceReferenceDate)
  } }
 }
}

/// Original small vector faces matching the glass card palette; no emoji font or remote assets.
struct TemperatureFace:View {
 let value:Double?
 var displayMood:Int?=nil
 private var mood:Int { displayMood ?? Metrics.temperatureMood(value) }
 private var tint:Color {
  switch mood {case 0:return .cyan;case 1:return neon;case 2:return Color(red:1,green:0.85,blue:0.35);case 3:return Color(red:1,green:0.30,blue:0.40);case 4:return violet;default:return .gray}
 }
 var body:some View {
  Canvas { context,size in
   let scale=min(size.width,size.height)/24
   context.scaleBy(x:scale,y:scale)
   let circle=Path(ellipseIn:CGRect(x:3,y:3,width:18,height:18))
   var glow=context;glow.addFilter(.blur(radius:1.4));glow.stroke(circle,with:.color(tint.opacity(0.27)),lineWidth:2)
   context.fill(circle,with:.color(tint.opacity(0.07)));context.stroke(circle,with:.color(tint.opacity(0.92)),lineWidth:1.2)
   var features=Path()
   if mood>=3 {
    features.move(to:CGPoint(x:7.3,y:10.6));features.addQuadCurve(to:CGPoint(x:10,y:10.6),control:CGPoint(x:8.65,y:8.7))
    features.move(to:CGPoint(x:14,y:10.6));features.addQuadCurve(to:CGPoint(x:16.7,y:10.6),control:CGPoint(x:15.35,y:8.7))
   } else {
    context.fill(Path(ellipseIn:CGRect(x:7.6,y:9.3,width:1.7,height:2.1)),with:.color(tint))
    context.fill(Path(ellipseIn:CGRect(x:14.7,y:9.3,width:1.7,height:2.1)),with:.color(tint))
   }
   if mood==0 || mood==1 {
    features.move(to:CGPoint(x:8,y:14));features.addQuadCurve(to:CGPoint(x:16,y:14),control:CGPoint(x:12,y:mood==0 ? 18:16.5))
   } else if mood==3 {
    features.move(to:CGPoint(x:9,y:15.3));features.addQuadCurve(to:CGPoint(x:15,y:15.3),control:CGPoint(x:12,y:14.5))
   } else if mood==4 {
    features.addEllipse(in:CGRect(x:10,y:14,width:4,height:3.4))
   } else {features.move(to:CGPoint(x:9,y:15));features.addLine(to:CGPoint(x:15,y:15))}
   context.stroke(features,with:.color(tint),style:StrokeStyle(lineWidth:1.25,lineCap:.round,lineJoin:.round))
   if mood>=3 {
    var drop=Path();drop.move(to:CGPoint(x:20.6,y:5));drop.addQuadCurve(to:CGPoint(x:22.6,y:9.2),control:CGPoint(x:23.4,y:8));drop.addQuadCurve(to:CGPoint(x:18.8,y:9.2),control:CGPoint(x:20.7,y:11.5));drop.addQuadCurve(to:CGPoint(x:20.6,y:5),control:CGPoint(x:18,y:8));drop.closeSubpath()
    context.fill(drop,with:.color(.cyan.opacity(0.9)))
   }
  }.accessibilityLabel(mood<0 ? "温度暂无读数":"温度状态表情")
 }
}
