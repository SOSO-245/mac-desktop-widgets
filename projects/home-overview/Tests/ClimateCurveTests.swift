import Foundation

@main
enum ClimateCurveTests {
    static func main() {
        let example = ClimateHistoryPoint.example
        precondition(example.count == 25)
        precondition(example.last?.temperature == 25.6 && example.last?.humidity == 55)

        let missing = [
            ClimateHistoryPoint(hour: 0, temperature: 20, humidity: 40),
            ClimateHistoryPoint(hour: 1, temperature: nil, humidity: 42),
            ClimateHistoryPoint(hour: 2, temperature: 22, humidity: 44),
            ClimateHistoryPoint(hour: 3, temperature: 23, humidity: 45),
            ClimateHistoryPoint(hour: 7, temperature: 24, humidity: 46)
        ]
        let runs = ClimateCurve.runs(missing, value: { $0.temperature })
        precondition(runs.map(\.count) == [1, 2, 1], "Missing and absent samples must both break lines")
        precondition(ClimateCurve.runs(missing, value: { $0.humidity }).map(\.count) == [4, 1], "A missing temperature must not erase humidity")

        let invalid = [
            ClimateHistoryPoint(hour: 0, temperature: 20, humidity: nil),
            ClimateHistoryPoint(hour: 1, temperature: .infinity, humidity: nil),
            ClimateHistoryPoint(hour: 2, temperature: 21, humidity: nil)
        ]
        precondition(ClimateCurve.runs(invalid, value: { $0.temperature }).map(\.count) == [1, 1])

        // The chart summarizes actual samples, not a regular grid of invented
        // readings. Means use sample timestamps and retain the real endpoints.
        let uneven: [ClimateCurve.Sample] = [
            .init(x: 0, y: 0), .init(x: 0.1, y: 10), .init(x: 0.4, y: 20),
            .init(x: 0.6, y: 30), .init(x: 0.8, y: 40), .init(x: 1, y: 50)
        ]
        let means = ClimateCurve.averaged(uneven)
        precondition(means.count == 4)
        precondition(means.first == uneven.first && means.last == uneven.last)
        precondition(abs(means[1].x - 1.0 / 6) < 1e-9 && means[1].y == 10)
        precondition(abs(means[2].x - 0.7) < 1e-9 && means[2].y == 35)
        precondition(ClimateCurve.averaged(Array(uneven.prefix(2))) == Array(uneven.prefix(2)))
        precondition(ClimateCurve.averaged(uneven, intervalHours: 0) == uneven)

        let interrupted = [
            ClimateHistoryPoint(hour: 0, temperature: 20, humidity: 40),
            ClimateHistoryPoint(hour: 0.1, temperature: 22, humidity: 42),
            ClimateHistoryPoint(hour: 0.2, temperature: nil, humidity: 43),
            ClimateHistoryPoint(hour: 0.3, temperature: 30, humidity: 44),
            ClimateHistoryPoint(hour: 0.4, temperature: 32, humidity: 45),
            ClimateHistoryPoint(hour: 0.45, temperature: 34, humidity: 46),
            ClimateHistoryPoint(hour: 4, temperature: 35, humidity: 47)
        ]
        let interruptedTrend = ClimateCurve.trendRuns(interrupted, value: { $0.temperature })
        precondition(interruptedTrend.count == 1, "The requested continuous trend must connect across missing samples and long gaps")
        precondition(interruptedTrend[0].allSatisfy { (20 ... 35).contains($0.y) })
        precondition(interruptedTrend[0].first == .init(x: 0, y: 20) && interruptedTrend[0].last == .init(x: 4, y: 35))
        precondition(ClimateCurve.trendRuns(interrupted, value: { $0.humidity }).count == 1)

        let absent = [
            ClimateHistoryPoint(hour: 0, temperature: nil, humidity: nil),
            ClimateHistoryPoint(hour: 4, temperature: .nan, humidity: nil),
            ClimateHistoryPoint(hour: 12, temperature: nil, humidity: nil)
        ]
        precondition(ClimateCurve.trendRuns(absent, value: { $0.temperature }).isEmpty)
        precondition(ClimateCurve.trendRuns([], value: { $0.temperature }).isEmpty)
        let single = absent + [ClimateHistoryPoint(hour: 6, temperature: 24, humidity: nil)]
        precondition(ClimateCurve.trendRuns(single, value: { $0.temperature }) == [[.init(x: 6, y: 24)]],
                     "One real sample remains one point, not an invented line")
        let distant = [ClimateHistoryPoint(hour: 2, temperature: 20, humidity: nil),
                       ClimateHistoryPoint(hour: 6, temperature: nil, humidity: nil),
                       ClimateHistoryPoint(hour: 20, temperature: 26, humidity: nil)]
        let connected = ClimateCurve.trendRuns(distant, value: { $0.temperature })
        precondition(connected == [[.init(x: 2, y: 20), .init(x: 20, y: 26)]],
                     "Empty periods may interpolate but must not create samples or extend beyond the real endpoints")
        let bridge = ClimateCurve.cubics(connected[0])
        precondition(bridge.count == 1 && abs(bridge[0].value(at: 0.5) - 23) < 1e-9)

        let staggered = [
            ClimateHistoryPoint(hour: 0, temperature: 20, humidity: nil, hasHumiditySample: false),
            ClimateHistoryPoint(hour: 0.1, temperature: nil, humidity: 40, hasTemperatureSample: false),
            ClimateHistoryPoint(hour: 0.2, temperature: 21, humidity: nil, hasHumiditySample: false),
            ClimateHistoryPoint(hour: 0.3, temperature: nil, humidity: 41, hasTemperatureSample: false),
            ClimateHistoryPoint(hour: 0.4, temperature: nil, humidity: nil, hasHumiditySample: false),
            ClimateHistoryPoint(hour: 0.5, temperature: 22, humidity: nil, hasHumiditySample: false)
        ]
        precondition(ClimateCurve.trendRuns(staggered.filter(\.hasTemperatureSample), value: { $0.temperature }).count == 1)
        precondition(ClimateCurve.trendRuns(staggered.filter(\.hasHumiditySample), value: { $0.humidity }).count == 1,
                     "Another metric's sample must not enter its mean")

        let noisy = (0 ... 960).map { index in
            ClimateCurve.Sample(x: Double(index) / 40,
                                y: 24 + sin(Double(index) / 160) + (index.isMultiple(of: 2) ? 0.35 : -0.35))
        }
        let smooth = ClimateCurve.averaged(noisy)
        precondition(smooth.count <= 51, "A 24-hour mini chart should contain about 48 averaged buckets")
        precondition(smooth.first == noisy.first && smooth.last == noisy.last)
        let rawVariation = zip(noisy, noisy.dropFirst()).reduce(0.0) { $0 + abs($1.1.y - $1.0.y) }
        let trendVariation = zip(smooth, smooth.dropFirst()).reduce(0.0) { $0 + abs($1.1.y - $1.0.y) }
        precondition(trendVariation < rawVariation / 10, "High-frequency jitter should be summarized into a readable trend")
        let shifted = ClimateCurve.averaged(noisy.map { .init(x: $0.x - 0.01, y: $0.y) })
        precondition(zip(smooth, shifted).allSatisfy { abs($0.y - $1.y) < 1e-9 },
                     "Moving the visible window must not change averaging bucket membership")

        // Peaks, troughs, plateaus and uneven spacing remain within each pair's
        // measured range throughout the interpolation, not merely at endpoints.
        let values = [21.0, 24, 22, 22, 22.1, 18, 26, 25.6]
        let hours = [0.0, 0.3, 1, 2, 2.1, 4, 4.5, 6]
        let samples = zip(hours, values).map { ClimateCurve.Sample(x: $0.0, y: $0.1) }
        for cubic in ClimateCurve.cubics(samples) {
            let lower = min(cubic.start.y, cubic.end.y) - 1e-9
            let upper = max(cubic.start.y, cubic.end.y) + 1e-9
            for step in 0 ... 100 {
                precondition((lower ... upper).contains(cubic.value(at: Double(step) / 100)), "Curve introduced an unmeasured extremum")
            }
        }
        // The smoothed trend, including a sudden jump, must never overshoot the
        // measured/averaged segment bounds or move the endpoints.
        let jump = (0 ... 240).map { index in
            ClimateCurve.Sample(x: Double(index) / 20, y: index < 120 ? 20 : 30)
        }
        for trend in [smooth, ClimateCurve.averaged(jump), interruptedTrend[0], connected[0]] {
            let curves = ClimateCurve.cubics(trend)
            precondition(curves.first?.start == trend.first && curves.last?.end == trend.last)
            for cubic in curves {
                let range = (min(cubic.start.y, cubic.end.y) - 1e-9) ... (max(cubic.start.y, cubic.end.y) + 1e-9)
                for step in 0 ... 100 {
                    precondition(range.contains(cubic.value(at: Double(step) / 100)), "Smoothed curve overshot a real or averaged bound")
                }
            }
        }
        let linear = ClimateCurve.cubics([.init(x: 0, y: 20), .init(x: 1, y: 24)])
        precondition(linear.count == 1 && abs(linear[0].value(at: 0.5) - 22) < 1e-9)
        precondition(ClimateCurve.cubics([.init(x: 0, y: 20)]).isEmpty)
        print("Climate trend: half-hour real-sample means, continuous gap interpolation, no endpoint extrapolation, empty/single-point histories, independent metrics, and no-overshoot smoothing passed.")
    }
}
