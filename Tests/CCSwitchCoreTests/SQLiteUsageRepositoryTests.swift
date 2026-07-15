import CCSwitchCore
import CSQLite
import Foundation
import XCTest

final class SQLiteUsageRepositoryTests: XCTestCase {
    func testAggregatesProxyRequestLogsUsingPlannedSemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 20, minute: 30
        )))
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-repository-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try createFixtureDatabase(at: databaseURL)

        let snapshot = try SQLiteUsageRepository(
            databaseURL: databaseURL,
            calendar: calendar
        ).loadSnapshot(now: now)

        XCTAssertEqual(snapshot.today.totalTokens, 185)
        XCTAssertEqual(snapshot.today.requestCount, 2)
        XCTAssertEqual(snapshot.today.successRate, 0.5)
        XCTAssertEqual(snapshot.yesterday.totalTokens, 80)
        XCTAssertEqual(snapshot.hourlyTrend.count, 21)
        XCTAssertEqual(snapshot.hourlyTrend.first { calendar.component(.hour, from: $0.date) == 19 }?.totalTokens, 60)
        XCTAssertEqual(snapshot.hourlyTrend.first { calendar.component(.hour, from: $0.date) == 20 }?.totalTokens, 125)
        let hour20 = try XCTUnwrap(snapshot.hourlyTrend.first { calendar.component(.hour, from: $0.date) == 20 })
        XCTAssertEqual(hour20.appUsage["codex"]?.totalTokens, 125)
        XCTAssertEqual(hour20.appUsage["codex"]?.requestCount, 1)
        XCTAssertEqual(hour20.appUsage["codex"]?.cacheHitRate ?? 0, 30.0 / 105.0, accuracy: 0.0001)
        XCTAssertEqual(hour20.appUsage["codex"]?.costUSD ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(hour20.modelUsage["priced-model"]?.costUSD ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.trend.count, 30)
        let ranges = UsageDateRanges(now: now, calendar: calendar)
        let expectedHeatmapDays = try XCTUnwrap(calendar.dateComponents(
            [.day], from: ranges.heatmapGridStart, to: calendar.startOfDay(for: now)
        ).day) + 1
        XCTAssertEqual(snapshot.sixMonthTrend.count, expectedHeatmapDays)
        XCTAssertEqual(snapshot.trend.suffix(7).filter { $0.totalTokens == 0 }.count, 5)
        XCTAssertEqual(snapshot.apps.map(\.id), ["codex", "claude"])
        XCTAssertEqual(snapshot.apps.first?.trendTokens.suffix(7), [0, 0, 0, 0, 0, 80, 125])
        XCTAssertEqual(snapshot.models.map(\.id), ["priced-model", "claude-request"])
        XCTAssertEqual(snapshot.models.first?.totalTokens, 125)
        XCTAssertEqual(snapshot.models.first?.totals.cacheReadTokens, 30)
        XCTAssertEqual(snapshot.models.first?.totals.cacheableTokens, 105)
        XCTAssertEqual(snapshot.models.first?.cacheHitRate ?? 0, 30.0 / 105.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.previousRangeTokens(for: .today, model: "gpt-yesterday"), 80)
        XCTAssertEqual(snapshot.previousRangeTokens(for: .sevenDays, model: "priced-model"), 0)
        XCTAssertEqual(snapshot.sevenDayAverageTokens, 80.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.monthCostUSD, 4.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.analysis[.today].totals, snapshot.today)
        XCTAssertEqual(snapshot.analysis[.today].apps.first { $0.id == "codex" }?.totals.costUSD ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.analysis[.sevenDays].models, snapshot.modelSummaries(for: .sevenDays))
        XCTAssertEqual(snapshot.analysis.heatmapLevels.count, snapshot.sixMonthTrend.count)
    }

    func testReportsMissingColumnsAsIncompatibleSchema() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-missing-columns-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE proxy_request_logs (created_at INTEGER);", nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try SQLiteUsageRepository(databaseURL: databaseURL).loadSnapshot()) { error in
            guard case let UsageRepositoryError.incompatibleSchema(missing) = error else {
                return XCTFail("Expected incompatible schema, got \(error)")
            }
            XCTAssertTrue(missing.contains("app_type"))
            XCTAssertTrue(missing.contains("input_tokens"))
        }
    }

    func testFreshInputNormalizationMatchesCCSwitchByAppProtocol() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 20, minute: 30
        )))
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-token-semantics-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try createFixtureDatabase(at: databaseURL, insertRows: false)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let insert = """
        INSERT INTO proxy_request_logs VALUES
        ('codex','p','codex','codex-model','','',100,20,30,0,'0',200,1783684800),
        ('gemini','p','gemini','gemini-model','','',80,10,20,0,'0',200,1783684800),
        ('claude','p','claude','claude-model','','',50,5,200,0,'0',200,1783684800),
        ('unknown','p','future-app','future-model','','',40,5,10,0,'0',200,1783684800);
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)

        let snapshot = try SQLiteUsageRepository(databaseURL: databaseURL, calendar: calendar)
            .loadSnapshot(now: now)
        let totals = Dictionary(uniqueKeysWithValues: snapshot.apps.map { ($0.id, $0.totalTokens) })
        XCTAssertEqual(totals["codex"], 120) // (100 - 30) + 20 + 30
        XCTAssertEqual(totals["gemini"], 90) // (80 - 20) + 10 + 20
        XCTAssertEqual(totals["claude"], 255) // Claude input excludes its 200 cache read
        XCTAssertEqual(totals["future-app"], 55) // unknown protocols default to Claude semantics
        XCTAssertEqual(snapshot.today.totalTokens, 520)
    }

    func testEmptyDatabaseReturnsZeroSnapshotWithFilledTrend() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 20)))
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-empty-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try createFixtureDatabase(at: databaseURL, insertRows: false)

        let snapshot = try SQLiteUsageRepository(
            databaseURL: databaseURL,
            calendar: calendar
        ).loadSnapshot(now: now)

        XCTAssertEqual(snapshot.today.totalTokens, 0)
        XCTAssertEqual(snapshot.today.requestCount, 0)
        XCTAssertEqual(snapshot.hourlyTrend.count, 21)
        XCTAssertEqual(snapshot.trend.count, 30)
        XCTAssertGreaterThanOrEqual(snapshot.sixMonthTrend.count, 181)
        XCTAssertTrue(snapshot.sixMonthTrend.allSatisfy { $0.totalTokens == 0 })
        XCTAssertTrue(snapshot.trend.allSatisfy { $0.totalTokens == 0 })
        XCTAssertEqual(snapshot.apps, [])
        XCTAssertEqual(snapshot.models, [])
    }

    func testHeatmapIncludesRealUsageFromVisibleLeadingWeekdays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let january12 = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 12, hour: 10
        )))
        let january13 = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 13, hour: 10
        )))
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-heatmap-leading-week-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try createFixtureDatabase(at: databaseURL, insertRows: false)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let insert = """
        INSERT INTO proxy_request_logs VALUES
        ('jan-12','p','codex','gpt-leading','','',100,20,0,0,'1.00',200,\(Int64(january12.timeIntervalSince1970))),
        ('jan-13','p','codex','gpt-leading','','',200,30,0,0,'2.00',200,\(Int64(january13.timeIntervalSince1970)));
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)

        let snapshot = try SQLiteUsageRepository(databaseURL: databaseURL, calendar: calendar)
            .loadSnapshot(now: now)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(snapshot.sixMonthTrend.first?.date)),
                       DateComponents(year: 2026, month: 1, day: 12))
        XCTAssertEqual(snapshot.sixMonthTrend[0].totalTokens, 120)
        XCTAssertEqual(snapshot.sixMonthTrend[1].totalTokens, 230)
    }

    func testUsageQueryPoliciesRespectEnabledFlagForRegularAndOfficialProviders() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-provider-policy-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE providers (
          id TEXT, name TEXT, app_type TEXT, settings_config TEXT, meta TEXT,
          sort_index INTEGER, icon TEXT
        );
        INSERT INTO providers VALUES
          ('1','DeepSeek','claude','{"env":{"ANTHROPIC_AUTH_TOKEN":"key","ANTHROPIC_BASE_URL":"https://api.deepseek.com"}}','{"usage_script":{"enabled":true,"code":""}}',1,'deepseek'),
          ('2','Disabled','claude','{"env":{"ANTHROPIC_AUTH_TOKEN":"key","ANTHROPIC_BASE_URL":"https://disabled.example"}}','{"usage_script":{"enabled":false,"code":"x"}}',2,''),
          ('3','No Config','claude','{"env":{"ANTHROPIC_AUTH_TOKEN":"key","ANTHROPIC_BASE_URL":"https://none.example"}}','{}',3,''),
          ('4','OpenAI Official','codex','{}','{"usage_script":{"enabled":true,"templateType":"official_subscription"}}',4,'openai'),
          ('5','Claude Official','claude','{}','{}',5,'anthropic');
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)

        let repository = SQLiteUsageRepository(databaseURL: databaseURL)
        XCTAssertEqual(try repository.loadProviders().map(\.name), ["DeepSeek"])
        XCTAssertEqual(try repository.loadProviders().first?.iconName, "deepseek")
        let policies = try repository.loadUsageQueryPolicies()
        XCTAssertTrue(policies.contains { $0.name == "OpenAI Official" && $0.isEnabled })
        XCTAssertTrue(policies.contains { $0.name == "Claude Official" && !$0.isEnabled })
    }

    private func createFixtureDatabase(at url: URL, insertRows: Bool = true) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE proxy_request_logs (
          request_id TEXT PRIMARY KEY, provider_id TEXT, app_type TEXT, model TEXT,
          request_model TEXT, pricing_model TEXT, input_tokens INTEGER,
          output_tokens INTEGER, cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
          total_cost_usd TEXT, status_code INTEGER, created_at INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)
        guard insertRows else { return }

        let insert = """
        INSERT INTO proxy_request_logs VALUES
        ('today-codex','p','codex','raw-model','requested-model','priced-model',100,20,30,5,'1.25',200,1783684800),
        ('today-claude','p','claude','fallback-model','claude-request','',50,10,0,0,'0.50',500,1783681200),
        ('yesterday','p','codex','gpt-yesterday','','',70,10,20,0,'0.75',201,1783598400),
        ('month-only','p','codex','old-model','','',10,5,0,0,'2.00',200,1782993600);
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)
    }
}
