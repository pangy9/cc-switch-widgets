import Foundation

public struct UsageTotals: Codable, Equatable, Sendable {
    public var totalTokens: Int64
    public var cacheReadTokens: Int64
    public var cacheableTokens: Int64
    public var requestCount: Int
    public var successfulRequests: Int
    public var costUSD: Double

    public init(
        totalTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        cacheableTokens: Int64 = 0,
        requestCount: Int = 0,
        successfulRequests: Int = 0,
        costUSD: Double = 0
    ) {
        self.totalTokens = totalTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheableTokens = cacheableTokens
        self.requestCount = requestCount
        self.successfulRequests = successfulRequests
        self.costUSD = costUSD
    }

    public var successRate: Double {
        requestCount == 0 ? 0 : Double(successfulRequests) / Double(requestCount)
    }

    /// 缓存命中率（cc-switch 官方口径）：cache_read / (input + cache_creation + cache_read)。
    public var cacheHitRate: Double {
        cacheableTokens == 0 ? 0 : Double(cacheReadTokens) / Double(cacheableTokens)
    }

    mutating func add(tokens: Int64, cacheReadTokens: Int64, cacheableTokens: Int64, costUSD: Double, statusCode: Int) {
        totalTokens += tokens
        self.cacheReadTokens += cacheReadTokens
        self.cacheableTokens += cacheableTokens
        requestCount += 1
        successfulRequests += (200 ..< 300).contains(statusCode) ? 1 : 0
        self.costUSD += costUSD
    }

    mutating func add(_ other: UsageTotals) {
        totalTokens += other.totalTokens
        cacheReadTokens += other.cacheReadTokens
        cacheableTokens += other.cacheableTokens
        requestCount += other.requestCount
        successfulRequests += other.successfulRequests
        costUSD += other.costUSD
    }

    private enum CodingKeys: String, CodingKey {
        case totalTokens, cacheReadTokens, cacheableTokens, requestCount, successfulRequests, costUSD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalTokens = try c.decode(Int64.self, forKey: .totalTokens)
        cacheReadTokens = try c.decodeIfPresent(Int64.self, forKey: .cacheReadTokens) ?? 0
        cacheableTokens = try c.decodeIfPresent(Int64.self, forKey: .cacheableTokens) ?? 0
        requestCount = try c.decode(Int.self, forKey: .requestCount)
        successfulRequests = try c.decodeIfPresent(Int.self, forKey: .successfulRequests) ?? 0
        costUSD = try c.decode(Double.self, forKey: .costUSD)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(totalTokens, forKey: .totalTokens)
        try c.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try c.encode(cacheableTokens, forKey: .cacheableTokens)
        try c.encode(requestCount, forKey: .requestCount)
        try c.encode(successfulRequests, forKey: .successfulRequests)
        try c.encode(costUSD, forKey: .costUSD)
    }
}

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let totals: UsageTotals
    public let appTokens: [String: Int64]
    public let modelTokens: [String: Int64]?
    public let appRequests: [String: Int]
    public let modelRequests: [String: Int]
    public let appUsage: [String: UsageTotals]
    public let modelUsage: [String: UsageTotals]

    public var id: Date { date }
    public var totalTokens: Int64 { totals.totalTokens }

    public init(
        date: Date,
        totals: UsageTotals,
        appTokens: [String: Int64] = [:],
        modelTokens: [String: Int64]? = nil,
        appRequests: [String: Int] = [:],
        modelRequests: [String: Int] = [:],
        appUsage: [String: UsageTotals] = [:],
        modelUsage: [String: UsageTotals] = [:]
    ) {
        self.date = date
        self.totals = totals
        self.appTokens = appTokens
        self.modelTokens = modelTokens
        self.appRequests = appRequests
        self.modelRequests = modelRequests
        self.appUsage = appUsage.isEmpty ? Self.legacyUsage(tokens: appTokens, requests: appRequests) : appUsage
        self.modelUsage = modelUsage.isEmpty ? Self.legacyUsage(tokens: modelTokens ?? [:], requests: modelRequests) : modelUsage
    }

    private enum CodingKeys: String, CodingKey {
        case date, totals, appTokens, modelTokens, appRequests, modelRequests, appUsage, modelUsage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        totals = try container.decode(UsageTotals.self, forKey: .totals)
        appTokens = try container.decodeIfPresent([String: Int64].self, forKey: .appTokens) ?? [:]
        modelTokens = try container.decodeIfPresent([String: Int64].self, forKey: .modelTokens)
        appRequests = try container.decodeIfPresent([String: Int].self, forKey: .appRequests) ?? [:]
        modelRequests = try container.decodeIfPresent([String: Int].self, forKey: .modelRequests) ?? [:]
        appUsage = try container.decodeIfPresent([String: UsageTotals].self, forKey: .appUsage)
            ?? Self.legacyUsage(tokens: appTokens, requests: appRequests)
        modelUsage = try container.decodeIfPresent([String: UsageTotals].self, forKey: .modelUsage)
            ?? Self.legacyUsage(tokens: modelTokens ?? [:], requests: modelRequests)
    }

    private static func legacyUsage(tokens: [String: Int64], requests: [String: Int]) -> [String: UsageTotals] {
        Dictionary(uniqueKeysWithValues: tokens.map { id, tokens in
            (id, UsageTotals(totalTokens: tokens, requestCount: requests[id] ?? 0))
        })
    }
}

