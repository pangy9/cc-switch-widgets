import CCSwitchCore
import Foundation
import XCTest

final class UsageModelsTests: XCTestCase {
    func testBuiltInDarkThemeUsesWarmWhiteAsFourthDataColor() {
        XCTAssertEqual(BuiltInThemePalette.darkSeriesHexes, [0x89062B, 0xC40A3E, 0xEA3468, 0xB83B5E])
    }

    func testToolIconResolverUsesKnownBrandResourcesAndGenericFallback() {
        XCTAssertEqual(ToolIconResolver.resourceName(for: "codex"), "openai")
        XCTAssertEqual(ToolIconResolver.resourceName(for: "claude"), "anthropic")
        XCTAssertEqual(ToolIconResolver.resourceName(for: "gemini"), "gemini")
        XCTAssertEqual(ToolIconResolver.resourceName(for: "private-tool"), "model-generic")
    }

    func testMenuBarMetricUsesCompactSegmentLabels() {
        XCTAssertEqual(MenuBarPrimaryMetric.allCases.map(\.segmentTitle), ["图标", "请求数", "Token", "花费"])
    }

    func testModelFamilyResolverRecognizesCommonNamesAndVendorPrefixes() {
        let cases: [(String, ModelFamily)] = [
            ("openai/gpt-5.5", .openAI),
            ("o3-mini", .openAI),
            ("codex-auto-review", .openAI),
            ("anthropic/claude-sonnet-4", .anthropic),
            ("gemini-3-flash", .google),
            ("deepseek-v4", .deepSeek),
            ("glm-5.2", .zhipu),
            ("qwen3-coder", .qwen),
            ("kimi-k2", .kimi),
            ("minimax-m2", .minimax),
            ("codestral-latest", .mistral),
            ("grok-4", .xAI),
            ("meta/llama-4", .meta),
            ("doubao-pro", .bytedance),
            ("yi-lightning", .yi),
            ("mimo-v2", .xiaomi),
            ("nemotron-ultra", .nvidia),
            ("private-custom-model", .generic),
        ]

        for (name, expected) in cases {
            XCTAssertEqual(ModelFamilyResolver.resolve(name), expected, name)
        }
    }
    func testSnapshotPersistsReusableAnalysisProjection() throws {
        let daily = makeBuckets(count: 30)
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            today: UsageTotals(),
            yesterday: UsageTotals(),
            sevenDayAverageTokens: 0,
            hourlyTrend: Array(daily.prefix(3)),
            trend: daily,
            sixMonthTrend: daily,
            apps: [],
            models: [],
            monthCostUSD: 0
        )

        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.analysis, snapshot.analysis)
        XCTAssertEqual(decoded.analysis[.sevenDays].totals.totalTokens, daily.suffix(7).map(\.totalTokens).reduce(0, +))
    }

    func testLegacySnapshotWithoutAnalysisRebuildsProjection() throws {
        let daily = makeBuckets(count: 7)
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            today: UsageTotals(), yesterday: UsageTotals(),
            sevenDayAverageTokens: 0, trend: daily, sixMonthTrend: daily,
            apps: [], models: [], monthCostUSD: 0
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "analysis")

        let decoded = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.analysis[.sevenDays].models.map(\.id), ["gpt"])
        XCTAssertEqual(decoded.analysis.heatmapLevels.count, daily.count)
    }

    func testChartRangeSelectsHourlyOrDailyBuckets() {
        let hourly = makeBuckets(count: 24)
        let daily = makeBuckets(count: 30)
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            today: UsageTotals(),
            yesterday: UsageTotals(),
            sevenDayAverageTokens: 0,
            hourlyTrend: hourly,
            trend: daily,
            apps: [],
            models: [],
            monthCostUSD: 0
        )

        XCTAssertEqual(snapshot.buckets(for: .today), hourly)
        XCTAssertEqual(snapshot.buckets(for: .sevenDays), Array(daily.suffix(7)))
        XCTAssertEqual(snapshot.buckets(for: .thirtyDays), daily)
    }

    func testLegacySnapshotWithoutHourlyTrendDecodesWithEmptyHourlyTrend() throws {
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            today: UsageTotals(totalTokens: 42),
            yesterday: UsageTotals(),
            sevenDayAverageTokens: 6,
            hourlyTrend: [],
            trend: makeBuckets(count: 7),
            apps: [],
            models: [],
            monthCostUSD: 1.25
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "hourlyTrend")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.hourlyTrend, [])
        XCTAssertEqual(decoded.today.totalTokens, 42)
    }

    func testChartRangeProvidesCompactVisibleLabels() {
        XCTAssertEqual(ChartRange.today.shortLabel, "当天")
        XCTAssertEqual(ChartRange.sevenDays.shortLabel, "7日")
        XCTAssertEqual(ChartRange.thirtyDays.shortLabel, "30日")
    }

    func testThirtyDayAxisLabelsSkipEveryOtherBucket() {
        XCTAssertEqual(ChartRange.thirtyDays.axisLabelIndices(bucketCount: 6), [0, 2, 4])
        XCTAssertEqual(ChartRange.sevenDays.axisLabelIndices(bucketCount: 6), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(ChartRange.today.axisLabelIndices(bucketCount: 3), [0, 1, 2])
    }

    func testTodayAxisLabelsCompressWhenBucketCountExceedsFifteen() {
        XCTAssertEqual(ChartRange.today.axisLabelIndices(bucketCount: 20), [0, 2, 4, 6, 8, 10, 12, 14, 16, 18])
        XCTAssertEqual(ChartRange.today.axisLabelIndices(bucketCount: 15), Array(0 ..< 15))
        XCTAssertEqual(ChartRange.today.axisStep(bucketCount: 16), 2)
        XCTAssertEqual(ChartRange.today.axisStep(bucketCount: 15), 1)
    }

    func testCacheHitRateUsesCacheableDenominator() {
        let totals = UsageTotals(totalTokens: 200, cacheReadTokens: 60, cacheableTokens: 150)
        XCTAssertEqual(totals.cacheHitRate, 0.4, accuracy: 0.0001)
        XCTAssertEqual(UsageTotals().cacheHitRate, 0)
    }

    func testLegacyTotalsDecodeWithoutCacheFields() throws {
        let json = """
        {"totalTokens":42,"requestCount":3,"costUSD":1.5}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UsageTotals.self, from: json)
        XCTAssertEqual(decoded.totalTokens, 42)
        XCTAssertEqual(decoded.cacheReadTokens, 0)
        XCTAssertEqual(decoded.cacheableTokens, 0)
        XCTAssertEqual(decoded.successfulRequests, 0)
    }

    func testLegacySnapshotWithoutPreviousRangeTokensDefaultsEmpty() throws {
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            today: UsageTotals(), yesterday: UsageTotals(),
            sevenDayAverageTokens: 0, trend: [], apps: [], models: [], monthCostUSD: 0
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "previousRangeModelTokens")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: legacyData)
        XCTAssertEqual(decoded.previousRangeTokens(for: .today, model: "x"), 0)
    }

    func testRangeSummariesRecalculateTokensSharesAndRanking() {
        let daily = [
            DailyUsage(date: Date(), totals: UsageTotals(totalTokens: 100), appTokens: ["codex": 80, "claude": 20], modelTokens: ["a": 80, "b": 20]),
            DailyUsage(date: Date().addingTimeInterval(86_400), totals: UsageTotals(totalTokens: 300), appTokens: ["codex": 30, "claude": 270], modelTokens: ["a": 30, "b": 270]),
        ]
        let snapshot = UsageSnapshot(
            generatedAt: Date(), today: UsageTotals(), yesterday: UsageTotals(),
            sevenDayAverageTokens: 0, hourlyTrend: daily, trend: daily,
            apps: [], models: [], monthCostUSD: 0
        )

        XCTAssertEqual(snapshot.appSummary(id: "codex", for: .today).totalTokens, 110)
        XCTAssertEqual(snapshot.appSummary(id: "codex", for: .today).share, 0.275, accuracy: 0.0001)
        XCTAssertEqual(snapshot.modelSummaries(for: .sevenDays).map(\.id), ["b", "a"])
        XCTAssertEqual(snapshot.modelSummaries(for: .sevenDays).map(\.totalTokens), [290, 110])
    }

    func testTrendModelCandidatesUseThirtyDayAnalysisInsteadOfTodayOnlyModels() {
        let daily = [
            DailyUsage(
                date: Date(),
                totals: UsageTotals(totalTokens: 300),
                modelTokens: ["gpt-5.6": 200, "claude-opus": 80, "glm-5": 20]
            )
        ]
        let snapshot = UsageSnapshot(
            generatedAt: Date(),
            today: UsageTotals(totalTokens: 200),
            yesterday: UsageTotals(),
            sevenDayAverageTokens: 0,
            trend: daily,
            apps: [],
            models: [ModelUsage(id: "gpt-5.6", totals: UsageTotals(totalTokens: 200), share: 1)],
            monthCostUSD: 0
        )

        XCTAssertEqual(snapshot.availableTrendModelIDs, ["gpt-5.6", "claude-opus", "glm-5"])
    }

    private func makeBuckets(count: Int) -> [DailyUsage] {
        (0 ..< count).map { index in
            DailyUsage(
                date: Date(timeIntervalSince1970: TimeInterval(index * 3_600)),
                totals: UsageTotals(totalTokens: Int64(index)),
                appTokens: ["codex": Int64(index)],
                modelTokens: ["gpt": Int64(index)]
            )
        }
    }
}
