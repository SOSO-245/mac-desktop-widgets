import AppKit
@main struct Tests {
    static func main() throws {
        let field=MenuField(id:"value",title:"实时数据",value:"123 W",color:.green)
        var config=MenuCustomization()
        precondition(config.text(field)=="123 W")
        config.labels["value"]="家里 {值}";precondition(config.text(field)=="家里 123 W")
        config.labels["value"]="我的家";precondition(config.text(field)=="我的家")
        config.visible["value"]=false;precondition(!config.shown(field))
        config.showIcon=false;config.icon="emoji";config.emoji="";config.enabled=true
        let fallback=config.render(fields:[field],fallback:nil);precondition(fallback.size.width>=18)
        let decoded=try JSONDecoder().decode(MenuCustomization.self,from:JSONEncoder().encode(config));precondition(decoded==config)
        precondition(MenuCustomization.hex(MenuCustomization.color("#12ABEF"))=="#12ABEF")
        precondition(MenuCustomization.hex(MenuCustomization.color("invalid"))=="#FFFFFF")
        let ring=MenuField(id:"ring",title:"剩余",value:"",ring:true,progress:0.64)
        precondition(config.render(fields:[ring],fallback:nil).tiffRepresentation != nil)
        print("PASS 9 menu customization checks; no preferences changed")
    }
}
