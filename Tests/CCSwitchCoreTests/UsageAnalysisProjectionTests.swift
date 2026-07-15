import CCSwitchCore
import Foundation
import XCTest

final class UsageAnalysisProjectionTests: XCTestCase {
    func testProjectionPrecomputesEveryRangeFromCanonicalBuckets() {
        let hours = makeBuckets(count: 3, tokenBase: 10)
        let days = makeBuckets(count: 30, tokenBase: 1)
        let projection = UsageAnalysisProjection.build(
            hourlyTrend: hours,
            dailyTrend: days,
            sixMonthTrend: days
        )

        XCTAssertEqual(projection[.today].totals.totalTokens, hours.map(\.totalTokens).reduce(0, +))
        XCTAssertEqual(projection[.sevenDays].totals.totalTokens, days.suffix(7).map(\.totalTokens).reduce(0, +))
        XCTAssertEqual(projection[.thirtyDays].totals.totalTokens, days.map(\.totalTokens).reduce(0, +))
        XCTAssertEqual(projection.heatmapLevels.count, days.count)
    }

    func testProjectionSortsStableSummariesAndCalculatesShares() {
        let buckets = [
            DailyUsage(
                date: Date(timeIntervalSince1970: 0),
                totals: UsageTotals(totalTokens: 400, requestCount: 4, successfulRequests: 3, costUSD: 2),
                appTokens: ["codex": 100, "claude": 300],
                modelTokens: ["z-model": 200, "a-model": 200],
                appUsage: [
                    "codex": UsageTotals(totalTokens: 100, cacheReadTokens: 20, cacheableTokens: 50, requestCount: 1, successfulRequests: 1, costUSD: 1),
                    "claude": UsageTotals(totalTokens: 300, cacheReadTokens: 30, cacheableTokens: 100, requestCount: 3, successfulRequests: 2, costUSD: 3),
                ],
                modelUsage: [
                    "z-model": UsageTotals(totalTokens: 200, cacheReadTokens: 10, cacheableTokens: 40, requestCount: 2, successfulRequests: 2, costUSD: 2),
                    "a-model": UsageTotals(totalTokens: 200, cacheReadTokens: 20, cacheableTokens: 50, requestCount: 2, successfulRequests: 1, costUSD: 2),
                ]
            ),
        ]

        let projection = UsageAnalysisProjection.build(
            hourlyTrend: buckets,
            dailyTrend: buckets,
            sixMonthTrend: buckets
        )[.today]

        XCTAssertEqual(projection.totals, buckets[0].totals)
        XCTAssertEqual(projection.apps.map(\.id), ["claude", "codex"])
        XCTAssertEqual(projection.apps.map(\.share), [0.75, 0.25])
        XCTAssertEqual(projection.models.map(\.id), ["a-model", "z-model"])
        XCTAssertEqual(projection.apps.first?.totals.costUSD, 3)
        XCTAssertEqual(projection.models.first?.totals.cacheHitRate ?? 0, 0.4, accuracy: 0.0001)
    }

    func testProjectionHandlesZeroDataWithoutNaN() {
        let zero = DailyUsage(date: Date(), totals: UsageTotals(), appTokens: ["codex": 0], modelTokens: nil)
        let projection = UsageAnalysisProjection.build(
            hourlyTrend: [zero],
            dailyTrend: [zero],
            sixMonthTrend: [zero]
        )

        XCTAssertEqual(projection[.today].apps.first?.share, 0)
        XCTAssertFalse(projection[.today].apps.first?.share.isNaN ?? true)
        XCTAssertEqual(projection[.today].models, [])
        XCTAssertEqual(projection.heatmapLevels, [0])
    }

    func testProjectionKeepsEveryModelWithCompleteDistributionMetrics() {
        var modelUsage: [String: UsageTotals] = [:]
        for index in 0 ..< 12 {
            modelUsage["model-\(index)"] = UsageTotals(
                totalTokens: Int64(index + 1) * 100,
                cacheReadTokens: Int64(index + 1) * 10,
                cacheableTokens: Int64(index + 1) * 20,
                requestCount: index + 1,
                successfulRequests: index + 1,
                costUSD: Double(index + 1) / 10
            )
        }
        var totals = UsageTotals()
        for value in modelUsage.values {
            totals.totalTokens += value.totalTokens
            totals.cacheReadTokens += value.cacheReadTokens
            totals.cacheableTokens += value.cacheableTokens
            totals.requestCount += value.requestCount
            totals.successfulRequests += value.successfulRequests
            totals.costUSD += value.costUSD
        }
        let bucket = DailyUsage(
            date: Date(timeIntervalSince1970: 0),
            totals: totals,
            modelTokens: modelUsage.mapValues { $0.totalTokens },
            modelUsage: modelUsage
        )

        let projection = UsageAnalysisProjection.build(
            hourlyTrend: [bucket], dailyTrend: [bucket], sixMonthTrend: [bucket]
        )[.today]

        XCTAssertEqual(projection.models.count, 12)
        XCTAssertTrue(projection.models.allSatisfy { $0.totals.requestCount > 0 })
        XCTAssertTrue(projection.models.allSatisfy { $0.totals.cacheHitRate == 0.5 })
        XCTAssertTrue(projection.models.allSatisfy { $0.totals.costUSD > 0 })
        XCTAssertEqual(projection.models.map { $0.share }.reduce(0, +), 1, accuracy: 0.0001)
    }

