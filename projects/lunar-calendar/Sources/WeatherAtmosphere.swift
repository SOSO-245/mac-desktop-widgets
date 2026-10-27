import SwiftUI
import AppKit

enum WeatherScene:String,CaseIterable,Identifiable {
    case none,rain,fog,wind,snow,frost,typhoon,dust,thunder
    var id:String {rawValue}
    var title:String {
        switch self {case .none:return "无";case .rain:return "下雨";case .fog:return "起雾";case .wind:return "大风";case .snow:return "下雪";case .frost:return "薄霜";case .typhoon:return "台风";case .dust:return "沙尘";case .thunder:return "雷雨"}
    }
    static func resolve(_ reading:CalendarWeatherReading?,now:Date=Date())->Self {
        guard let reading=reading?.validated(now:now) else{return .none}
        let text=reading.condition.lowercased()
        if ["台风","飓风","typhoon","hurricane","tropical cyclone"].contains(where:text.contains) {return .typhoon}
        if ["沙尘","扬沙","浮尘","sandstorm","dust"].contains(where:text.contains) {return .dust}
        if ["霜","冻雨","frost","freezing"].contains(where:text.contains) {return .frost}
        if reading.icon=="thunderstorms" {return .thunder}
        if reading.icon=="snow" {return .snow}
        if reading.icon=="rain" {return .rain}
        if reading.icon=="fog" {return .fog}
        if reading.icon=="wind" || (reading.windSpeedMs ?? 0)>=10.8 {return .wind}
        // A decorative cold-edge effect, not a frost warning inferred from temperature.
        if let temperature=reading.temperature,temperature<=0 {return .frost}
        return .none
    }
}

/// Decode each AI-generated texture once. Tests may provide an explicit fixture folder.
enum WeatherTexture {
    static var frost: NSImage? = load("frost-edge-ai")
    static var leaf: NSImage? = load("wind-leaf-ai")
    private static func load(_ name:String)->NSImage? {
        if let folder=ProcessInfo.processInfo.environment["WEATHER_TEXTURE_TEST_DIR"],
           let image=NSImage(contentsOfFile:URL(fileURLWithPath:folder).appendingPathComponent(name+".png").path) {return image}
        guard let url=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"WeatherTextures") else{return nil}
        return NSImage(contentsOf:url)
    }
}