public struct AppUsage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let totals: UsageTotals
    public let share: Double
    public let trendTokens: [Int64]

    public var totalTokens: Int64 { totals.totalTokens }
    public var successRate: Double { totals.successRate }

    public init(id: String, totals: UsageTotals, share: Double, trendTokens: [Int64]) {
        self.id = id
        self.totals = totals
        self.share = share
        self.trendTokens = trendTokens
    }
}

public struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let totals: UsageTotals
    public let share: Double

    public var totalTokens: Int64 { totals.totalTokens }
    public var successRate: Double { totals.successRate }
    public var cacheHitRate: Double { totals.cacheHitRate }

    public init(id: String, totals: UsageTotals, share: Double) {
        self.id = id
        self.totals = totals
        self.share = share
    }
}

public enum ChartRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case thirtyDays

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .today: "当天"
        case .sevenDays: "7日"
        case .thirtyDays: "30日"
        }
    }

    /// x 轴刻度步长：thirtyDays 恒 2；today 小时数 >15 时 2 否则 1；sevenDays 恒 1。
    public func axisStep(bucketCount: Int) -> Int {
        switch self {
        case .thirtyDays: return 2
        case .today: return bucketCount > 15 ? 2 : 1
        case .sevenDays: return 1
        }
    }

    public func axisLabelIndices(bucketCount: Int) -> [Int] {
        guard bucketCount > 0 else { return [] }
        return Array(stride(from: 0, to: bucketCount, by: axisStep(bucketCount: bucketCount)))
    }
}

