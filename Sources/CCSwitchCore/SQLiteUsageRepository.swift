#if canImport(CSQLite)
import CSQLite
#else
import SQLite3
#endif
import Foundation

public enum UsageRepositoryError: Error, LocalizedError, Equatable {
    case cannotOpen(String)
    case incompatibleSchema([String])
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .cannotOpen(message): "无法只读打开 CC Switch 数据库：\(message)"
        case let .incompatibleSchema(columns): "CC Switch 数据库缺少字段：\(columns.joined(separator: ", "))"
        case let .queryFailed(message): "读取 CC Switch 统计失败：\(message)"
        }
    }
}

public struct SQLiteUsageRepository {
    private let databaseURL: URL
    private let calendar: Calendar

    public init(databaseURL: URL, calendar: Calendar = .current) {
        self.databaseURL = databaseURL
        self.calendar = calendar
    }

    public func loadSnapshot(now: Date = Date()) throws -> UsageSnapshot {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw UsageRepositoryError.cannotOpen(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 1_500)
        guard sqlite3_db_readonly(database, "main") == 1 else {
            throw UsageRepositoryError.cannotOpen("database was not opened read-only")
        }
        guard sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else {
            throw UsageRepositoryError.queryFailed(errorMessage(database))
        }

        try validateSchema(database)
        let ranges = UsageDateRanges(now: now, calendar: calendar)
        let lowerBound = min(ranges.monthStart, ranges.averageStart, ranges.trendStart, ranges.extendedTrendStart, ranges.heatmapGridStart)
        let records = try readRecords(
            database,
            from: Int64(lowerBound.timeIntervalSince1970),
            through: Int64(now.timeIntervalSince1970)
        )
        return aggregate(records: records, ranges: ranges)
    }

