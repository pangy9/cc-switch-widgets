import Charts
import SwiftUI

public enum UsageNoticeDateFormatter {
    public static func string(
        from date: Date,
        range: ChartRange,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = range == .today ? "HH:mm" : "M月d日"
        return formatter.string(from: date)
    }
}

public struct UsageNoticeMetrics: Equatable, Sendable {
    public let totalTokens: Int64
    public let requestCount: Int
    public let cacheHitRate: Double?
    public let costUSD: Double

    public init(totals: UsageTotals) {
        totalTokens = totals.totalTokens
        requestCount = totals.requestCount
        cacheHitRate = totals.cacheableTokens == 0 ? nil : totals.cacheHitRate
        costUSD = totals.costUSD
    }
}

public enum UsageNoticeHeadline {
    public static func text(dateText: String, totalTokens: Int64) -> String {
        "\(dateText) · 当天总消耗 \(usageTokens(totalTokens))"
    }
}

public struct UsageVisualizationPalette {
    public let primaryText: Color
    public let secondaryText: Color
    public let accent: Color
    public let series: [Color]
    public let separator: Color
    public let isDark: Bool

    public init(
        primaryText: Color,
        secondaryText: Color,
        accent: Color,
        series: [Color],
        separator: Color,
        isDark: Bool
    ) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.series = series
        self.separator = separator
        self.isDark = isDark
    }

    public func seriesColor(_ index: Int) -> Color {
        series.isEmpty ? accent : series[index % series.count]
    }

    public func heatmapColor(_ level: Int) -> Color {
        guard level > 0 else { return separator.opacity(isDark ? 0.34 : 0.46) }
        return accent.opacity([0.0, 0.32, 0.52, 0.74, 1.0][min(4, level)])
    }
}

public struct UsageMiniLineVisualization: View {
    public let buckets: [DailyUsage]
    public let seriesID: String
    public let scope: ModuleTrendScope
    public let range: ChartRange
    public let color: Color
    public let palette: UsageVisualizationPalette
    public let supportsHover: Bool
    @State private var hoveredIndex: Int?
    @State private var hoverLocation: CGPoint?

    public init(
        buckets: [DailyUsage], seriesID: String, scope: ModuleTrendScope, range: ChartRange,
        color: Color, palette: UsageVisualizationPalette, supportsHover: Bool
    ) {
        self.buckets = buckets
        self.seriesID = seriesID
        self.scope = scope
        self.range = range
        self.color = color
        self.palette = palette
        self.supportsHover = supportsHover
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Chart {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        AreaMark(x: .value("点", index), y: .value("Token", totals(in: bucket).totalTokens))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.42), color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("点", index), y: .value("Token", totals(in: bucket).totalTokens))
                            .interpolationMethod(.monotone).foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                    if !buckets.isEmpty {
                        RuleMark(y: .value("均值", Double(buckets.reduce(Int64(0)) { $0 + totals(in: $1).totalTokens }) / Double(buckets.count)))
                            .foregroundStyle(palette.primaryText.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
                    }
                    if let hoveredIndex, buckets.indices.contains(hoveredIndex) {
                        PointMark(
                            x: .value("选中", hoveredIndex),
                            y: .value("Token", totals(in: buckets[hoveredIndex]).totalTokens)
                        )
                        .foregroundStyle(color)
                        .symbolSize(34)
                    }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartXScale(domain: TrendAxisGeometry.domain(bucketCount: buckets.count))
                .chartOverlay { proxy in
                    if supportsHover {
                        GeometryReader { overlay in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        guard let anchor = proxy.plotFrame else { return }
                                        let frame = overlay[anchor]
                                        guard frame.contains(location), let x: Double = proxy.value(atX: location.x - frame.minX) else {
                                            hoveredIndex = nil; hoverLocation = nil; return
                                        }
                                        hoveredIndex = min(max(Int(x.rounded()), 0), max(0, buckets.count - 1))
                                        hoverLocation = location
                                    case .ended:
                                        hoveredIndex = nil; hoverLocation = nil
                                    }
                                }
                        }
                    }
                }

                if let index = hoveredIndex, buckets.indices.contains(index), let hoverLocation {
                    CompactUsageNoticeView(
                        title: UsageNoticeDateFormatter.string(from: buckets[index].date, range: range),
                        name: seriesID,
                        metrics: UsageNoticeMetrics(totals: totals(in: buckets[index])),
                        color: color,
                        palette: palette
                    )
                    .fixedSize()
                    .position(x: min(max(hoverLocation.x, 68), max(68, geometry.size.width - 68)), y: -34)
                    .allowsHitTesting(false)
                    .zIndex(20)
                }
            }
        }
    }

    private func totals(in bucket: DailyUsage) -> UsageTotals {
        scope == .byModel ? bucket.modelUsage[seriesID] ?? UsageTotals() : bucket.appUsage[seriesID] ?? UsageTotals()
    }
}

