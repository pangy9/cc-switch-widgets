import CCSwitchCore
import CSQLite
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case let .mismatch(message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.mismatch(message) }
}

func day(_ date: Date, calendar: Calendar) -> DateComponents {
    calendar.dateComponents([.year, .month, .day], from: date)
}

var calendar = Calendar(identifier: .gregorian)
guard let timeZone = TimeZone(identifier: "Asia/Shanghai") else { fatalError("missing timezone") }
calendar.timeZone = timeZone
guard let now = calendar.date(from: DateComponents(
    year: 2026, month: 7, day: 10, hour: 20, minute: 30
)) else { fatalError("invalid fixture date") }

do {
    let ranges = UsageDateRanges(now: now, calendar: calendar)
    try expect(day(ranges.todayStart, calendar: calendar) == DateComponents(year: 2026, month: 7, day: 10), "today boundary")
    try expect(day(ranges.yesterdayStart, calendar: calendar) == DateComponents(year: 2026, month: 7, day: 9), "yesterday boundary")
    try expect(day(ranges.averageStart, calendar: calendar) == DateComponents(year: 2026, month: 7, day: 3), "average boundary")
    try expect(day(ranges.trendStart, calendar: calendar) == DateComponents(year: 2026, month: 6, day: 11), "trend boundary")
    try expect(day(ranges.monthStart, calendar: calendar) == DateComponents(year: 2026, month: 7, day: 1), "month boundary")

    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ccswitch-core-checks-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    var database: OpaquePointer?
    try expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK, "create fixture database")

    let schema = """
    CREATE TABLE proxy_request_logs (
      request_id TEXT PRIMARY KEY, provider_id TEXT, app_type TEXT, model TEXT,
      request_model TEXT, pricing_model TEXT, input_tokens INTEGER,
      output_tokens INTEGER, cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
      total_cost_usd TEXT, status_code INTEGER, created_at INTEGER
    );
    """
    try expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK, "create fixture schema")

    let insert = """
    INSERT INTO proxy_request_logs VALUES
    ('today-codex','p','codex','raw-model','requested-model','priced-model',100,20,30,5,'1.25',200,1783684800),
    ('today-claude','p','claude','fallback-model','claude-request','',50,10,0,0,'0.50',500,1783681200),
    ('yesterday','p','codex','gpt-yesterday','','',70,10,20,0,'0.75',201,1783598400),
    ('month-only','p','codex','old-model','','',10,5,0,0,'2.00',200,1782993600);
    """
    try expect(sqlite3_exec(database, insert, nil, nil, nil) == SQLITE_OK, "insert fixture rows")
    sqlite3_close(database)
    database = nil

    let snapshot = try SQLiteUsageRepository(
        databaseURL: databaseURL,
        calendar: calendar
    ).loadSnapshot(now: now)

    try expect(snapshot.today.totalTokens == 185, "today uses cache-normalized token semantics")
    try expect(snapshot.today.requestCount == 2, "today request count")
    try expect(snapshot.today.successRate == 0.5, "today 2xx success rate")
    try expect(snapshot.yesterday.totalTokens == 80, "yesterday total")
    try expect(snapshot.trend.count == 30, "trend fills thirty calendar days")
    try expect(snapshot.trend.suffix(7).filter { $0.totalTokens == 0 }.count == 5, "trend fills missing days with zero")
    try expect(abs(snapshot.monthCostUSD - 4.5) < 0.0001, "month cost includes older month rows")
    try expect(snapshot.apps.map(\.id) == ["codex", "claude"], "apps sort by token descending")
    try expect(snapshot.models.map(\.id) == ["priced-model", "claude-request"], "model fallback and token sorting")
    try expect(snapshot.models.first?.totalTokens == 125, "top model token total")
    try expect(abs(snapshot.sevenDayAverageTokens - (80.0 / 7.0)) < 0.0001, "average uses seven complete days")
    let projectedCodex = snapshot.analysis[.sevenDays].apps.first { $0.id == "codex" }
    try expect(snapshot.appSummary(id: "codex", for: .sevenDays) == projectedCodex, "card app summary reuses projection")
    try expect(snapshot.modelSummaries(for: .thirtyDays) == snapshot.analysis[.thirtyDays].models, "model ranking reuses projection")
    try expect(snapshot.analysis.heatmapLevels.count == snapshot.sixMonthTrend.count, "heatmap levels align with canonical days")
    print("CoreChecks: PASS")
} catch {
    fputs("CoreChecks: FAIL: \(error)\n", stderr)
    exit(1)
}