    /// 读取 cc-switch providers 表，解析 settings_config.env 里的 API key 和 base url。
    /// 兼容 claude(ANTHROPIC_AUTH_TOKEN/BASE_URL) / codex(OPENAI_API_KEY/BASE_URL) / gemini 三类。
    public func loadProviders() throws -> [ProviderConfig] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw UsageRepositoryError.cannotOpen(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_500)
        sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)

        let sql = "SELECT id, name, app_type, settings_config, meta, icon FROM providers ORDER BY sort_index, rowid"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UsageRepositoryError.queryFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var providers: [ProviderConfig] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, index: 0)
            let name = columnString(statement, index: 1)
            let appType = columnString(statement, index: 2)
            let settingsJSON = columnString(statement, index: 3)
            let metaJSON = columnString(statement, index: 4)
            let iconName = columnString(statement, index: 5)
            guard let metaData = metaJSON.data(using: .utf8),
                  let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
                  let script = meta["usage_script"] as? [String: Any],
                  (script["enabled"] as? Bool) == true else { continue }
            guard let data = settingsJSON.data(using: .utf8),
                  let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let env = settings["env"] as? [String: Any] else { continue }
            let apiKey = (env["ANTHROPIC_AUTH_TOKEN"] as? String)
                ?? (env["OPENAI_API_KEY"] as? String)
                ?? (env["GEMINI_API_KEY"] as? String)
                ?? ""
            let baseUrl = (env["ANTHROPIC_BASE_URL"] as? String)
                ?? (env["OPENAI_BASE_URL"] as? String)
                ?? (env["GEMINI_API_BASE"] as? String)
                ?? ""
            guard !apiKey.isEmpty, !baseUrl.isEmpty else { continue }
            // 读 meta.usage_script.code（cc-switch 自定义余额查询脚本）
            let usageScriptCode = (script["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            providers.append(ProviderConfig(id: id, name: name, appType: appType, baseUrl: baseUrl, apiKey: apiKey, usageScriptCode: usageScriptCode, iconName: iconName.isEmpty ? nil : iconName))
        }
        return providers
    }

    public func loadUsageQueryPolicies() throws -> [ProviderUsageQueryPolicy] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw UsageRepositoryError.cannotOpen(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_500)
        sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)

        var statement: OpaquePointer?
        let sql = "SELECT id, name, app_type, meta, icon FROM providers ORDER BY sort_index, rowid"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw UsageRepositoryError.queryFailed(errorMessage(database)) }
        defer { sqlite3_finalize(statement) }

        var result: [ProviderUsageQueryPolicy] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, index: 0)
            let name = columnString(statement, index: 1)
            let appType = columnString(statement, index: 2)
            let metaJSON = columnString(statement, index: 3)
            let iconName = columnString(statement, index: 4)
            let script: [String: Any]? = metaJSON.data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["usage_script"] as? [String: Any] }
            result.append(ProviderUsageQueryPolicy(
                id: id,
                name: name,
                appType: appType,
                isEnabled: (script?["enabled"] as? Bool) == true,
                templateType: script?["templateType"] as? String,
                iconName: iconName.isEmpty ? nil : iconName
            ))
        }
        return result
    }

    private func validateSchema(_ database: OpaquePointer) throws {
        let required: Set<String> = [
            "app_type", "model", "request_model", "pricing_model", "input_tokens",
            "output_tokens", "cache_read_tokens", "cache_creation_tokens",
            "total_cost_usd", "status_code", "created_at",
        ]
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(proxy_request_logs)", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UsageRepositoryError.queryFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var available = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            available.insert(columnString(statement, index: 1))
        }
        let missing = required.subtracting(available).sorted()
        guard missing.isEmpty else { throw UsageRepositoryError.incompatibleSchema(missing) }
    }

    private func readRecords(
        _ database: OpaquePointer,
        from lowerBound: Int64,
        through upperBound: Int64
    ) throws -> [LogRecord] {
        let sql = """
        SELECT app_type, model, request_model, pricing_model,
               input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
               total_cost_usd, status_code, created_at
        FROM proxy_request_logs
        WHERE created_at >= ?1 AND created_at <= ?2
        ORDER BY created_at ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UsageRepositoryError.queryFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lowerBound)
        sqlite3_bind_int64(statement, 2, upperBound)

        var records: [LogRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let appType = normalized(columnString(statement, index: 0), fallback: "unknown")
                let inputTokens = sqlite3_column_int64(statement, 4)
                let cacheReadTokens = sqlite3_column_int64(statement, 6)
                let cacheCreationTokens = sqlite3_column_int64(statement, 7)
                let freshInputTokens = normalizedFreshInputTokens(
                    appType: appType,
                    inputTokens: inputTokens,
                    cacheReadTokens: cacheReadTokens
                )
                records.append(LogRecord(
                    appType: appType,
                    model: resolvedModel(
                        pricing: columnString(statement, index: 3),
                        request: columnString(statement, index: 2),
                        raw: columnString(statement, index: 1)
                    ),
                    tokens: freshInputTokens
                        + sqlite3_column_int64(statement, 5)
                        + cacheReadTokens
                        + cacheCreationTokens,
                    cacheReadTokens: cacheReadTokens,
                    cacheableTokens: freshInputTokens + cacheReadTokens + cacheCreationTokens,
                    costUSD: Double(columnString(statement, index: 8)) ?? 0,
                    statusCode: Int(sqlite3_column_int(statement, 9)),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 10)))
                ))
            case SQLITE_DONE:
                return records
            default:
                throw UsageRepositoryError.queryFailed(errorMessage(database))
            }
        }
    }

    /// CC Switch 的统一“新增输入”口径：Codex/Gemini 的原始输入已包含
    /// cache read，需要扣除；Claude 和未知协议的输入本身就是新增输入。
    private func normalizedFreshInputTokens(
        appType: String,
        inputTokens: Int64,
        cacheReadTokens: Int64
    ) -> Int64 {
        guard ["codex", "gemini"].contains(appType), inputTokens >= cacheReadTokens else {
            return inputTokens
        }
        return inputTokens - cacheReadTokens
    }

    private func aggregate(records: [LogRecord], ranges: UsageDateRanges) -> UsageSnapshot {
        var dailyTotals: [Date: UsageTotals] = [:]
        var dailyApps: [Date: [String: Int64]] = [:]
        var dailyModels: [Date: [String: Int64]] = [:]
        var hourlyTotals: [Date: UsageTotals] = [:]
        var hourlyApps: [Date: [String: Int64]] = [:]
        var hourlyModels: [Date: [String: Int64]] = [:]
        var todayApps: [String: UsageTotals] = [:]
        var todayModels: [String: UsageTotals] = [:]
        var dailyAppUsage: [Date: [String: UsageTotals]] = [:]
        var dailyModelUsage: [Date: [String: UsageTotals]] = [:]
        var hourlyAppUsage: [Date: [String: UsageTotals]] = [:]
        var hourlyModelUsage: [Date: [String: UsageTotals]] = [:]
        var monthCost = 0.0

        var dailyAppRequests: [Date: [String: Int]] = [:]
        var dailyModelRequests: [Date: [String: Int]] = [:]
        var hourlyAppRequests: [Date: [String: Int]] = [:]
        var hourlyModelRequests: [Date: [String: Int]] = [:]

        for record in records {
            let day = calendar.startOfDay(for: record.createdAt)
            dailyTotals[day, default: UsageTotals()].add(
                tokens: record.tokens,
                cacheReadTokens: record.cacheReadTokens,
                cacheableTokens: record.cacheableTokens,
                costUSD: record.costUSD,
                statusCode: record.statusCode
            )
            dailyApps[day, default: [:]][record.appType, default: 0] += record.tokens
            dailyModels[day, default: [:]][record.model, default: 0] += record.tokens
            dailyAppRequests[day, default: [:]][record.appType, default: 0] += 1
            dailyModelRequests[day, default: [:]][record.model, default: 0] += 1
            dailyAppUsage[day, default: [:]][record.appType, default: UsageTotals()].add(
                tokens: record.tokens, cacheReadTokens: record.cacheReadTokens,
                cacheableTokens: record.cacheableTokens, costUSD: record.costUSD, statusCode: record.statusCode
            )
            dailyModelUsage[day, default: [:]][record.model, default: UsageTotals()].add(
                tokens: record.tokens, cacheReadTokens: record.cacheReadTokens,
                cacheableTokens: record.cacheableTokens, costUSD: record.costUSD, statusCode: record.statusCode
            )

            if record.createdAt >= ranges.monthStart { monthCost += record.costUSD }
            if day == ranges.todayStart {
                let hour = calendar.dateInterval(of: .hour, for: record.createdAt)?.start ?? record.createdAt
                hourlyTotals[hour, default: UsageTotals()].add(
                    tokens: record.tokens,
                    cacheReadTokens: record.cacheReadTokens,
                    cacheableTokens: record.cacheableTokens,
                    costUSD: record.costUSD,
                    statusCode: record.statusCode
                )
                hourlyApps[hour, default: [:]][record.appType, default: 0] += record.tokens
                hourlyModels[hour, default: [:]][record.model, default: 0] += record.tokens
                hourlyAppRequests[hour, default: [:]][record.appType, default: 0] += 1
                hourlyModelRequests[hour, default: [:]][record.model, default: 0] += 1
                hourlyAppUsage[hour, default: [:]][record.appType, default: UsageTotals()].add(
                    tokens: record.tokens, cacheReadTokens: record.cacheReadTokens,
                    cacheableTokens: record.cacheableTokens, costUSD: record.costUSD, statusCode: record.statusCode
                )
                hourlyModelUsage[hour, default: [:]][record.model, default: UsageTotals()].add(
                    tokens: record.tokens, cacheReadTokens: record.cacheReadTokens,
                    cacheableTokens: record.cacheableTokens, costUSD: record.costUSD, statusCode: record.statusCode
                )
                todayApps[record.appType, default: UsageTotals()].add(
                    tokens: record.tokens,
                    cacheReadTokens: record.cacheReadTokens,
                    cacheableTokens: record.cacheableTokens,
                    costUSD: record.costUSD,
                    statusCode: record.statusCode
                )
                todayModels[record.model, default: UsageTotals()].add(
                    tokens: record.tokens,
                    cacheReadTokens: record.cacheReadTokens,
                    cacheableTokens: record.cacheableTokens,
                    costUSD: record.costUSD,
                    statusCode: record.statusCode
                )
            }
        }

        let today = dailyTotals[ranges.todayStart] ?? UsageTotals()
        let yesterday = dailyTotals[ranges.yesterdayStart] ?? UsageTotals()
        let trendDates = dates(startingAt: ranges.trendStart, count: 30)
        let trend = trendDates.map {
            DailyUsage(
                date: $0,
                totals: dailyTotals[$0] ?? UsageTotals(),
                appTokens: dailyApps[$0] ?? [:],
                modelTokens: dailyModels[$0] ?? [:],
                appRequests: dailyAppRequests[$0] ?? [:],
                modelRequests: dailyModelRequests[$0] ?? [:],
                appUsage: dailyAppUsage[$0] ?? [:], modelUsage: dailyModelUsage[$0] ?? [:]
            )
        }
        let sixMonthTrend = dates(from: ranges.heatmapGridStart, through: ranges.todayStart).map {
            DailyUsage(
                date: $0,
                totals: dailyTotals[$0] ?? UsageTotals(),
                appTokens: dailyApps[$0] ?? [:],
                modelTokens: dailyModels[$0] ?? [:],
                appRequests: dailyAppRequests[$0] ?? [:],
                modelRequests: dailyModelRequests[$0] ?? [:],
                appUsage: dailyAppUsage[$0] ?? [:], modelUsage: dailyModelUsage[$0] ?? [:]
            )
        }
        let hourlyTrend = hourDates(startingAt: ranges.todayStart, through: ranges.now).map {
            DailyUsage(
                date: $0,
                totals: hourlyTotals[$0] ?? UsageTotals(),
                appTokens: hourlyApps[$0] ?? [:],
                modelTokens: hourlyModels[$0] ?? [:],
                appRequests: hourlyAppRequests[$0] ?? [:],
                modelRequests: hourlyModelRequests[$0] ?? [:],
                appUsage: hourlyAppUsage[$0] ?? [:], modelUsage: hourlyModelUsage[$0] ?? [:]
            )
        }
        let averageDates = dates(startingAt: ranges.averageStart, count: 7)
        let averageTokens = Double(averageDates.reduce(Int64(0)) {
            $0 + (dailyTotals[$1]?.totalTokens ?? 0)
        }) / 7

        // 前一周期 per-model token（环比口径：当天→昨日、7日→前 7-14、30日→前 30-60）
        let previousRangeModelTokens: [String: [String: Int64]] = [
            ChartRange.today.rawValue: sumModelTokens(dailyModels, from: ranges.yesterdayStart, count: 1),
            ChartRange.sevenDays.rawValue: sumModelTokens(
                dailyModels,
                from: calendar.date(byAdding: .day, value: -13, to: ranges.todayStart)!,
                count: 7
            ),
            ChartRange.thirtyDays.rawValue: sumModelTokens(
                dailyModels,
                from: ranges.extendedTrendStart,
                count: 30
            ),
        ]

        var apps: [AppUsage] = []
        apps.reserveCapacity(todayApps.count)
        for (key, totals) in todayApps {
            apps.append(AppUsage(
                id: key,
                totals: totals,
                share: today.totalTokens == 0 ? 0 : Double(totals.totalTokens) / Double(today.totalTokens),
                trendTokens: trend.map { $0.appTokens[key] ?? 0 }
            ))
        }
        apps.sort {
            $0.totalTokens == $1.totalTokens ? $0.id < $1.id : $0.totalTokens > $1.totalTokens
        }

        var models: [ModelUsage] = []
        models.reserveCapacity(todayModels.count)
        for (key, totals) in todayModels {
            models.append(ModelUsage(
                id: key,
                totals: totals,
                share: today.totalTokens == 0 ? 0 : Double(totals.totalTokens) / Double(today.totalTokens)
            ))
        }
        models.sort {
            $0.totalTokens == $1.totalTokens ? $0.id < $1.id : $0.totalTokens > $1.totalTokens
        }

        return UsageSnapshot(
            generatedAt: ranges.now,
            today: today,
            yesterday: yesterday,
            sevenDayAverageTokens: averageTokens,
            hourlyTrend: hourlyTrend,
            trend: trend,
            sixMonthTrend: sixMonthTrend,
            apps: apps,
            models: models,
            monthCostUSD: monthCost,
            previousRangeModelTokens: previousRangeModelTokens
        )
    }

    /// 累加从 start 起 count 个自然日里每个模型的 token 总和（用于前一周期环比）。
    private func sumModelTokens(_ dailyModels: [Date: [String: Int64]], from start: Date, count: Int) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for offset in 0 ..< count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for (model, tokens) in dailyModels[day] ?? [:] {
                result[model, default: 0] += tokens
            }
        }
        return result
    }

    private func dates(startingAt start: Date, count: Int) -> [Date] {
        (0 ..< count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dates(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func hourDates(startingAt start: Date, through end: Date) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }
}

private struct LogRecord {
    let appType: String
    let model: String
    let tokens: Int64
    let cacheReadTokens: Int64
    let cacheableTokens: Int64
    let costUSD: Double
    let statusCode: Int
    let createdAt: Date
}

private func columnString(_ statement: OpaquePointer, index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: text)
}

private func errorMessage(_ database: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(database))
}

private func normalized(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func resolvedModel(pricing: String, request: String, raw: String) -> String {
    for candidate in [pricing, request, raw] {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return "未知模型"
}