private struct CompactUsageNoticeView: View {
    let title: String
    let name: String
    let metrics: UsageNoticeMetrics
    let color: Color
    let palette: UsageVisualizationPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).lineLimit(1)
                Spacer(minLength: 4)
                Text(title).foregroundStyle(palette.secondaryText)
            }
            HStack(spacing: 8) {
                Text(usageTokens(metrics.totalTokens))
                Text("\(metrics.requestCount) 请求")
            }
            HStack(spacing: 8) {
                Text(metrics.cacheHitRate.map { "命中 " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "命中 —")
                Text(metrics.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))))
            }
        }
        .frame(width: 124, alignment: .leading)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.primaryText)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.isDark ? Color.black.opacity(0.92) : Color.white.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.separator))
        .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
    }
}

private struct UsageNoticeView: View {
    let title: String
    let rows: [(String, UsageNoticeMetrics, Color)]
    let palette: UsageVisualizationPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.bold)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    Circle().fill(row.2).frame(width: 7, height: 7)
                    Text(row.0).lineLimit(1)
                    Text("\(usageTokens(row.1.totalTokens)) · \(row.1.requestCount) 请求")
                    Text(row.1.cacheHitRate.map { "命中 " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "命中 —")
                    Text(row.1.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                }
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(palette.primaryText)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.isDark ? Color.black.opacity(0.9) : Color.white.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.separator))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

public struct UsageTrendVisualization: View {
    public let buckets: [DailyUsage]
    public let projection: UsageRangeProjection
    public let scope: ModuleTrendScope
    public let style: ModuleTrendStyle
    public let palette: UsageVisualizationPalette
    public let supportsHover: Bool
    public let showsLegend: Bool
    public let selectedModelIDs: [String]
    public let selectedModelsInitialized: Bool
    @State private var hoveredIndex: Int?
    @State private var hoverLocation: CGPoint?
    @State private var hoveredLegendID: String?

    public init(
        buckets: [DailyUsage],
        projection: UsageRangeProjection,
        scope: ModuleTrendScope,
        style: ModuleTrendStyle,
        palette: UsageVisualizationPalette,
        supportsHover: Bool = true,
        showsLegend: Bool = true,
        selectedModelIDs: [String] = [],
        selectedModelsInitialized: Bool = false
    ) {
        self.buckets = buckets
        self.projection = projection
        self.scope = scope
        self.style = style
        self.palette = palette
        self.supportsHover = supportsHover
        self.showsLegend = showsLegend
        self.selectedModelIDs = selectedModelIDs
        self.selectedModelsInitialized = selectedModelsInitialized
    }

