import Foundation
import JavaScriptCore

/// cc-switch providers 表里读出的一个 provider 连接配置。
public struct ProviderConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let appType: String
    public let baseUrl: String
    public let apiKey: String
    /// cc-switch provider meta.usage_script.code（JS IIFE：{request, extractor}），可选。
    public let usageScriptCode: String?
    public let iconName: String?

    public init(id: String, name: String, appType: String, baseUrl: String, apiKey: String, usageScriptCode: String? = nil, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.appType = appType
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.usageScriptCode = usageScriptCode
        self.iconName = iconName
    }
}

public struct ProviderUsageQueryPolicy: Equatable, Sendable {
    public let id: String
    public let name: String
    public let appType: String
    public let isEnabled: Bool
    public let templateType: String?
    public let iconName: String?

    public init(id: String, name: String, appType: String, isEnabled: Bool, templateType: String? = nil, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.appType = appType
        self.isEnabled = isEnabled
        self.templateType = templateType
        self.iconName = iconName
    }
}

/// 单个限速窗口（如 5h 会话、7天周期）。与 cc-switch QuotaTier 对齐。
public struct QuotaTier: Codable, Equatable, Sendable, Identifiable {
    public let name: String        // five_hour / seven_day / 30_day 等
    public let utilization: Double // 0–100 已用百分比
    public let resetsAt: Date?     // 重置时间
    public var id: String { name }

    public init(name: String, utilization: Double, resetsAt: Date? = nil) {
        self.name = name
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public enum ProviderQuotaPeriod: Equatable, Sendable {
    case fiveHour, week
}

public enum ProviderQuotaPresentation {
    public static func tier(for period: ProviderQuotaPeriod, in tiers: [QuotaTier]) -> QuotaTier? {
        let names: Set<String>
        switch period {
        case .fiveHour: names = ["five_hour", "primary_window", "5h"]
        case .week: names = ["seven_day", "weekly_limit", "secondary_window", "week"]
        }
        return tiers.first { names.contains($0.name.lowercased()) }
    }

    public static func percent(for tier: QuotaTier, mode: ProviderQuotaDisplayMode) -> Double {
        let used = min(max(tier.utilization, 0), 100)
        return mode == .used ? used : 100 - used
    }

    public static func resetText(for tier: QuotaTier, period: ProviderQuotaPeriod, now: Date) -> String {
        guard let resetsAt = tier.resetsAt else { return "暂无数据" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "待刷新" }
        switch period {
        case .fiveHour:
            let minutes = Int(seconds / 60)
            guard minutes > 0 else { return "<1min" }
            let hours = minutes / 60
            let remainder = minutes % 60
            if hours == 0 { return "\(minutes)min" }
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)min"
        case .week:
            let hours = Int(seconds / 3600)
            guard hours > 0 else { return "<1h" }
            let days = hours / 24
            let remainder = hours % 24
            if days == 0 { return "\(hours)h" }
            return remainder == 0 ? "\(days)d" : "\(days)d \(remainder)h"
        }
    }
}

public enum CredentialStatus: String, Codable, Sendable {
    case valid, expired, notFound, parseError
}

public enum ProviderBalanceKind: String, Codable, Sendable {
    case balance       // provider 余额（单值）
    case claudeOAuth   // Claude 官方 OAuth
    case codexOAuth    // Codex/ChatGPT 官方 OAuth
}

public struct ExtraUsage: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?
    public let currency: String?

    public init(isEnabled: Bool, monthlyLimit: Double? = nil, usedCredits: Double? = nil, utilization: Double? = nil, currency: String? = nil) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
        self.currency = currency
    }
}