public struct RangeTokenSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let totals: UsageTotals
    public let share: Double

    public var totalTokens: Int64 { totals.totalTokens }

    public init(id: String, totalTokens: Int64, share: Double) {
        self.id = id
        totals = UsageTotals(totalTokens: totalTokens)
        self.share = share
    }

    public init(id: String, totals: UsageTotals, share: Double) {
        self.id = id
        self.totals = totals
        self.share = share
    }

    private enum CodingKeys: String, CodingKey { case id, totals, totalTokens, share }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        share = try container.decode(Double.self, forKey: .share)
        totals = try container.decodeIfPresent(UsageTotals.self, forKey: .totals)
            ?? UsageTotals(totalTokens: try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(totals, forKey: .totals)
        try container.encode(share, forKey: .share)
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let today: UsageTotals
    public let yesterday: UsageTotals
    public let sevenDayAverageTokens: Double
    public let hourlyTrend: [DailyUsage]
    public let trend: [DailyUsage]
    public let sixMonthTrend: [DailyUsage]
    public let apps: [AppUsage]
    public let models: [ModelUsage]
    public let monthCostUSD: Double
    public let analysis: UsageAnalysisProjection
    /// 前一周期 per-model token：key=ChartRange.rawValue，value=[modelID: 前一周期 token 总和]。
    public let previousRangeModelTokens: [String: [String: Int64]]

    public init(
        generatedAt: Date,
        today: UsageTotals,
        yesterday: UsageTotals,
        sevenDayAverageTokens: Double,
        hourlyTrend: [DailyUsage] = [],
        trend: [DailyUsage],
        sixMonthTrend: [DailyUsage] = [],
        apps: [AppUsage],
        models: [ModelUsage],
        monthCostUSD: Double,
        previousRangeModelTokens: [String: [String: Int64]] = [:],
        analysis: UsageAnalysisProjection? = nil
    ) {
        self.generatedAt = generatedAt
        self.today = today
        self.yesterday = yesterday
        self.sevenDayAverageTokens = sevenDayAverageTokens
        self.hourlyTrend = hourlyTrend
        self.trend = trend
        self.sixMonthTrend = sixMonthTrend
        self.apps = apps
        self.models = models
        self.monthCostUSD = monthCostUSD
        self.previousRangeModelTokens = previousRangeModelTokens
        self.analysis = analysis ?? .build(
            hourlyTrend: hourlyTrend,
            dailyTrend: trend,
            sixMonthTrend: sixMonthTrend
        )
    }

    /// 取某范围、某模型在「前一周期」的 token 总和（环比口径：当天→昨日、7日→前7-14、30日→前30-60）。
    public func previousRangeTokens(for range: ChartRange, model: String) -> Int64 {
        previousRangeModelTokens[range.rawValue]?[model] ?? 0
    }

    public func buckets(for range: ChartRange) -> [DailyUsage] {
        switch range {
        case .today:
            hourlyTrend
        case .sevenDays:
            Array(trend.suffix(7))
        case .thirtyDays:
            Array(trend.suffix(30))
        }
    }

    public func appSummary(id: String, for range: ChartRange) -> RangeTokenSummary {
        analysis[range].apps.first(where: { $0.id == id })
            ?? RangeTokenSummary(id: id, totalTokens: 0, share: 0)
    }

    public func modelSummaries(for range: ChartRange) -> [RangeTokenSummary] {
        analysis[range].models
    }

    /// 趋势配置使用最近 30 天出现过的完整模型集合；旧快照没有分析投影时回退到摘要模型。
    public var availableTrendModelIDs: [String] {
        let projected = analysis[.thirtyDays].models.map(\.id)
        return projected.isEmpty ? models.map(\.id) : projected
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case today
        case yesterday
        case sevenDayAverageTokens
        case hourlyTrend
        case trend
        case sixMonthTrend
        case apps
        case models
        case monthCostUSD
        case previousRangeModelTokens
        case analysis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        today = try container.decode(UsageTotals.self, forKey: .today)
        yesterday = try container.decode(UsageTotals.self, forKey: .yesterday)
        sevenDayAverageTokens = try container.decode(Double.self, forKey: .sevenDayAverageTokens)
        hourlyTrend = try container.decodeIfPresent([DailyUsage].self, forKey: .hourlyTrend) ?? []
        trend = try container.decode([DailyUsage].self, forKey: .trend)
        sixMonthTrend = try container.decodeIfPresent([DailyUsage].self, forKey: .sixMonthTrend) ?? trend
        apps = try container.decode([AppUsage].self, forKey: .apps)
        models = try container.decode([ModelUsage].self, forKey: .models)
        monthCostUSD = try container.decode(Double.self, forKey: .monthCostUSD)
        previousRangeModelTokens = try container.decodeIfPresent([String: [String: Int64]].self, forKey: .previousRangeModelTokens) ?? [:]
        analysis = try container.decodeIfPresent(UsageAnalysisProjection.self, forKey: .analysis) ?? .build(
            hourlyTrend: hourlyTrend,
            dailyTrend: trend,
            sixMonthTrend: sixMonthTrend
        )
    }

    public static let empty = UsageSnapshot(
        generatedAt: .distantPast,
        today: UsageTotals(),
        yesterday: UsageTotals(),
        sevenDayAverageTokens: 0,
        trend: [],
        apps: [],
        models: [],
        monthCostUSD: 0
    )
}

