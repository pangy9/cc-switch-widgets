import Foundation

public struct UsageRangeProjection: Codable, Equatable, Sendable {
    public let range: ChartRange
    public let totals: UsageTotals
    public let apps: [RangeTokenSummary]
    public let models: [RangeTokenSummary]

    public init(
        range: ChartRange,
        totals: UsageTotals,
        apps: [RangeTokenSummary],
        models: [RangeTokenSummary]
    ) {
        self.range = range
        self.totals = totals
        self.apps = apps
        self.models = models
    }

    public static func empty(range: ChartRange) -> UsageRangeProjection {
        UsageRangeProjection(range: range, totals: UsageTotals(), apps: [], models: [])
    }
}

public struct UsageAnalysisProjection: Codable, Equatable, Sendable {
    public let ranges: [String: UsageRangeProjection]
    public let heatmapLevels: [Int]

    public init(ranges: [String: UsageRangeProjection], heatmapLevels: [Int]) {
        self.ranges = ranges
        self.heatmapLevels = heatmapLevels
    }

    public subscript(_ range: ChartRange) -> UsageRangeProjection {
        ranges[range.rawValue] ?? .empty(range: range)
    }

    public static func build(
        hourlyTrend: [DailyUsage],
        dailyTrend: [DailyUsage],
        sixMonthTrend: [DailyUsage]
    ) -> UsageAnalysisProjection {
        let buckets: [(ChartRange, [DailyUsage])] = [
            (.today, hourlyTrend),
            (.sevenDays, Array(dailyTrend.suffix(7))),
            (.thirtyDays, Array(dailyTrend.suffix(30))),
        ]
        let ranges = Dictionary(uniqueKeysWithValues: buckets.map { range, values in
            (range.rawValue, buildRange(range: range, buckets: values))
        })
        let heatmapValues = sixMonthTrend.map(\.totalTokens)
        return UsageAnalysisProjection(
            ranges: ranges,
            heatmapLevels: heatmapValues.map { HeatmapIntensity.level(for: $0, among: heatmapValues) }
        )
    }

    private static func buildRange(range: ChartRange, buckets: [DailyUsage]) -> UsageRangeProjection {
        var totals = UsageTotals()
        var appUsage: [String: UsageTotals] = [:]
        var modelUsage: [String: UsageTotals] = [:]
        for bucket in buckets {
            totals.totalTokens += bucket.totals.totalTokens
            totals.cacheReadTokens += bucket.totals.cacheReadTokens
            totals.cacheableTokens += bucket.totals.cacheableTokens
            totals.requestCount += bucket.totals.requestCount
            totals.successfulRequests += bucket.totals.successfulRequests
            totals.costUSD += bucket.totals.costUSD
            for (id, value) in bucket.appUsage { appUsage[id, default: UsageTotals()].add(value) }
            for (id, value) in bucket.modelUsage { modelUsage[id, default: UsageTotals()].add(value) }
        }
        return UsageRangeProjection(
            range: range,
            totals: totals,
            apps: summaries(from: appUsage, totalTokens: totals.totalTokens),
            models: summaries(from: modelUsage, totalTokens: totals.totalTokens)
        )
    }

    private static func summaries(from values: [String: UsageTotals], totalTokens: Int64) -> [RangeTokenSummary] {
        values.map { id, totals in
            RangeTokenSummary(
                id: id,
                totals: totals,
                share: totalTokens == 0 ? 0 : Double(totals.totalTokens) / Double(totalTokens)
            )
        }
        .sorted { lhs, rhs in
            lhs.totalTokens == rhs.totalTokens ? lhs.id < rhs.id : lhs.totalTokens > rhs.totalTokens
        }
    }
}