    func testHeatmapLevelsStayAlignedWithOriginalDays() {
        let tokens: [Int64] = [0, 10, 20, 30, 40, 10_000]
        let days = tokens.enumerated().map { index, tokens in
            DailyUsage(
                date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                totals: UsageTotals(totalTokens: tokens, requestCount: index)
            )
        }

        let projection = UsageAnalysisProjection.build(hourlyTrend: [], dailyTrend: [], sixMonthTrend: days)

        XCTAssertEqual(projection.heatmapLevels, [0, 1, 2, 3, 4, 4])
        XCTAssertEqual(days[3].totals.requestCount, 3)
    }

    func testDailyUsagePreservesPerToolAndPerModelRequestCounts() throws {
        let usage = DailyUsage(
            date: Date(timeIntervalSince1970: 0),
            totals: UsageTotals(totalTokens: 30, requestCount: 3),
            appTokens: ["codex": 20, "claude": 10],
            modelTokens: ["gpt": 20, "sonnet": 10],
            appRequests: ["codex": 2, "claude": 1],
            modelRequests: ["gpt": 2, "sonnet": 1]
        )

        let decoded = try JSONDecoder().decode(DailyUsage.self, from: JSONEncoder().encode(usage))

        XCTAssertEqual(decoded.appRequests, ["codex": 2, "claude": 1])
        XCTAssertEqual(decoded.modelRequests, ["gpt": 2, "sonnet": 1])
    }

    func testLegacyDailyUsageDecodesMissingRequestBreakdownAsEmpty() throws {
        let json = #"{"date":0,"totals":{"totalTokens":1,"requestCount":1,"costUSD":0},"appTokens":{"codex":1}}"#
        let decoded = try JSONDecoder().decode(DailyUsage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.appRequests, [:])
        XCTAssertEqual(decoded.modelRequests, [:])
    }

    func testTrendScopeIncludesModelDimension() {
        XCTAssertEqual(ModuleTrendScope.allCases, [.byTool, .byModel, .total])
    }

    func testUsageNoticeMetricsExposeCompleteSeriesMetrics() {
        let totals = UsageTotals(
            totalTokens: 500, cacheReadTokens: 40, cacheableTokens: 100,
            requestCount: 7, successfulRequests: 6, costUSD: 1.25
        )
        let metrics = UsageNoticeMetrics(totals: totals)

        XCTAssertEqual(metrics.totalTokens, 500)
        XCTAssertEqual(metrics.requestCount, 7)
        XCTAssertEqual(metrics.cacheHitRate, 0.4)
        XCTAssertEqual(metrics.costUSD, 1.25)
        XCTAssertNil(UsageNoticeMetrics(totals: UsageTotals()).cacheHitRate)
    }

    func testTrendNoticeHeadlineIncludesBucketTotal() {
        XCTAssertEqual(
            UsageNoticeHeadline.text(dateText: "7月14日", totalTokens: 123_000_000),
            "7月14日 · 当天总消耗 123.00M"
        )
    }

    func testNoticeDateFormattingFollowsChartRange() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 13, hour: 9, minute: 5
        )))

        XCTAssertEqual(UsageNoticeDateFormatter.string(from: date, range: .today, timeZone: timeZone), "09:05")
        XCTAssertEqual(UsageNoticeDateFormatter.string(from: date, range: .sevenDays, timeZone: timeZone), "7月13日")
        XCTAssertEqual(UsageNoticeDateFormatter.string(from: date, range: .thirtyDays, timeZone: timeZone), "7月13日")
    }

    private func makeBuckets(count: Int, tokenBase: Int64) -> [DailyUsage] {
        (0 ..< count).map { index in
            let tokens = tokenBase + Int64(index)
            return DailyUsage(
                date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                totals: UsageTotals(
                    totalTokens: tokens,
                    cacheReadTokens: tokens / 4,
                    cacheableTokens: tokens / 2,
                    requestCount: index + 1,
                    successfulRequests: index,
                    costUSD: Double(tokens) / 100
                ),
                appTokens: ["codex": tokens],
                modelTokens: ["gpt": tokens]
            )
        }
    }
}