/// Bounded native atmosphere behind the content, not an embedded webpage.
struct WeatherAtmosphere:View {
    var scene:WeatherScene
    var intensity:Double=0.65
    var fixedTime:Double?=nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        if scene != .none {
            TimelineView(.animation(minimumInterval:1.0/24,paused:reduceMotion || fixedTime != nil)) { timeline in
                Canvas { context,size in
                    let t=reduceMotion ? 0:(fixedTime ?? timeline.date.timeIntervalSinceReferenceDate)
                    let w=size.width,h=size.height
                    func unit(_ value:Double)->Double {value-floor(value)}
                    func seed(_ i:Int)->Double {unit(sin(Double(i)*127.1+4.7)*43758.5453)}
                    let blue=Color(red:0.65,green:0.85,blue:1)
                    // Soft overlapping vapor, kept at the perimeter to preserve text contrast.
                    func clouds(_ opacity:Double,_ speed:Double) {
                        var vapor=context;vapor.addFilter(.blur(radius:5))
                        for i in 0..<14 {
                            let x=unit(seed(i+401)+t*speed)*(w+180)-90
                            let y=i%2==0 ? -14+seed(i+7)*25:h+8-seed(i+5)*21
                            let radius=35+seed(i+50)*48
                            let rect=CGRect(x:x-radius,y:y-radius*0.42,width:radius*2,height:radius*0.84)
                            vapor.fill(Path(ellipseIn:rect),with:.radialGradient(Gradient(colors:[blue.opacity(opacity*(0.5+seed(i))),.clear]),center:CGPoint(x:x,y:y),startRadius:0,endRadius:radius))
                        }
                    }
                    switch scene {
                    case .rain,.thunder:
                        for i in 0..<44 {
                            let depth=0.4+seed(i)*0.6
                            let y=unit(seed(i+90)+t*(0.6+depth*0.7))*h
                            let x=unit(seed(i+4)-t*0.09)*w
                            var line=Path();line.move(to:CGPoint(x:x,y:y));line.addLine(to:CGPoint(x:x-3*depth,y:y+10*depth))
                            context.stroke(line,with:.color(blue.opacity(0.16+depth*0.22)),style:StrokeStyle(lineWidth:0.65,lineCap:.round))
                        }
                        if scene == .thunder {
                            // Soft dark sky, without a visible ellipse or pulsing cloud blob.
                            context.fill(Path(CGRect(x:0,y:0,width:w,height:h*0.6)),with:.linearGradient(Gradient(colors:[.black.opacity(0.19),.clear]),startPoint:.zero,endPoint:CGPoint(x:0,y:h*0.6)))
                            let cycle=floor(t/10),phase=t-cycle*10
                            let event=phase>=7.4 ? 1:0
                            let age=phase-(event==0 ? 2.0:7.4)
                            if age>=0 && age<0.55 {
                                let alpha=age<0.055 ? age/0.055:pow(max(0,1-(age-0.055)/0.495),2)
                                let salt=Int(cycle)*101+event*197
                                let start=CGPoint(x:w*(0.35+seed(salt+22)*0.45),y:-3)
                                let end=CGPoint(x:start.x+w*(seed(salt+32)-0.5)*0.35,y:h*0.78)
                                func split(_ a:CGPoint,_ b:CGPoint,_ spread:Double,_ depth:Int,_ n:Int)->[CGPoint] {
                                    if depth==0 {return [a,b]}
                                    let dx=b.x-a.x,dy=b.y-a.y,length=max(1,hypot(dx,dy))
                                    let displacement=(seed(n+salt)-0.5)*spread
                                    let mid=CGPoint(x:(a.x+b.x)/2-dy/length*displacement,y:(a.y+b.y)/2+dx/length*displacement)
                                    return Array(split(a,mid,spread*0.53,depth-1,n*2+1).dropLast())+split(mid,b,spread*0.53,depth-1,n*2+2)
                                }
                                let points=split(start,end,42,5,7)
                                func path(_ pts:[CGPoint])->Path {var p=Path();p.addLines(pts);return p}
                                let bolt=path(points)
                                var light=context;light.addFilter(.blur(radius:3))
                                light.stroke(bolt,with:.color(.cyan.opacity(alpha*0.42)),style:StrokeStyle(lineWidth:4,lineCap:.round))
                                context.stroke(bolt,with:.color(.white.opacity(alpha)),style:StrokeStyle(lineWidth:1.05,lineCap:.round))
                                for j in 0..<3 {
                                    let point=points[7+j*6]
                                    let tip=CGPoint(x:point.x+(j%2==0 ? -1:1)*(18+seed(j+salt+61)*31),y:point.y+18+seed(j+salt+71)*25)
                                    let branch=path(split(point,tip,13,3,j+92))
                                    light.stroke(branch,with:.color(.cyan.opacity(alpha*0.25)),lineWidth:2)
                                    context.stroke(branch,with:.color(.white.opacity(alpha*0.65)),lineWidth:0.5)
                                }
                                context.fill(Path(CGRect(x:0,y:0,width:w,height:h)),with:.radialGradient(Gradient(colors:[.white.opacity(alpha*0.065),.clear]),center:start,startRadius:0,endRadius:w*0.6))
                            }
                        }
                    case .snow:
                        for i in 0..<34 {
                            let depth=0.4+seed(i)*0.6,radius=1+depth*1.8
                            let x=unit(seed(i+9)+sin(t*0.7+Double(i))*0.03)*w
                            let y=unit(seed(i+90)+t*(0.04+depth*0.05))*h
                            context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:radius,height:radius)),with:.color(.white.opacity(0.28+depth*0.25)))
                        }
                    case .fog:
                        var mist=context;mist.addFilter(.blur(radius:16))
                        for i in 0..<4 {
                            let x=sin(t*0.16+Double(i)*2)*w*0.2-w*0.2
                            let y=h*Double(i)/3-12
                            mist.fill(Path(ellipseIn:CGRect(x:x,y:y,width:w*1.4,height:40)),with:.color(.white.opacity(0.11)))
                        }
                    case .wind:
   for i in 0..<13 {
    let depth=0.55+Double(i%4)*0.15
    let phase=(t/6+Double(i)*0.076923).truncatingRemainder(dividingBy:1)
    let x=phase*(w+60)-30
    let baseY = 15+Double((i*37)%133)
    let y=baseY+sin(phase*Double.pi*2+Double(i))*9
    var c=context
    c.translateBy(x:x,y:y)
    c.rotate(by:.degrees(-32+sin(t*Double.pi/3+Double(i))*18))
    c.scaleBy(x:depth,y:depth)
    c.opacity=min(1,phase*10,(1-phase)*10)*0.72
    var stem=Path();stem.move(to:CGPoint(x:0,y:0));stem.addQuadCurve(to:CGPoint(x:2,y:14),control:CGPoint(x:-1,y:7))
    c.stroke(stem,with:.color(.white.opacity(0.75)),style:StrokeStyle(lineWidth:0.55,lineCap:.round))
    c.fill(Path(ellipseIn:CGRect(x:1.1,y:12,width:1.6,height:4)),with:.color(Color(red:0.83,green:0.76,blue:0.58)))
    for j in 0..<11 {
     let angle=Double.pi+Double(j)/10*Double.pi
     let px=cos(angle)*9,py=sin(angle)*7-2
     var hair=Path();hair.move(to:.zero);hair.addQuadCurve(to:CGPoint(x:px,y:py),control:CGPoint(x:px*0.35,y:py*0.65))
     c.stroke(hair,with:.color(.white.opacity(0.85)),style:StrokeStyle(lineWidth:0.42,lineCap:.round))
     var wisps=Path();wisps.move(to:CGPoint(x:px-1.4,y:py+0.6));wisps.addLine(to:CGPoint(x:px,y:py-1));wisps.addLine(to:CGPoint(x:px+1.4,y:py+0.6))
     c.stroke(wisps,with:.color(.white.opacity(0.7)),lineWidth:0.35)
    }
   }
                    case .dust:
                        for i in 0..<65 {
                            let x=unit(seed(i)+t*0.12)*1.3*w-0.15*w
                            let y=seed(i+30)*h+sin(t+Double(i))*4
                            context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1+seed(i+4)*2.5,height:1.3)),with:.color(Color.orange.opacity(0.16+seed(i)*0.2)))
                        }
                        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.orange.opacity(0.045)))
                    case .frost:
                        if let image=WeatherTexture.frost {
                            var frost=context
                            // Keep the actual crystalline texture; slow changes in translucency only.
                            frost.opacity=0.46+0.06*sin(t*0.25)
                            // Preserve the original frost artwork; enlarge its inset perimeter to the card edge.
                            frost.draw(context.resolve(Image(nsImage:image)),in:CGRect(x:-14,y:-26,width:w+28,height:h+52))
                        }
                    case .typhoon:
                        // Horizontal storm scene: wind-driven rain beneath fast rolling cloud banks.
                        clouds(0.35,0.085)
                        let gust=sin(t*0.7)*0.025
                        for i in 0..<76 {
                            let depth=0.35+seed(i)*0.65
                            let x=unit(seed(i+4)+t*(0.32+depth*0.19)+gust)*(w+50)-25
                            let y=unit(seed(i+90)+t*(0.26+depth*0.17))*h
                            let length=8+depth*15
                            var rain=Path();rain.move(to:CGPoint(x:x,y:y));rain.addLine(to:CGPoint(x:x+length,y:y+length*0.45))
                            context.stroke(rain,with:.color(blue.opacity(0.12+depth*0.22)),style:StrokeStyle(lineWidth:0.5+depth*0.25,lineCap:.round))
                        }
                    case .none:break
                    }
                }
            }.opacity(min(1,max(0.2,intensity))).clipShape(RoundedRectangle(cornerRadius:28,style:.continuous))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