    public var body: some View {
        GeometryReader { geometry in
            let seriesIDs = scope == .byModel
                ? TrendModelSelection.visible(
                    savedIDs: selectedModelIDs,
                    availableIDs: projection.models.map(\.id),
                    isInitialized: selectedModelsInitialized
                )
                : projection.apps.map(\.id)
            let axisLayout = TrendAxisLayout(bucketCount: buckets.count, range: projection.range)
            let barWidth = TrendBarLayout.width(
                availableWidth: max(1, geometry.size.width - 12),
                bucketCount: buckets.count
            )
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                Chart {
                    marks(seriesIDs: seriesIDs, barWidth: barWidth)
                    if !buckets.isEmpty {
                        RuleMark(y: .value("均值", Double(projection.totals.totalTokens) / Double(buckets.count)))
                            .foregroundStyle(palette.secondaryText.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let hoveredIndex, buckets.indices.contains(hoveredIndex) {
                        RuleMark(x: .value("选中", hoveredIndex))
                            .foregroundStyle(palette.primaryText.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXAxis {
                    let halfStep = Double(projection.range.axisStep(bucketCount: buckets.count)) / 2
                    let labelMarks: [Double] = {
                        var marks = axisLayout.labelIndices.map { Double($0) - halfStep }
                        if let last = axisLayout.labelIndices.last { marks.append(Double(last) + halfStep) }
                        return marks
                    }()
                    AxisMarks(values: axisLayout.labelIndices) { _ in
                        AxisGridLine().foregroundStyle(palette.separator.opacity(0.7))
                        AxisTick().foregroundStyle(palette.separator.opacity(0.7))
                    }
                    AxisMarks(values: labelMarks) { value in
                        AxisValueLabel(centered: true) {
                            if let shifted = value.as(Double.self) {
                                let index = Int((shifted + halfStep).rounded())
                                if buckets.indices.contains(index) {
                                    Text(usageAxisLabel(buckets[index].date, range: projection.range))
                                }
                            }
                        }
                        .font(.system(size: axisLayout.xAxisFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(palette.separator.opacity(0.7))
                        AxisValueLabel()
                            .font(.system(size: axisLayout.yAxisFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .chartXScale(domain: -1 ... Double(max(1, buckets.count)))
                .chartOverlay { proxy in
                    if supportsHover {
                        GeometryReader { overlayGeometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        guard let frameAnchor = proxy.plotFrame else { return }
                                        let frame = overlayGeometry[frameAnchor]
                                        guard frame.contains(location),
                                              let x: Double = proxy.value(atX: location.x - frame.minX),
                                              let index = axisLayout.nearestBucket(for: x) else {
                                            hoveredIndex = nil
                                            return
                                        }
                                        hoveredIndex = index
                                        hoverLocation = location
                                    case .ended:
                                        hoveredIndex = nil
                                        hoverLocation = nil
                                    }
                                }
                        }
                    }
                }

                if showsLegend { legend(seriesIDs: seriesIDs) }
                }
                if let hoveredIndex,
                   buckets.indices.contains(hoveredIndex),
                   let hoverLocation {
                    trendNotice(bucket: buckets[hoveredIndex], seriesIDs: seriesIDs)
                        .fixedSize()
                        .position(noticePosition(near: hoverLocation, in: geometry.size))
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
                if let hoveredLegendID {
                    legendNotice(id: hoveredLegendID)
                        .fixedSize()
                        .position(x: max(120, geometry.size.width - 120), y: max(48, geometry.size.height - 72))
                        .allowsHitTesting(false)
                        .zIndex(12)
                }
            }
        }
    }

    @ChartContentBuilder
    private func marks(seriesIDs: [String], barWidth: CGFloat) -> some ChartContent {
        if scope == .total && style == .stackedBars {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                BarMark(x: .value("日期", index), y: .value("Token", bucket.totalTokens), width: .fixed(barWidth))
                    .foregroundStyle(palette.accent)
            }
        } else if scope == .total {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                LineMark(x: .value("日期", index), y: .value("Token", bucket.totalTokens))
                    .foregroundStyle(palette.accent)
                    .interpolationMethod(.monotone)
            }
        } else if style == .stackedBars {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                ForEach(Array(seriesIDs.enumerated()), id: \.element) { seriesIndex, id in
                    BarMark(
                        x: .value("日期", index),
                        y: .value("Token", tokens(in: bucket, for: id)),
                        width: .fixed(barWidth),
                        stacking: .standard
                    )
                    .foregroundStyle(palette.seriesColor(seriesIndex))
                }
            }
        } else {
            ForEach(Array(seriesIDs.enumerated()), id: \.element) { seriesIndex, id in
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    LineMark(
                        x: .value("日期", index),
                        y: .value("Token", tokens(in: bucket, for: id)),
                        series: .value("系列", id)
                    )
                    .foregroundStyle(palette.seriesColor(seriesIndex))
                    .interpolationMethod(.monotone)
                }
            }
        }
    }

    @ViewBuilder
    private func legend(seriesIDs: [String]) -> some View {
        if scope == .total {
            HStack {
                legendItem(name: "总消耗量", color: palette.accent)
                    .onContinuousHover { phase in updateLegendHover(phase, id: "总消耗量") }
                Spacer(minLength: 0)
            }
        } else {
            let visible = Array(seriesIDs.prefix(TrendLegendLayout.visibleCount(seriesCount: seriesIDs.count)))
            let rows = TrendLegendLayout.rowCount(seriesCount: visible.count)
            let columns = max(1, Int(ceil(Double(visible.count) / Double(max(1, rows)))))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0 ..< rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row * columns ..< min((row + 1) * columns, visible.count), id: \.self) { index in
                            legendItem(name: visible[index], color: palette.seriesColor(index))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onContinuousHover { phase in updateLegendHover(phase, id: visible[index]) }
                        }
                        if row == rows - 1 {
                            let remaining = TrendLegendLayout.remainingCount(seriesCount: seriesIDs.count)
                            if remaining > 0 {
                                Text("另有 \(remaining) 个\(scope == .byModel ? "模型" : "工具")")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(palette.secondaryText)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateLegendHover(_ phase: HoverPhase, id: String) {
        guard supportsHover else { return }
        switch phase {
        case .active: hoveredLegendID = id
        case .ended:
            if hoveredLegendID == id { hoveredLegendID = nil }
        }
    }

    private func legendNotice(id: String) -> some View {
        let metrics: UsageNoticeMetrics
        let color: Color
        if scope == .total {
            metrics = UsageNoticeMetrics(totals: projection.totals)
            color = palette.accent
        } else {
            let summaries = scope == .byModel ? projection.models : projection.apps
            let summary = summaries.first { $0.id == id }
            metrics = UsageNoticeMetrics(totals: summary?.totals ?? UsageTotals())
            let index = summaries.firstIndex { $0.id == id } ?? 0
            color = palette.seriesColor(index)
        }
        return UsageNoticeView(
            title: projection.range.shortLabel,
            rows: [(id, metrics, color)],
            palette: palette
        )
    }

    private func tokens(in bucket: DailyUsage, for id: String) -> Int64 {
        seriesTotals(in: bucket, for: id).totalTokens
    }

    private func requests(in bucket: DailyUsage, for id: String) -> Int {
        seriesTotals(in: bucket, for: id).requestCount
    }

    private func seriesTotals(in bucket: DailyUsage, for id: String) -> UsageTotals {
        scope == .byModel ? bucket.modelUsage[id] ?? UsageTotals() : bucket.appUsage[id] ?? UsageTotals()
    }

    private func noticePosition(near point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x + 110, 120), size.width - 120), y: min(max(point.y - 54, 55), size.height - 55))
    }

    private func trendNotice(bucket: DailyUsage, seriesIDs: [String]) -> some View {
        let activeIDs = seriesIDs.filter { seriesTotals(in: bucket, for: $0).requestCount > 0 || seriesTotals(in: bucket, for: $0).totalTokens > 0 }
        let rows: [(String, UsageNoticeMetrics, Color)] = scope == .total
            ? [("总消耗量", UsageNoticeMetrics(totals: bucket.totals), palette.accent)]
            : activeIDs.enumerated().map { index, id in
                (id, UsageNoticeMetrics(totals: seriesTotals(in: bucket, for: id)), palette.seriesColor(index))
            }
        return UsageNoticeView(
            title: UsageNoticeHeadline.text(
                dateText: UsageNoticeDateFormatter.string(from: bucket.date, range: projection.range),
                totalTokens: bucket.totalTokens
            ),
            rows: rows,
            palette: palette
        )
    }

    private func legendItem(name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 7)
            Text(name).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.secondaryText)
    }
}

public struct UsageHeatmapVisualization: View {
    public let days: [DailyUsage]
    public let levels: [Int]
    public let palette: UsageVisualizationPalette
    public let supportsHover: Bool
    @State private var hoveredCoordinate: UsageHeatmapCoordinate?
    @State private var hoverLocation: CGPoint?
    @State private var noticeSize = CGSize(width: 240, height: 52)

    public init(
        days: [DailyUsage],
        levels: [Int],
        palette: UsageVisualizationPalette,
        supportsHover: Bool = true
    ) {
        self.days = days
        self.levels = levels
        self.palette = palette
        self.supportsHover = supportsHover
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = HeatmapCalendarLayout(days: days, calendar: .current)
            let levelsByDay = Dictionary(uniqueKeysWithValues: zip(days, levels).map {
                (Calendar.current.startOfDay(for: $0.0.date), $0.1)
            })
            let spacing: CGFloat = 3
            let weekdayGutter: CGFloat = 18
            let monthHeight: CGFloat = 12
            let footerHeight: CGFloat = 12
            let gridWidth = max(1, proxy.size.width - weekdayGutter)
            let horizontalCell = (gridWidth - CGFloat(max(0, layout.weekCount - 1)) * spacing) / CGFloat(max(1, layout.weekCount))
            let availableGridHeight = max(1, proxy.size.height - monthHeight - footerHeight - HeatmapGeometry.monthGridSpacing)
            let verticalCell = (availableGridHeight - 6 * spacing) / 7
            let cell = max(5, min(28, horizontalCell, verticalCell))
            let actualGridWidth = CGFloat(layout.weekCount) * cell + CGFloat(max(0, layout.weekCount - 1)) * spacing
            let gridLeading = max(weekdayGutter, (proxy.size.width - actualGridWidth + weekdayGutter) / 2)
            let hoveredDay = hoveredCoordinate.flatMap { layout.day(week: $0.week, weekday: $0.weekday) }

            VStack(alignment: .leading, spacing: HeatmapGeometry.monthGridSpacing) {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.monthMarkers, id: \.week) { marker in
                        Text(marker.label)
                            .fixedSize()
                            .position(
                                x: gridLeading
                                    + CGFloat(marker.week) * (cell + spacing)
                                    + cell / 2,
                                y: monthHeight / 2
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: monthHeight,
                    maxHeight: monthHeight,
                    alignment: .topLeading
                )
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText)

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .trailing, spacing: spacing) {
                        ForEach(Array(["一", "", "三", "", "五", "", "日"].enumerated()), id: \.offset) { _, label in
                            Text(label).frame(width: 13, height: cell, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .offset(x: gridLeading - weekdayGutter)

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0 ..< layout.weekCount, id: \.self) { week in
                            VStack(spacing: spacing) {
                                ForEach(0 ..< 7, id: \.self) { weekday in
                                    let coordinate = UsageHeatmapCoordinate(week: week, weekday: weekday)
                                    let state = layout.state(week: week, weekday: weekday)
                                    let day = layout.day(week: week, weekday: weekday)
                                    let level = day.map { levelsByDay[Calendar.current.startOfDay(for: $0.date)] ?? 0 } ?? 0
                                    let spotlight = spotlight(at: coordinate)
                                    RoundedRectangle(cornerRadius: max(1.5, cell * 0.2), style: .continuous)
                                        .fill({
                                            switch state {
                                            case .padding: palette.heatmapColor(0)
                                            case .data: palette.heatmapColor(level)
                                            case .future: Color.clear
                                            }
                                        }())
                                        .frame(width: cell, height: cell)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: max(1.5, cell * 0.2), style: .continuous)
                                                .fill(palette.primaryText.opacity(spotlight * 0.14))
                                        }
                                        .overlay {
                                            if hoveredCoordinate == coordinate {
                                                RoundedRectangle(cornerRadius: max(1.5, cell * 0.2), style: .continuous)
                                                    .stroke(palette.primaryText.opacity(0.92), lineWidth: 0.8)
                                            }
                                        }
                                        .scaleEffect(1 + spotlight * (hoveredCoordinate == coordinate ? 0.2 : 0.06))
                                        .shadow(color: palette.accent.opacity(spotlight * 0.7), radius: spotlight * 4)
                                        .onContinuousHover { phase in
                                            guard supportsHover, case .data = state else { return }
                                            switch phase {
                                            case let .active(location):
                                                hoveredCoordinate = coordinate
                                                hoverLocation = CGPoint(
                                                    x: gridLeading + CGFloat(week) * (cell + spacing) + location.x,
                                                    y: monthHeight + CGFloat(weekday) * (cell + spacing) + location.y
                                                )
                                            case .ended:
                                                hoveredCoordinate = nil
                                                hoverLocation = nil
                                            }
                                        }
                                        .help(day.map {
                                            "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \(usageTokens($0.totalTokens)) Token · \($0.totals.requestCount) 请求"
                                        } ?? "")
                                }
                            }
                        }
                    }
                    .offset(x: gridLeading)
                }

            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    Text("少")