/// 余额/额度查询结果：单值（余额类）或多 tier（OAuth/订阅类）统一结构。
public struct ProviderBalance: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let appType: String
    // 单值（余额类）
    public let remaining: Double?
    public let total: Double?
    public let used: Double?
    public let unit: String
    public let isValid: Bool
    public let errorMessage: String?
    public let queriedAt: Date
    // 多 tier（OAuth/订阅类）
    public let tiers: [QuotaTier]
    public let kind: ProviderBalanceKind
    public let credentialStatus: CredentialStatus?
    public let extraUsage: ExtraUsage?
    public let iconName: String?

    public init(
        id: String? = nil,
        name: String,
        appType: String,
        remaining: Double? = nil,
        total: Double? = nil,
        used: Double? = nil,
        unit: String = "—",
        isValid: Bool = true,
        errorMessage: String? = nil,
        queriedAt: Date,
        tiers: [QuotaTier] = [],
        kind: ProviderBalanceKind = .balance,
        credentialStatus: CredentialStatus? = nil,
        extraUsage: ExtraUsage? = nil,
        iconName: String? = nil
    ) {
        self.id = id ?? "\(name)-\(appType)-\(kind.rawValue)"
        self.name = name
        self.appType = appType
        self.remaining = remaining
        self.total = total
        self.used = used
        self.unit = unit
        self.isValid = isValid
        self.errorMessage = errorMessage
        self.queriedAt = queriedAt
        self.tiers = tiers
        self.kind = kind
        self.credentialStatus = credentialStatus
        self.extraUsage = extraUsage
        self.iconName = iconName
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appType, remaining, total, used, unit, isValid, errorMessage, queriedAt
        case tiers, kind, credentialStatus, extraUsage, iconName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        appType = try c.decode(String.self, forKey: .appType)
        remaining = try c.decodeIfPresent(Double.self, forKey: .remaining)
        total = try c.decodeIfPresent(Double.self, forKey: .total)
        used = try c.decodeIfPresent(Double.self, forKey: .used)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "—"
        isValid = try c.decodeIfPresent(Bool.self, forKey: .isValid) ?? true
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        queriedAt = try c.decode(Date.self, forKey: .queriedAt)
        tiers = try c.decodeIfPresent([QuotaTier].self, forKey: .tiers) ?? []
        kind = try c.decodeIfPresent(ProviderBalanceKind.self, forKey: .kind) ?? .balance
        credentialStatus = try c.decodeIfPresent(CredentialStatus.self, forKey: .credentialStatus)
        extraUsage = try c.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "\(name)-\(appType)-\(kind.rawValue)"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(appType, forKey: .appType)
        try c.encodeIfPresent(remaining, forKey: .remaining)
        try c.encodeIfPresent(total, forKey: .total)
        try c.encodeIfPresent(used, forKey: .used)
        try c.encode(unit, forKey: .unit)
        try c.encode(isValid, forKey: .isValid)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encode(queriedAt, forKey: .queriedAt)
        try c.encode(tiers, forKey: .tiers)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(credentialStatus, forKey: .credentialStatus)
        try c.encodeIfPresent(extraUsage, forKey: .extraUsage)
        try c.encodeIfPresent(iconName, forKey: .iconName)
    }
}

public extension ProviderBalance {
    func withProviderMetadata(id: String, name: String, appType: String, iconName: String?) -> ProviderBalance {
        ProviderBalance(
            id: id, name: name, appType: appType,
            remaining: remaining, total: total, used: used, unit: unit,
            isValid: isValid, errorMessage: errorMessage, queriedAt: queriedAt,
            tiers: tiers, kind: kind, credentialStatus: credentialStatus,
            extraUsage: extraUsage, iconName: iconName
        )
    }
}

public enum ProviderBalanceMerge {
    public static func merge(previous: [ProviderBalance], refreshed: [ProviderBalance]) -> [ProviderBalance] {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return refreshed.map { current in
            guard !current.isValid, let old = oldByID[current.id], old.isValid else { return current }
            return ProviderBalance(
                id: old.id, name: current.name, appType: current.appType,
                remaining: old.remaining, total: old.total, used: old.used, unit: old.unit,
                isValid: old.isValid, errorMessage: current.errorMessage, queriedAt: old.queriedAt,
                tiers: old.tiers, kind: old.kind, credentialStatus: current.credentialStatus ?? old.credentialStatus,
                extraUsage: old.extraUsage, iconName: current.iconName ?? old.iconName
            )
        }
    }
}

/// provider 余额查询服务：移植自 cc-switch src-tauri/src/services/balance.rs。
/// 支持 DeepSeek / StepFun / SiliconFlow(中/英) / OpenRouter / Novita AI。
/// 通过 `detectProvider(baseUrl)` 路由到各家余额接口，Bearer 鉴权 + JSON 提取。
public struct ProviderBalanceService: Sendable {
    public init() {}

    private enum BalanceProvider: String {
        case deepseek, stepfun, siliconflow, siliconflowEn, openrouter, novita, zhipu
    }

