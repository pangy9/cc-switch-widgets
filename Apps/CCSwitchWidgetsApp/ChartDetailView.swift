#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import Charts
import SwiftUI

enum AppChartKind: String, CaseIterable, Identifiable {
    case apps
    case models

    var id: String { rawValue }
    var label: String { self == .apps ? "按应用" : "按模型" }
}

struct ChartDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: UsageSnapshot
    @Binding var range: ChartRange
    @Binding var kind: AppChartKind
    let themeMode: ThemeMode
    var customPalette: [UInt32] = CustomPalette.defaultHexes

    @State private var selectedBucket: DailyUsage?

    private var buckets: [DailyUsage] { snapshot.buckets(for: range) }
    private var average: Double {
        guard !buckets.isEmpty else { return 0 }
        return Double(buckets.reduce(Int64(0)) { $0 + $1.totalTokens }) / Double(buckets.count)
    }
    private var surface: AppSurface { AppSurface(mode: themeMode, palette: customPalette, colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("用量趋势")
                        .font(.headline)
                    Text("将鼠标移到柱或折线位置查看对应数值")
                        .font(.caption)
                        .foregroundStyle(surface.secondaryText)
                }
                Spacer()
                Picker("分组", selection: $kind) {
                    ForEach(AppChartKind.allCases) { item in Text(item.label).tag(item) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Picker("范围", selection: $range) {
                    Text("当天").tag(ChartRange.today)
                    Text("7 日").tag(ChartRange.sevenDays)
                    Text("30 日").tag(ChartRange.thirtyDays)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            Chart {
                ForEach(buckets) { bucket in
                    ForEach(segments(in: bucket), id: \.key) { segment in
                        BarMark(
                            x: .value("时间", bucket.date, unit: range == .today ? .hour : .day),
                            y: .value("Token", segment.value),
                            stacking: .standard
                        )
                        .foregroundStyle(seriesColor(for: segment.key))
                    }
                    LineMark(
                        x: .value("时间", bucket.date, unit: range == .today ? .hour : .day),
                        y: .value("总 Token", bucket.totalTokens)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(surface.primaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                RuleMark(y: .value("均值", average))
                    .foregroundStyle(surface.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                if let selectedBucket {
                    RuleMark(x: .value("选中", selectedBucket.date))
                        .foregroundStyle(surface.primaryText.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .thirtyDays ? 8 : 7)) { _ in
                    AxisGridLine().foregroundStyle(surface.secondaryText.opacity(0.18))
                    AxisValueLabel(format: range == .today ? .dateTime.hour() : .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(surface.secondaryText.opacity(0.18))
                    AxisValueLabel()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                guard let frameAnchor = proxy.plotFrame else { return }
                                let frame = geometry[frameAnchor]
                                guard frame.contains(location),
                                      let date: Date = proxy.value(atX: location.x - frame.minX) else {
                                    selectedBucket = nil
                                    return
                                }
                                selectedBucket = buckets.min {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                }
                            case .ended:
                                selectedBucket = nil
                            }
                        }
                }
            }
            .frame(height: 250)

            if let selectedBucket {
                HStack(spacing: 18) {
                    Text(bucketLabel(selectedBucket.date))
                        .font(.subheadline.weight(.semibold))
                    Text("总计 \(formattedToken(selectedBucket.totalTokens))")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(segments(in: selectedBucket).prefix(4)), id: \.key) { segment in
                        HStack(spacing: 5) {
                            Circle().fill(seriesColor(for: segment.key)).frame(width: 7, height: 7)
                            Text("\(segment.key) \(formattedToken(segment.value))")
                        }
                        .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(surface.background.opacity(surface.isDark ? 0.55 : 0.8))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Text("悬停图表以查看时间、总量和分项")
                    .font(.caption)
                    .foregroundStyle(surface.secondaryText)
                    .frame(height: 32)
            }
        }
    }

    private func segments(in bucket: DailyUsage) -> [(key: String, value: Int64)] {
        let values = kind == .apps ? bucket.appTokens : (bucket.modelTokens ?? [:])
        return values.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
    }

    private var allSeriesKeys: [String] {
        let keys = buckets.flatMap { bucket -> [String] in
            kind == .apps ? Array(bucket.appTokens.keys) : Array((bucket.modelTokens ?? [:]).keys)
        }
        return Array(Set(keys)).sorted()
    }

    private func seriesColor(for key: String) -> Color {
        let colors = surface.chartColors
        let index = allSeriesKeys.firstIndex(of: key) ?? 0
        return colors[index % colors.count]
    }

    private func bucketLabel(_ date: Date) -> String {
        range == .today
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.month().day())
    }
}