                    ForEach(0 ... 4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.heatmapColor(level))
                            .frame(width: 10, height: 8)
                    }

                    Text("多")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .frame(height: footerHeight)
            }
            .overlay(alignment: .topLeading) {
                if let hoveredDay, let hoverLocation {
                    UsageNoticeView(
                        title: hoveredDay.date.formatted(.dateTime.year().month().day()),
                        rows: [("总计", UsageNoticeMetrics(totals: hoveredDay.totals), palette.accent)],
                        palette: palette
                    )
                    .fixedSize()
                    .background {
                        GeometryReader { noticeProxy in
                            Color.clear.preference(key: HeatmapNoticeSizePreferenceKey.self, value: noticeProxy.size)
                        }
                    }
                    .position(HeatmapGeometry.noticePosition(
                        hoverLocation: hoverLocation,
                        noticeSize: noticeSize,
                        canvasSize: proxy.size
                    ))
                    .allowsHitTesting(false)
                    .zIndex(100)
                }
            }
            .onPreferenceChange(HeatmapNoticeSizePreferenceKey.self) { size in
                if size.width > 0, size.height > 0 { noticeSize = size }
            }
        }
    }

    private func spotlight(at coordinate: UsageHeatmapCoordinate) -> Double {
        guard let hoveredCoordinate else { return 0 }
        let dx = Double(coordinate.week - hoveredCoordinate.week)
        let dy = Double(coordinate.weekday - hoveredCoordinate.weekday)
        return max(0, 1 - sqrt(dx * dx + dy * dy) / 5.2)
    }
}

private struct HeatmapNoticeSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize(width: 240, height: 52)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct UsageHeatmapCoordinate: Equatable {
    let week: Int
    let weekday: Int
}

private extension HoverPhase {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

private func usageTokens(_ value: Int64) -> String {
    let number = Double(value)
    if value >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", number / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
}

private func usageAxisLabel(_ date: Date, range: ChartRange) -> String {
    "\(Calendar.current.component(range == .today ? .hour : .day, from: date))"
}