    private func detectProvider(_ baseUrl: String) -> BalanceProvider? {
        let url = baseUrl.lowercased()
        if url.contains("api.deepseek.com") { return .deepseek }
        if url.contains("api.stepfun.ai") || url.contains("api.stepfun.com") { return .stepfun }
        if url.contains("api.siliconflow.cn") { return .siliconflow }
        if url.contains("api.siliconflow.com") { return .siliconflowEn }
        if url.contains("openrouter.ai") { return .openrouter }
        if url.contains("api.novita.ai") { return .novita }
        if url.contains("bigmodel.cn") || url.contains("z.ai") { return .zhipu }
        return nil
    }

    /// 查询余额。成功/确定性失败都返回 ProviderBalance（errorMessage 体现失败原因）；
    /// 网络层瞬时失败也落到 errorMessage（调用方决定是否保留上次值）。
    public func getBalance(name: String, appType: String, baseUrl: String, apiKey: String, now: Date, usageScriptCode: String? = nil, iconName: String? = nil) async -> ProviderBalance {
        let common = { (remaining: Double?, total: Double?, used: Double?, unit: String, valid: Bool, err: String?) in
            ProviderBalance(name: name, appType: appType, remaining: remaining, total: total, used: used, unit: unit, isValid: valid, errorMessage: err, queriedAt: now, iconName: iconName)
        }

        if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            return common(nil, nil, nil, "—", false, "API key 为空")
        }
        // 优先用 cc-switch meta.usage_script（自定义余额脚本），其次 detect_provider。
        if let code = usageScriptCode, !code.isEmpty {
            return await queryUsageScript(code: code, baseUrl: baseUrl, apiKey: apiKey, name: name, appType: appType, now: now)
        }
        guard let provider = detectProvider(baseUrl) else {
            return common(nil, nil, nil, "—", false, "未知余额查询供应商")
        }