public enum ThemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    case custom

    public var id: String { rawValue }
}

/// 自定义主题色板：7 个 hex，依次为 [背景, 数据1, 数据2, 数据3, 数据4, 按钮高亮, 标准字体]。
/// 次级字体色由标准字体色加透明度派生。默认复用浅色预设。
public enum CustomPalette {
    public static let defaultHexes: [UInt32] =
        [0xF6FBFD, 0x3752AA, 0x578FCA, 0xA1E3F9, 0xD1F8EF, 0x3752AA, 0x1A1A1A]

    /// 自定义涨跌色：[涨色, 跌色]。默认红涨绿跌。
    public static let defaultMovementHexes: [UInt32] = [0xE60012, 0x00A854]
}

public enum BuiltInThemePalette {
    public static let darkSeriesHexes: [UInt32] = [0x89062B, 0xC40A3E, 0xEA3468, 0xB83B5E]
    public static let lightSeriesHexes: [UInt32] = [0x3752AA, 0x578FCA, 0xA1E3F9, 0xD1F8EF]
}

public enum MovementColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case redDownGreenUp
    case redUpGreenDown
    case custom

    public var id: String { rawValue }
}

public enum DataState: Equatable, Sendable {
    case disconnected
    case live(UsageSnapshot)
    case cached(UsageSnapshot, reason: String)
    case failed(String)
}

/// GitHub 风格热力图的日历坐标：一列是一周，一行固定为周一到周日。
public struct HeatmapCalendarLayout: Sendable {
    public enum CellState: Equatable, Sendable {
        case padding
        case data(DailyUsage)
        case future
    }
    public struct MonthMarker: Equatable, Sendable {
        public let week: Int
        public let label: String
    }

    private let cells: [Int: DailyUsage]
    private let firstDataIndex: Int
    private let lastDataIndex: Int
    public let weekCount: Int
    public let monthMarkers: [MonthMarker]

    public init(days: [DailyUsage], calendar: Calendar = .current) {
        guard let first = days.first?.date, let last = days.last?.date else {
            cells = [:]
            firstDataIndex = 0
            lastDataIndex = -1
            weekCount = 0
            monthMarkers = []
            return
        }

        let firstWeekday = (calendar.component(.weekday, from: first) + 5) % 7
        let firstWeekStart = calendar.date(byAdding: .day, value: -firstWeekday, to: calendar.startOfDay(for: first))!
        var mapped: [Int: DailyUsage] = [:]
        var markers: [MonthMarker] = []
        var markedMonths = Set<DateComponents>()

        for day in days {
            let date = calendar.startOfDay(for: day.date)
            let distance = calendar.dateComponents([.day], from: firstWeekStart, to: date).day ?? 0
            let week = max(0, distance / 7)
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7
            mapped[week * 7 + weekday] = day

            let month = calendar.dateComponents([.year, .month], from: date)
            if !markedMonths.contains(month) {
                markedMonths.insert(month)
                let label = date.formatted(.dateTime.month(.abbreviated))
                markers.append(MonthMarker(week: week, label: label))
            }
        }

        let lastDistance = calendar.dateComponents([.day], from: firstWeekStart, to: calendar.startOfDay(for: last)).day ?? 0
        cells = mapped
        firstDataIndex = mapped.keys.min() ?? 0
        lastDataIndex = mapped.keys.max() ?? -1
        weekCount = max(1, lastDistance / 7 + 1)
        monthMarkers = markers
    }

    public func day(week: Int, weekday: Int) -> DailyUsage? {
        cells[week * 7 + weekday]
    }

    public func hasDay(week: Int, weekday: Int) -> Bool {
        day(week: week, weekday: weekday) != nil
    }

