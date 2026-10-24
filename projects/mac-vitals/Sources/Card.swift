import SwiftUI
let neon=Color(red:0.40,green:1,blue:0.70)
let violet=Color(red:0.69,green:0.55,blue:1)
struct SmoothLine:Shape {
    var values:[Double]
    func path(in r:CGRect)->Path {
        var p=Path();guard values.count>1 else{return p};let lo=min(0,values.min() ?? 0),hi=max(1,values.max() ?? 1)
        let pts=values.enumerated().map{CGPoint(x:r.width*Double($0.offset)/Double(values.count-1),y:r.height*(1-($0.element-lo)/(hi-lo)))}
        p.move(to:pts[0]);for i in 1..<pts.count {let a=pts[i-1],b=pts[i],mid=(a.x+b.x)/2;p.addCurve(to:b,control1:CGPoint(x:mid,y:a.y),control2:CGPoint(x:mid,y:b.y))};return p
    }
}
struct VitalsCard:View {
    let data:Metrics
    var size="medium",widget=false,locked=false
    var onLock:(()->Void)?=nil,onMenu:(()->Void)?=nil,onHide:(()->Void)?=nil
    private var small:Bool{size=="small"};private var large:Bool{size=="large"}
    private var fresh:Bool{data.fresh()}
    private func metric(_ title:String,_ value:String,_ color:Color = .white)->some View {
        VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:small ? 10:11,weight:.medium)).foregroundStyle(.white.opacity(0.60));Text(value).font(.system(size:small ? 17:23,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:small ? 9:13){
            HStack(spacing:7){Image(systemName:"desktopcomputer").foregroundStyle(neon);Text(small ? "Mac 状态":"Mac 实时监测").font(.system(size:small ? 12:15,weight:.bold)).lineLimit(1);Spacer(minLength:0)
                if !widget {Button(action:{onLock?()}){Image(systemName:locked ? "lock.fill":"lock.open").foregroundStyle(.cyan)}.help(locked ? "解锁位置":"锁定位置");Button(action:{onMenu?()}){Image(systemName:"ellipsis")}.help("卡片设置")}
            }.buttonStyle(.plain)
            HStack(alignment:.firstTextBaseline){
                VStack(alignment:.leading,spacing:3){Text(data.powerLabel).font(.system(size:10)).foregroundStyle(.white.opacity(0.60));HStack(alignment:.firstTextBaseline,spacing:4){Text(Metrics.value(fresh ? data.power:nil,decimals:1)).font(.system(size:small ? 30:40,weight:.medium,design:.rounded));Text("W").font(.system(size:13,weight:.semibold)).foregroundStyle(.white.opacity(0.65))}.foregroundStyle(neon)}
                Spacer(minLength:8)
                if !small {VStack(alignment:.trailing,spacing:7){Text(data.chip).font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.6));Text(Metrics.value(fresh ? data.cpuTemp:nil," °C",decimals:1)).font(.system(size:19,weight:.semibold,design:.rounded)).foregroundStyle(.cyan);Text("CPU 温度").font(.system(size:9)).foregroundStyle(.white.opacity(0.5))}}
            }
            HStack(spacing:12){metric("CPU",Metrics.value(fresh ? data.cpu:nil,"%"),.white);metric("内存",Metrics.value(fresh ? data.memoryPercent:nil,"%"),violet)
                if !small {metric("内存已用",Metrics.value(fresh ? data.memoryUsed.map{$0/1073741824}:nil," GB",decimals:1),.white)}
            }
            if !small {Divider().overlay(.white.opacity(0.10));HStack(spacing:12){metric("↓ 下载",Metrics.rate(fresh ? data.download:nil),.cyan);metric("↑ 上传",Metrics.rate(fresh ? data.upload:nil),violet)}}
            if large {
                VStack(alignment:.leading,spacing:8){HStack{Text("最近一分钟 · 功率");Spacer();Text(data.powerLabel)}.font(.system(size:10)).foregroundStyle(.white.opacity(0.6));SmoothLine(values:data.history).stroke(neon,style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round)).frame(height:52)}.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
                HStack{metric("芯片功率",Metrics.value(fresh ? data.chipPower:nil," W",decimals:1),neon);metric("GPU 温度",Metrics.value(fresh ? data.gpuTemp:nil," °C",decimals:1),violet)}
            }
            HStack(spacing:4){Circle().fill(fresh ? neon:.gray).frame(width:4,height:4);Text(fresh ? (widget ? "快照":"每秒更新") : "数据已过期，请打开应用");Spacer(minLength:0);if data.date != .distantPast {Text(data.date,style:.time)}}.font(.system(size:small ? 8:9,weight:.medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }.padding(small ? 14:18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background {
            if !widget {RoundedRectangle(cornerRadius:28).fill(LinearGradient(colors:[Color(red:0.18,green:0.17,blue:0.34),Color(red:0.055,green:0.075,blue:0.13),Color(red:0.13,green:0.11,blue:0.26)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay{RoundedRectangle(cornerRadius:28).strokeBorder(LinearGradient(colors:[.white.opacity(0.4),.white.opacity(0.06),violet.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1)}}
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
