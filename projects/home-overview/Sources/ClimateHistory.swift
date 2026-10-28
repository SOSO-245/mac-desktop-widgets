import Foundation

struct ClimateHistoryPoint {
    /// Hours from the start of the visible 24-hour window, in ascending order.
    let hour: Double
    let temperature: Double?
    let humidity: Double?
    var hasTemperatureSample: Bool = true
    var hasHumiditySample: Bool = true

    #if CLIMATE_CURVE_TESTING
    /// Numeric fixtures for interpolation regression tests only.
    static var example: [ClimateHistoryPoint] {
        let temperature: [Double] = [
            25.2, 25.0, 24.8, 24.7, 24.5, 24.3, 24.2, 24.1, 24.2,
            24.5, 24.8, 25.1, 25.3, 25.5, 25.8, 26.0, 26.1, 26.0,
            25.8, 25.7, 25.5, 25.4, 25.5, 25.7, 25.6
        ]
        let humidity: [Double] = [
            54, 55, 56, 56, 57, 58, 59, 60, 59, 58, 57, 56, 55,
            54, 52, 51, 50, 51, 52, 53, 54, 55, 56, 56, 55
        ]
        return temperature.indices.map {
            ClimateHistoryPoint(hour: Double($0), temperature: temperature[$0], humidity: humidity[$0])
        }
    }
    #endif
}

/// Pure numeric shape-preserving interpolation, shared by rendering and tests.
enum ClimateCurve {
    struct Sample: Equatable {
        let x: Double
        let y: Double
    }

    struct Cubic {
        let start: Sample
        let control1: Sample
        let control2: Sample
        let end: Sample

        func value(at fraction: Double) -> Double {
            let t = min(max(fraction, 0), 1)
            let u = 1 - t
            return u * u * u * start.y + 3 * u * u * t * control1.y
                + 3 * u * t * t * control2.y + t * t * t * end.y
        }
    }

    /// HA records state changes rather than a guaranteed periodic sample stream.
    /// Explicit missing values always break a run. A long silent gap is also
    /// left blank conservatively, without claiming that the device was offline.
    static func runs(
        _ points: [ClimateHistoryPoint],
        value: (ClimateHistoryPoint) -> Double?,
        maximumGapHours: Double = 1.5
    ) -> [[Sample]] {
        var result: [[Sample]] = []
        var run: [Sample] = []
        func finish() {
            if !run.isEmpty { result.append(run) }
            run.removeAll(keepingCapacity: true)
        }
        for point in points {
            guard point.hour.isFinite, let reading = value(point), reading.isFinite,
                  (0 ... 24).contains(point.hour) else {
                finish()
                continue
            }
            if let previous = run.last,
               point.hour <= previous.x || point.hour - previous.x > maximumGapHours {
                finish()
            }
            run.append(Sample(x: point.hour, y: reading))
        }
        finish()
        return result
    }

    /// The overview intentionally shows one continuous trend. Average only
    /// actual valid samples, then interpolate between them across empty periods.
    /// No samples are invented, and the first/last readings bound the line.
    static func trendRuns(
        _ points: [ClimateHistoryPoint],
        value: (ClimateHistoryPoint) -> Double?,
        averagingHours: Double = 0.5
    ) -> [[Sample]] {
        var samples: [Sample] = []
        for point in points.filter({ $0.hour.isFinite }).sorted(by: { $0.hour < $1.hour }) {
            guard point.hour.isFinite, (0 ... 24).contains(point.hour),
                  let reading = value(point), reading.isFinite else { continue }
            let sample = Sample(x: point.hour, y: reading)
            if samples.last?.x == sample.x {
                samples[samples.count - 1] = sample
            } else {
                samples.append(sample)
            }
        }
        return samples.isEmpty ? [] : [averaged(samples, intervalHours: averagingHours)]
    }

    static func averaged(_ samples: [Sample], intervalHours: Double = 0.5) -> [Sample] {
        guard samples.count > 2, intervalHours.isFinite, intervalHours > 0,
              let first = samples.first, let last = samples.last else { return samples }
        var result = [first]
        var bucket: Int?
        var sumX = 0.0, sumY = 0.0
        var count = 0
        func finishBucket() {
            guard count > 0 else { return }
            let sample = Sample(x: sumX / Double(count), y: sumY / Double(count))
            // Keep each run's actual start/end readings, but do not duplicate a
            // mean whose timestamp is already one of those endpoint samples.
            if sample.x > first.x, sample.x < last.x { result.append(sample) }
            sumX = 0; sumY = 0; count = 0
        }
        for sample in samples {
            // Anchoring to the first real sample keeps bucket membership stable
            // while the visible 24-hour window advances between refreshes.
            let nextBucket = Int(floor((sample.x - first.x) / intervalHours))
            if nextBucket != bucket { finishBucket(); bucket = nextBucket }
            sumX += sample.x; sumY += sample.y; count += 1
        }
        finishBucket()
        result.append(last)
        return result
    }