        switch provider {
        case .deepseek:
            return await queryGet(
                url: "https://api.deepseek.com/user/balance",
                apiKey: apiKey, name: name, appType: appType, now: now, unit: "CNY"
            ) { body in
                // balance_infos[].total_balance
                let isAvailable = (body["is_available"] as? Bool) ?? true
                guard let infos = body["balance_infos"] as? [[String: Any]], let info = infos.first else {
                    return (nil, nil, nil, "CNY", isAvailable, nil)
                }
                let currency = (info["currency"] as? String) ?? "CNY"
                let total = parseDouble(info["total_balance"])
                return (total, nil, nil, currency, isAvailable, isAvailable ? nil : "余额不足")
            }
        case .stepfun:
            return await queryGet(
                url: "https://api.stepfun.com/v1/accounts",
                apiKey: apiKey, name: name, appType: appType, now: now, unit: "CNY"
            ) { body in
                let balance = parseDouble(body["balance"]) ?? 0
                return (balance, nil, nil, "CNY", true, nil)
            }
        case .siliconflow:
            return await querySiliconflow(isCn: true, apiKey: apiKey, name: name, appType: appType, now: now)
        case .siliconflowEn:
            return await querySiliconflow(isCn: false, apiKey: apiKey, name: name, appType: appType, now: now)
        case .openrouter:
            return await queryGet(
                url: "https://openrouter.ai/api/v1/credits",
                apiKey: apiKey, name: name, appType: appType, now: now, unit: "USD"
            ) { body in
                let data = (body["data"] as? [String: Any]) ?? body
                let totalCredits = parseDouble(data["total_credits"]) ?? 0
                let totalUsage = parseDouble(data["total_usage"]) ?? 0
                let remaining = totalCredits - totalUsage
                return (remaining, totalCredits, totalUsage, "USD", remaining > 0, remaining > 0 ? nil : "无可用额度")
            }
        case .novita:
            return await queryGet(
                url: "https://api.novita.ai/v3/user/balance",
                apiKey: apiKey, name: name, appType: appType, now: now, unit: "USD"
            ) { body in
                // Novita 金额单位 0.0001 USD
                let available = (parseDouble(body["availableBalance"]) ?? 0) / 10000.0
                return (available, nil, nil, "USD", available > 0, available > 0 ? nil : "无可用余额")
            }
        case .zhipu:
            // 智谱 token 套餐额度（5h/周 tiers），裸 key 鉴权，移植 cc-switch coding_plan parse_zhipu_token_tiers。
            return await queryZhipu(baseUrl: baseUrl, apiKey: apiKey, name: name, appType: appType, now: now)
        }
    }

    /// SiliconFlow：data.totalBalance，中/英域名 + 货币不同。
    private func querySiliconflow(isCn: Bool, apiKey: String, name: String, appType: String, now: Date) async -> ProviderBalance {
        let domain = isCn ? "api.siliconflow.cn" : "api.siliconflow.com"
        let unit = isCn ? "CNY" : "USD"
        return await queryGet(
            url: "https://\(domain)/v1/user/info",
            apiKey: apiKey, name: name, appType: appType, now: now, unit: unit
        ) { body in
            guard let data = body["data"] as? [String: Any] else { return (nil, nil, nil, unit, false, "响应缺少 data 字段") }
            let total = parseDouble(data["totalBalance"]) ?? 0
            return (total, nil, nil, unit, true, nil)
        }
    }

    /// 智谱 token 套餐额度（移植 cc-switch coding_plan query_zhipu + parse_zhipu_token_tiers）。
    /// limits[] 中 type==TOKENS_LIMIT 的条目，按 unit 分 5h(3)/周(6)，取 percentage（utilization%）+ nextResetTime（毫秒）。
    private func queryZhipu(baseUrl: String, apiKey: String, name: String, appType: String, now: Date) async -> ProviderBalance {
        let base = zhipuBase(baseUrl)
        var request = URLRequest(url: URL(string: "\(base)/monitor/usage/quota/limit")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization") // 裸 key
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "鉴权失败 (HTTP \(status))", queriedAt: now)
            }
            if !(200..<300).contains(status) {
                return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "API 错误 (HTTP \(status))", queriedAt: now)
            }
            guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "响应解析失败", queriedAt: now)
            }
            if (body["success"] as? Bool) == false {
                let msg = (body["msg"] as? String) ?? "未知错误"
                return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "API 错误: \(msg)", queriedAt: now)
            }
            guard let dataObj = body["data"] as? [String: Any] else {
                return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "响应缺少 data", queriedAt: now)
            }

            let limits = (dataObj["limits"] as? [[String: Any]]) ?? []
            var tiers: [QuotaTier] = []
            for item in limits {
                guard ((item["type"] as? String) ?? "").uppercased() == "TOKENS_LIMIT" else { continue }
                guard let percentage = parseDouble(item["percentage"]) else { continue }
                let unitVal = Int(parseDouble(item["unit"]) ?? 0)
                let tierName: String
                switch unitVal {
                case 3: tierName = "five_hour"
                case 6: tierName = "weekly_limit"
                default: continue
                }
                let resetsAt = parseDouble(item["nextResetTime"]).map { Date(timeIntervalSince1970: $0 / 1000) }
                tiers.append(QuotaTier(name: tierName, utilization: percentage, resetsAt: resetsAt))
            }

            return ProviderBalance(name: name, appType: appType, unit: "%", isValid: true, queriedAt: now, tiers: tiers, kind: .balance)
        } catch {
            return ProviderBalance(name: name, appType: appType, unit: "%", isValid: false, errorMessage: "网络错误: \(error.localizedDescription)", queriedAt: now)
        }
    }

    /// 智谱额度接口 host：bigmodel.cn → open.bigmodel.cn/api，z.ai → api.z.ai/api。
    private func zhipuBase(_ baseUrl: String) -> String {
        baseUrl.lowercased().contains("bigmodel.cn") ? "https://open.bigmodel.cn/api" : "https://api.z.ai/api"
    }

    /// 通用 GET + JSON 提取。extractor 返回 (remaining, total, used, unit, isValid, error)。
    /// bearer=true 用 "Bearer <key>"，false 用裸 key（智谱）。
    private func queryGet(
        url: String,
        apiKey: String,
        name: String,
        appType: String,
        now: Date,
        unit: String,
        bearer: Bool = true,
        extractor: @escaping ([String: Any]) -> (Double?, Double?, Double?, String, Bool, String?)
    ) async -> ProviderBalance {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(bearer ? "Bearer \(apiKey)" : apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: unit, isValid: false, errorMessage: "鉴权失败 (HTTP \(status))", queriedAt: now)
            }
            if !(200..<300).contains(status) {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: unit, isValid: false, errorMessage: "API 错误 (HTTP \(status)): \(body)", queriedAt: now)
            }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: unit, isValid: false, errorMessage: "响应解析失败", queriedAt: now)
            }
            let parsed = extractor(body)
            return ProviderBalance(name: name, appType: appType, remaining: parsed.0, total: parsed.1, used: parsed.2, unit: parsed.3, isValid: parsed.4, errorMessage: parsed.5, queriedAt: now)
        } catch {
            return ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: unit, isValid: false, errorMessage: "网络错误: \(error.localizedDescription)", queriedAt: now)
        }
    }

    /// 兼容数字和字符串格式的 JSON 字段解析。
    private func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// 执行 cc-switch meta.usage_script：解析 {request, extractor}，发请求，用 JSContext 跑 extractor。
    /// 任何配了 usage_script 的 provider 都走这里，不需逐家硬编码。
    private func queryUsageScript(code: String, baseUrl: String, apiKey: String, name: String, appType: String, now: Date) async -> ProviderBalance {
        let fail = { (msg: String) in
            ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: "—", isValid: false, errorMessage: msg, queriedAt: now)
        }

        guard let context = JSContext() else { return fail("无法创建 JSContext") }
        var jsError: String?
        context.exceptionHandler = { _, value in jsError = value?.toString() }
        guard let script = context.evaluateScript(code),
              let request = script.forProperty("request"),
              let extractor = script.forProperty("extractor") else {
            return fail("usage_script 解析失败: \(jsError ?? "结构非法")")
        }

        let urlTemplate = request.forProperty("url")?.toString() ?? ""
        let urlString = urlTemplate
            .replacingOccurrences(of: "{{baseUrl}}", with: baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .replacingOccurrences(of: "{{apiKey}}", with: apiKey)
        guard let url = URL(string: urlString) else { return fail("无效 URL: \(urlString)") }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.forProperty("method")?.toString() ?? "GET"
        urlRequest.timeoutInterval = 15
        if let headers = request.forProperty("headers"), headers.hasProperty("Authorization") {
            let auth = headers.forProperty("Authorization")?.toString() ?? ""
            urlRequest.setValue(auth.replacingOccurrences(of: "{{apiKey}}", with: apiKey), forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderBalance(name: name, appType: appType, remaining: nil, total: nil, used: nil, unit: "—", isValid: false, errorMessage: "鉴权失败 (HTTP \(status))", queriedAt: now)
            }
            if !(200..<300).contains(status) { return fail("API 错误 (HTTP \(status))") }
            guard let body = try? JSONSerialization.jsonObject(with: data) else { return fail("响应解析失败") }
            guard let result = extractor.call(withArguments: [body]) else { return fail("extractor 调用失败: \(jsError ?? "")") }
            let remainingDouble = result.forProperty("remaining")?.toNumber()?.doubleValue ?? Double.nan
            let remaining: Double? = remainingDouble.isNaN ? nil : remainingDouble
            let unit = result.forProperty("unit")?.toString() ?? "USD"
            let isValid = result.forProperty("isValid")?.toBool() ?? true
            return ProviderBalance(name: name, appType: appType, remaining: remaining, total: nil, used: nil, unit: unit, isValid: isValid, errorMessage: nil, queriedAt: now)
        } catch {
            return fail("网络错误: \(error.localizedDescription)")
        }
    }

    // MARK: - Claude/Codex OAuth 额度查询

    /// 查询 Claude 官方订阅额度（移植 cc-switch query_claude_quota）。
    public func getClaudeQuota(accessToken: String, now: Date) async -> ProviderBalance {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderBalance(name: "Claude Official", appType: "claude", unit: "—", isValid: false, errorMessage: "凭据过期 (HTTP \(status))，请用 Claude CLI 重新登录", queriedAt: now, kind: .claudeOAuth, credentialStatus: .expired)
            }
            if !(200..<300).contains(status) {
                return ProviderBalance(name: "Claude Official", appType: "claude", unit: "—", isValid: false, errorMessage: "API 错误 (HTTP \(status))", queriedAt: now, kind: .claudeOAuth, credentialStatus: .valid)
            }
            guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderBalance(name: "Claude Official", appType: "claude", unit: "—", isValid: false, errorMessage: "响应解析失败", queriedAt: now, kind: .claudeOAuth)
            }

            let knownTiers = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]
            var tiers: [QuotaTier] = []
            for tierName in knownTiers {
                if let window = body[tierName] as? [String: Any],
                   let utilization = parseDouble(window["utilization"]) {
                    let resetsAt = (window["resets_at"] as? String).flatMap(isoDate)
                    tiers.append(QuotaTier(name: tierName, utilization: utilization, resetsAt: resetsAt))
                }
            }
            for (key, value) in body {
                if key == "extra_usage" || knownTiers.contains(key) { continue }
                if let window = value as? [String: Any], let utilization = parseDouble(window["utilization"]) {
                    let resetsAt = (window["resets_at"] as? String).flatMap(isoDate)
                    tiers.append(QuotaTier(name: key, utilization: utilization, resetsAt: resetsAt))
                }
            }

            var extra: ExtraUsage?
            if let extraBody = body["extra_usage"] as? [String: Any] {
                extra = ExtraUsage(
                    isEnabled: (extraBody["is_enabled"] as? Bool) ?? false,
                    monthlyLimit: parseDouble(extraBody["monthly_limit"]),
                    usedCredits: parseDouble(extraBody["used_credits"]),
                    utilization: parseDouble(extraBody["utilization"]),
                    currency: extraBody["currency"] as? String
                )
            }

            return ProviderBalance(name: "Claude Official", appType: "claude", unit: "%", isValid: true, queriedAt: now, tiers: tiers, kind: .claudeOAuth, credentialStatus: .valid, extraUsage: extra)
        } catch {
            return ProviderBalance(name: "Claude Official", appType: "claude", unit: "—", isValid: false, errorMessage: "网络错误: \(error.localizedDescription)", queriedAt: now, kind: .claudeOAuth)
        }
    }

    /// 查询 Codex/ChatGPT 官方订阅额度（移植 cc-switch query_codex_quota）。
    public func getCodexQuota(accessToken: String, accountId: String?, now: Date) async -> ProviderBalance {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId { request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderBalance(name: "OpenAI Official", appType: "codex", unit: "—", isValid: false, errorMessage: "凭据过期 (HTTP \(status))", queriedAt: now, kind: .codexOAuth, credentialStatus: .expired)
            }
            if !(200..<300).contains(status) {
                return ProviderBalance(name: "OpenAI Official", appType: "codex", unit: "—", isValid: false, errorMessage: "API 错误 (HTTP \(status))", queriedAt: now, kind: .codexOAuth, credentialStatus: .valid)
            }
            guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimit = body["rate_limit"] as? [String: Any] else {
                return ProviderBalance(name: "OpenAI Official", appType: "codex", unit: "—", isValid: false, errorMessage: "响应解析失败", queriedAt: now, kind: .codexOAuth)
            }

            var tiers: [QuotaTier] = []
            for windowKey in ["primary_window", "secondary_window"] {
                guard let window = rateLimit[windowKey] as? [String: Any],
                      let usedPercent = parseDouble(window["used_percent"]) else { continue }
                let limitSeconds = Int(parseDouble(window["limit_window_seconds"]) ?? 0)
                let tierName = windowSecondsToTierName(limitSeconds)
                let resetsAt = parseDouble(window["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                tiers.append(QuotaTier(name: tierName, utilization: usedPercent, resetsAt: resetsAt))
            }

            return ProviderBalance(name: "OpenAI Official", appType: "codex", unit: "%", isValid: true, queriedAt: now, tiers: tiers, kind: .codexOAuth, credentialStatus: .valid)
        } catch {
            return ProviderBalance(name: "OpenAI Official", appType: "codex", unit: "—", isValid: false, errorMessage: "网络错误: \(error.localizedDescription)", queriedAt: now, kind: .codexOAuth)
        }
    }

    /// 秒→tier 名（照搬 cc-switch window_seconds_to_tier_name）。
    private func windowSecondsToTierName(_ seconds: Int) -> String {
        switch seconds {
        case 18000: return "five_hour"
        case 604800: return "seven_day"
        case 2_592_000: return "30_day"
        default:
            let hours = seconds / 3600
            return hours >= 24 ? "\(hours / 24)_day" : "\(hours)_hour"
        }
    }

    /// tier 名→中文显示（Core 层，widget 可复用）。
    public static func tierDisplayName(_ name: String) -> String {
        switch name {
        case "five_hour": return "5小时"
        case "seven_day", "weekly_limit": return "7天"
        case "30_day", "monthly": return "30天"
        case let s where s.hasSuffix("_day"): return "\(s.dropLast(4))天"
        case let s where s.hasSuffix("_hour"): return "\(s.dropLast(5))小时"
        default: return name
        }
    }

    /// ISO 8601 字符串→Date。
    private func isoDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