    public func state(week: Int, weekday: Int) -> CellState {
        let index = week * 7 + weekday
        if let day = cells[index] { return .data(day) }
        return index < firstDataIndex ? .padding : .future
    }
}

public enum HeatmapIntensity {
    /// 以非零日期在当前六个月中的分位排名分成四档，避免少数峰值压扁其余颜色。
    public static func level(for value: Int64, among values: [Int64]) -> Int {
        guard value > 0 else { return 0 }
        let positives = values.filter { $0 > 0 }.sorted()
        guard !positives.isEmpty else { return 0 }
        let rank = (positives.lastIndex(where: { $0 <= value }) ?? 0) + 1
        return min(4, max(1, Int(ceil(Double(rank) / Double(positives.count) * 4))))
    }
}

public enum TrendBarLayout {
    public static func width(availableWidth: CGFloat, bucketCount: Int) -> CGFloat {
        guard bucketCount > 0 else { return 3 }
        return min(28, max(3, availableWidth / CGFloat(bucketCount) * 0.64))
    }
}

public enum TrendAxisGeometry {
    public static func domain(bucketCount: Int) -> ClosedRange<Double> {
        guard bucketCount > 1 else { return -0.5 ... 0.5 }
        return -0.5 ... Double(bucketCount - 1) + 0.5
    }
}

public struct TrendAxisLayout: Equatable, Sendable {
    public let bucketCount: Int
    public let range: ChartRange

    public init(bucketCount: Int, range: ChartRange) {
        self.bucketCount = max(0, bucketCount)
        self.range = range
    }

    public var domain: ClosedRange<Double> {
        TrendAxisGeometry.domain(bucketCount: bucketCount)
    }

    public var labelIndices: [Int] {
        range.axisLabelIndices(bucketCount: bucketCount)
    }

    public var gridIndices: [Int] { labelIndices }

    public var labelOffsetX: CGFloat { -4 }
    public var xAxisFontSize: CGFloat { 8.5 }
    public var yAxisFontSize: CGFloat { 8.5 }

    public func nearestBucket(for value: Double) -> Int? {
        guard bucketCount > 0 else { return nil }
        return min(max(Int(value.rounded()), 0), bucketCount - 1)
    }
}

public enum TrendLegendLayout {
    public static func visibleCount(seriesCount: Int) -> Int {
        min(max(0, seriesCount), 6)
    }

    public static func remainingCount(seriesCount: Int) -> Int {
        max(0, seriesCount - visibleCount(seriesCount: seriesCount))
    }

    public static func rowCount(seriesCount: Int) -> Int {
        guard seriesCount > 0 else { return 0 }
        return seriesCount < 3 ? 1 : 2
    }
}

public enum HeatmapGeometry {
    public static let monthGridSpacing: CGFloat = 1.25

    public static func monthLabelLeading(
        gridLeading: CGFloat,
        weekdayGutter: CGFloat,
        week: Int,
        pitch: CGFloat
    ) -> CGFloat {
        gridLeading + weekdayGutter + CGFloat(week) * pitch
    }

    public static func noticePosition(
        hoverLocation: CGPoint,
        noticeSize: CGSize,
        canvasSize: CGSize,
        gap: CGFloat = 8,
        inset: CGFloat = 4
    ) -> CGPoint {
        let halfWidth = noticeSize.width / 2
        let halfHeight = noticeSize.height / 2
        let fitsRight = hoverLocation.x + gap + noticeSize.width <= canvasSize.width - inset
        let preferredX = fitsRight ? hoverLocation.x + gap + halfWidth : hoverLocation.x - gap - halfWidth
        let fitsAbove = hoverLocation.y - gap - noticeSize.height >= inset
        let preferredY = fitsAbove ? hoverLocation.y - gap - halfHeight : hoverLocation.y + gap + halfHeight
        return CGPoint(
            x: min(max(preferredX, inset + halfWidth), max(inset + halfWidth, canvasSize.width - inset - halfWidth)),
            y: min(max(preferredY, inset + halfHeight), max(inset + halfHeight, canvasSize.height - inset - halfHeight))
        )
    }
}