    /// PCHIP tangents preserve local extrema instead of the overshoot that a
    /// generic Catmull-Rom spline can add to sensor data.
    static func cubics(_ samples: [Sample]) -> [Cubic] {
        guard samples.count >= 2 else { return [] }
        let h = zip(samples, samples.dropFirst()).map { $1.x - $0.x }
        guard h.allSatisfy({ $0 > 0 && $0.isFinite }) else { return [] }
        let slope = zip(samples, samples.dropFirst()).enumerated().map {
            ($0.element.1.y - $0.element.0.y) / h[$0.offset]
        }
        var tangent = Array(repeating: 0.0, count: samples.count)
        if samples.count == 2 {
            tangent = [slope[0], slope[0]]
        } else {
            for index in 1 ..< samples.count - 1 {
                let before = slope[index - 1]
                let after = slope[index]
                if before == 0 || after == 0 || before.sign != after.sign {
                    tangent[index] = 0
                } else {
                    let firstWeight = 2 * h[index] + h[index - 1]
                    let secondWeight = h[index] + 2 * h[index - 1]
                    tangent[index] = (firstWeight + secondWeight)
                        / (firstWeight / before + secondWeight / after)
                }
            }
            tangent[0] = endpointTangent(h[0], h[1], slope[0], slope[1])
            let last = slope.count - 1
            tangent[samples.count - 1] = endpointTangent(h[last], h[last - 1], slope[last], slope[last - 1])
        }
        return (0 ..< samples.count - 1).map { index in
            let a = samples[index]
            let b = samples[index + 1]
            let low = min(a.y, b.y)
            let high = max(a.y, b.y)
            let width = h[index] / 3
            // Control ordinates stay within each segment's sample range.
            // A cubic Bezier stays inside that convex hull by construction.
            let c1 = min(max(a.y + tangent[index] * width, low), high)
            let c2 = min(max(b.y - tangent[index + 1] * width, low), high)
            return Cubic(start: a,
                         control1: Sample(x: a.x + width, y: c1),
                         control2: Sample(x: b.x - width, y: c2),
                         end: b)
        }
    }

    private static func endpointTangent(_ h0: Double, _ h1: Double, _ d0: Double, _ d1: Double) -> Double {
        let estimate = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if estimate.sign != d0.sign || d0 == 0 { return 0 }
        if d0.sign != d1.sign && abs(estimate) > abs(3 * d0) { return 3 * d0 }
        return estimate
    }
}

#if !CLIMATE_CURVE_TESTING
import SwiftUI

struct ClimateHistoryChart: View {
    let points: [ClimateHistoryPoint]
    let isStale: Bool
    let caption: String

    private var temperatureRuns: [[ClimateCurve.Sample]] {
        ClimateCurve.trendRuns(points.filter(\.hasTemperatureSample), value: { $0.temperature })
    }
    private var humidityRuns: [[ClimateCurve.Sample]] {
        ClimateCurve.trendRuns(points.filter(\.hasHumiditySample), value: {
            guard let value = $0.humidity, (0 ... 100).contains(value) else { return nil }
            return value
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(temperatureRuns.isEmpty && humidityRuns.isEmpty
                 ? caption : "近24小时")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AtlasStyle.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            if temperatureRuns.isEmpty && humidityRuns.isEmpty {
                Text("暂无有效历史读数")
                    .font(.system(size: 16))
                    .foregroundStyle(AtlasStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 26) {
                    ClimateMiniChart(title: "温度", unit: "°C", color: AtlasStyle.mint,
                                     runs: temperatureRuns, minimumSpan: 2)
                    ClimateMiniChart(title: "湿度", unit: "%", color: AtlasStyle.blue,
                                     runs: humidityRuns, minimumSpan: 10)
                }
            }
        }.frame(height: 140)
    }
}

private struct ClimateMiniChart: View {
    let title: String
    let unit: String
    let color: Color
    let runs: [[ClimateCurve.Sample]]
    let minimumSpan: Double

    private var samples: [ClimateCurve.Sample] { runs.flatMap { $0 } }
    private var rangeLabel: String {
        guard let low = samples.map(\.y).min(), let high = samples.map(\.y).max() else { return "—" }
        let decimals = unit == "°C" ? 1 : 0
        return String(format: "%.*f–%.*f %@", decimals, low, decimals, high, unit)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title + " " + unit).foregroundStyle(color)
                Spacer(minLength: 4)
                Text(rangeLabel).foregroundStyle(AtlasStyle.secondary)
            }.font(.system(size: 14, weight: .medium)).lineLimit(1)
            if samples.isEmpty {
                Text("暂无有效读数").font(.system(size: 14)).foregroundStyle(AtlasStyle.secondary)
                    .frame(maxWidth: .infinity).frame(height: 70)
            } else {
                Canvas { context, size in
                    let rawLow = samples.map(\.y).min() ?? 0
                    let rawHigh = samples.map(\.y).max() ?? 1
                    let span = max(rawHigh - rawLow, minimumSpan)
                    let midpoint = (rawHigh + rawLow) / 2
                    let low = midpoint - span * 0.65
                    let high = midpoint + span * 0.65
                    func position(_ sample: ClimateCurve.Sample) -> CGPoint {
                        CGPoint(x: CGFloat(sample.x / 24) * size.width,
                                y: 4 + CGFloat(1 - (sample.y - low) / (high - low)) * (size.height - 8))
                    }
                    var grid = Path()
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = 4 + (size.height - 8) * fraction
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    for run in runs {
                        guard let first = run.first, let last = run.last else { continue }
                        var line = Path()
                        line.move(to: position(first))
                        for curve in ClimateCurve.cubics(run) {
                            line.addCurve(to: position(curve.end), control1: position(curve.control1), control2: position(curve.control2))
                        }
                        if run.count > 1 {
                            var area = line
                            area.addLine(to: CGPoint(x: position(last).x, y: size.height))
                            area.addLine(to: CGPoint(x: position(first).x, y: size.height))
                            area.closeSubpath()
                            context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.15), color.opacity(0.005)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        let end = position(last)
                        context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .color(color))
                    }
                }.frame(height: 70)
            }
            HStack {
                Text("24h 前")
                Spacer()
                Text("12h 前")
                Spacer()
                Text("现在")
            }.font(.system(size: 14)).foregroundStyle(AtlasStyle.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，近二十四小时历史的三十分钟采样均值，范围 \(rangeLabel)，缺测时段为平滑插值，不外推首尾")
    }
}
#endif
