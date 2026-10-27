import Foundation
import CoreLocation

extension WeatherCity {
    static func placemark(_ place:CLPlacemark,coordinate:CLLocationCoordinate2D?=nil)->WeatherCity? {
        guard let point=coordinate ?? place.location?.coordinate,CLLocationCoordinate2DIsValid(point) else{return nil}
        // Weather is a regional grid. Keep only roughly kilometre-level coordinates.
        let lat=(point.latitude*100).rounded()/100,lon=(point.longitude*100).rounded()/100
        let district=place.subLocality ?? place.subAdministrativeArea ?? place.locality ?? place.administrativeArea ?? "当前位置"
        let region=[place.administrativeArea,place.locality].compactMap{$0}.reduce(into:[String]()) {a,b in if !a.contains(b) && b != district {a.append(b)}}.joined(separator:" · ")
        return WeatherCity(id:Int((lat+90)*100)*36001+Int((lon+180)*100),name:district,latitude:lat,longitude:lon,admin1:region.isEmpty ? nil:region,country:place.country)
    }
    static func searchDistrict(_ query:String) async->[WeatherCity] {
        let coder=CLGeocoder()
        let timeout=Task {try? await Task.sleep(for:.seconds(15));if !Task.isCancelled {coder.cancelGeocode()}}
        defer {timeout.cancel()}
        guard let places=try? await coder.geocodeAddressString(query,in:nil,preferredLocale:Locale(identifier:"zh_CN")) else{return []}
        return places.compactMap{placemark($0)}
    }
}
@MainActor final class CalendarWeatherLocation:NSObject,@preconcurrency CLLocationManagerDelegate {
    private let manager=CLLocationManager()
    private let geocoder=CLGeocoder()
    private var completion:((WeatherCity?,String)->Void)?
    private var timeout:Task<Void,Never>?
    private var resolving=false
    private var generation=UUID()
    override init() {super.init();manager.delegate=self;manager.desiredAccuracy=kCLLocationAccuracyKilometer}
    func request(allowPrompt:Bool,completion:@escaping(WeatherCity?,String)->Void) {
        cancel();self.completion=completion
        timeout=Task {[weak self] in try? await Task.sleep(for:.seconds(25));guard !Task.isCancelled else{return};self?.finish(nil,"定位暂未完成，可重试或手动选择区县")}
        switch manager.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:manager.requestLocation()
        case .notDetermined:
            if allowPrompt {manager.requestWhenInUseAuthorization()} else {finish(nil,"点击“使用当前位置”以允许系统定位")}
        default:finish(nil,"定位未获允许，可在系统设置中开启，或手动选择区县")
        }
    }
    func cancel() {generation=UUID();timeout?.cancel();timeout=nil;manager.stopUpdatingLocation();geocoder.cancelGeocode();completion=nil;resolving=false}
    private func finish(_ city:WeatherCity?,_ note:String) {
        let callback=completion;cancel();callback?(city,note)
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        guard completion != nil else{return}
        switch manager.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:manager.requestLocation()
        case .restricted,.denied:finish(nil,"定位未获允许，可手动选择区县")
        default:break
        }
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) {finish(nil,"系统暂时无法定位，可重试或手动选择区县")}
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard !resolving,completion != nil,let point=locations.last,point.horizontalAccuracy>=0,abs(point.timestamp.timeIntervalSinceNow)<300 else{return}
        resolving=true;let request=generation
        Task {
            let places=try? await geocoder.reverseGeocodeLocation(point,preferredLocale:Locale(identifier:"zh_CN"))
            guard completion != nil,generation==request else{return}
            if let place=places?.first,let city=WeatherCity.placemark(place,coordinate:point.coordinate) {finish(city,"")}
            else {
                let lat=(point.coordinate.latitude*100).rounded()/100,lon=(point.coordinate.longitude*100).rounded()/100
                finish(WeatherCity(id:0,name:"当前位置",latitude:lat,longitude:lon,admin1:nil,country:nil),"区县名称暂不可用，使用当前位置天气")
            }
        }
    }
}
