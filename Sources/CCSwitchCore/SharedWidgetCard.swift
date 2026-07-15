import Charts
import AppKit
import SwiftUI
import WidgetKit

/// App、Widget 与菜单栏共同使用的不可变卡片输入。
/// 渲染层不读取数据库、UserDefaults 或 AppModel。
public struct CardRenderModel: Sendable {
    public let module: DashboardModule
    public let snapshot: UsageSnapshot
    public let balances: [ProviderBalance]
    public let themeMode: ThemeMode
    public let movementColorMode: MovementColorMode
    public let customPalette: [UInt32]
    public let customMovementColors: [UInt32]
    public let message: String?
    public let renderedAt: Date
    public let unavailableMessage: String?

    public init(
        module: DashboardModule,
        snapshot: UsageSnapshot,
        balances: [ProviderBalance] = [],
        themeMode: ThemeMode,
        movementColorMode: MovementColorMode,
        customPalette: [UInt32] = CustomPalette.defaultHexes,
        customMovementColors: [UInt32] = CustomPalette.defaultMovementHexes,
        message: String? = nil,
        renderedAt: Date = Date(),
        unavailableMessage: String? = nil
    ) {
        self.module = module
        self.snapshot = snapshot
        self.balances = balances
        self.themeMode = themeMode
        self.movementColorMode = movementColorMode
        self.customPalette = customPalette
        self.customMovementColors = customMovementColors
        self.message = message
        self.renderedAt = renderedAt
        self.unavailableMessage = unavailableMessage
    }

    public var shouldRenderContent: Bool { unavailableMessage == nil }
}

public enum SharedCardSurface: Equatable, Sendable {
    case app
    case widget
}

public struct SharedWidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private let model: CardRenderModel
    private let surface: SharedCardSurface
    private let onQuotaModeChange: ((ProviderQuotaDisplayMode) -> Void)?

    public init(
        model: CardRenderModel,
        surface: SharedCardSurface,
        onQuotaModeChange: ((ProviderQuotaDisplayMode) -> Void)? = nil
    ) {
        self.model = model
        self.surface = surface
        self.onQuotaModeChange = onQuotaModeChange
    }

    public var body: some View {
        let palette = SharedCardPalette(model: model, colorScheme: colorScheme)
        Group {
            if model.shouldRenderContent {
                card(palette: palette)
            } else {
                unavailableCard(palette: palette)
            }
        }
            .foregroundStyle(palette.primaryText)
            .background {
                if surface == .app {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(palette.background)
                }
            }
            .overlay {
                if surface == .app {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(palette.separator.opacity(0.55), lineWidth: 1)
                }
            }
            .shadow(color: surface == .app ? .black.opacity(palette.isDark ? 0.24 : 0.10) : .clear, radius: 10, y: 4)
            .containerBackground(for: .widget) { palette.background }
    }

    private func unavailableCard(palette: SharedCardPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.module.kind.title)
                .font(.system(size: model.module.size == .small ? 13 : 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "rectangle.slash")
                .font(.system(size: model.module.size == .small ? 22 : 28, weight: .semibold))
                .foregroundStyle(palette.warning)
            Text(model.unavailableMessage ?? "此卡片当前不可用")
                .font(.system(size: model.module.size == .small ? 12 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(WidgetPresentationMetrics.insets(for: model.module.size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetAccentable(false)
    }

    private func card(palette: SharedCardPalette) -> some View {
        VStack(alignment: .leading, spacing: WidgetPresentationMetrics.titleSpacing(for: model.module.size)) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(.system(size: model.module.size == .small ? 13 : 14, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 4)
                if model.module.kind == .providerBalances {
                    quotaModeControl
                }
                Text(CardUpdateTimeFormatter.string(from: updateDate, now: model.renderedAt))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText.opacity(0.62))
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            content(palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let message = model.message {
                Text(message).font(.caption2).foregroundStyle(palette.warning).lineLimit(2)
            }
        }
        .padding(WidgetPresentationMetrics.insets(for: model.module.size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetAccentable(false)
    }

    @ViewBuilder private func content(palette: SharedCardPalette) -> some View {
        switch model.module.kind {
        case .todayOverview: todayOverview(palette)
        case .averageComparison: averageComparison(palette)
        case .appCard: appCard(palette)
        case .topModel: topModel(palette)
        case .modelRanking: modelRanking(palette)
        case .usageTrend: usageTrend(palette)
        case .usageHeatmap: usageHeatmap(palette)
        case .costOverview: costOverview(palette)
        case .providerBalances: providerBalances(palette)
        }
    }

    private func todayOverview(_ palette: SharedCardPalette) -> some View {
        let today = model.snapshot.today
        let yesterday = model.snapshot.yesterday.totalTokens
        return VStack(alignment: .leading, spacing: 0) {
            Text(cardTokens(today.totalTokens)).font(.system(size: 29, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.58)
            Spacer(minLength: 6)
            Text("昨日 \(cardTokens(yesterday))").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                SharedMetric(label: "环比", value: cardDelta(today.totalTokens, yesterday), palette: palette)
                SharedMetric(label: "请求", value: "\(today.requestCount)", palette: palette)
            }
        }
    }

    private func averageComparison(_ palette: SharedCardPalette) -> some View {
        let today = Double(model.snapshot.today.totalTokens)
        let average = model.snapshot.sevenDayAverageTokens
        let change = average == 0 ? 0 : today / average - 1
        return VStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 4)
            Text(cardTokens(Int64(today))).font(.system(size: 31, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.56)
            Spacer(minLength: 10)
            GeometryReader { proxy in
                let ratio = average == 0 ? 0 : min(max(today / average, 0), 1.5)
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track.opacity(0.82))
                    Capsule().fill(ratio <= 1 ? palette.down : palette.up)
                        .frame(width: max(8, proxy.size.width * min(ratio / 1.5, 1)))
                }
            }.frame(height: 8)
            Spacer(minLength: 10)
            HStack(alignment: .bottom, spacing: 6) {
                SharedMetric(label: "均值", value: cardTokens(Int64(average)), palette: palette)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(change <= 0 ? "低于均值" : "高于均值")
                    Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(change <= 0 ? palette.down : palette.up)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func appCard(_ palette: SharedCardPalette) -> some View {
        let appID = configuredAppID
        let range = configuredRange
        let summary = model.snapshot.appSummary(id: appID, for: range)
        let buckets = model.snapshot.buckets(for: range)
        return VStack(alignment: .leading, spacing: 0) {
            Text(cardTokens(summary.totalTokens)).font(.system(size: 27, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.56)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Text(cardPercent(summary.share)).font(.caption.weight(.semibold))
                Text("区间占比").font(.caption2).foregroundStyle(palette.secondaryText)
            }.lineLimit(1)
            UsageMiniLineVisualization(
                buckets: buckets, seriesID: appID, scope: .byTool, range: range,
                color: palette.accent, palette: palette.visualization,
                supportsHover: surface == .app
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func topModel(_ palette: SharedCardPalette) -> some View {
        let top = model.snapshot.models.first
        return VStack(alignment: .leading, spacing: 0) {
            Text(top?.id ?? "暂无模型").font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 5)
            Text(cardTokens(top?.totalTokens ?? 0)).font(.system(size: 29, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.56)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                SharedMetric(label: "占比", value: cardPercent(top?.share ?? 0), palette: palette)
                SharedMetric(label: "命中", value: cardPercent(top?.cacheHitRate ?? 0), palette: palette)
                SharedMetric(label: "请求", value: "\(top?.totals.requestCount ?? 0)", palette: palette)
            }
        }
    }

    private func modelRanking(_ palette: SharedCardPalette) -> some View {
        let range = configuredRange
        let buckets = model.snapshot.buckets(for: range)
        let limit = model.module.size == .large ? 6 : 3
        let models = Array(model.snapshot.modelSummaries(for: range).prefix(limit))
        return VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.id).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                        Text("\(cardPercent(item.share)) 区间占比").font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.secondaryText).lineLimit(1)
                    }.frame(width: 126, alignment: .leading)
                    UsageMiniLineVisualization(
                        buckets: buckets, seriesID: item.id, scope: .byModel, range: range,
                        color: palette.series(index), palette: palette.visualization,
                        supportsHover: surface == .app
                    )
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    Text(cardTokens(item.totalTokens)).font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1).frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, model.module.size == .large ? 5 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                if index < models.count - 1 { Rectangle().fill(palette.separator).frame(height: 1) }
            }
        }
    }

    private func usageTrend(_ palette: SharedCardPalette) -> some View {
        let range = configuredRange
        return UsageTrendVisualization(
            buckets: model.snapshot.buckets(for: range),
            projection: model.snapshot.analysis[range],
            scope: model.module.trendScope,
            style: configuredTrendStyle,
            palette: palette.visualization,
            supportsHover: surface == .app,
            showsLegend: true,
            selectedModelIDs: model.module.trendModelIDs,
            selectedModelsInitialized: model.module.trendModelSelectionInitialized
        )
    }

    private func costOverview(_ palette: SharedCardPalette) -> some View {
        let today = model.snapshot.today.costUSD
        let yesterday = model.snapshot.yesterday.costUSD
        return VStack(alignment: .leading, spacing: 0) {
            Text(cardUSD(today)).font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.52)
            Spacer(minLength: 6)
            Text("昨日 \(cardUSD(yesterday))").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText).lineLimit(1).minimumScaleFactor(0.68)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                SharedMetric(label: "环比", value: cardSignedPercent(yesterday == 0 ? 0 : today / yesterday - 1), palette: palette)
                SharedMetric(label: "本月", value: cardUSD(model.snapshot.monthCostUSD), palette: palette)
            }
        }
    }

    private func usageHeatmap(_ palette: SharedCardPalette) -> some View {
        UsageHeatmapVisualization(
            days: model.snapshot.sixMonthTrend,
            levels: model.snapshot.analysis.heatmapLevels,
            palette: palette.visualization,
            supportsHover: surface == .app
        )
    }

    private func providerBalances(_ palette: SharedCardPalette) -> some View {
        let limit = model.module.size == .large ? 6 : 3
        return Group {
            if model.balances.isEmpty {
                Text("暂无账户数据").font(.caption).foregroundStyle(palette.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.balances.prefix(limit)) { balance in
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                if model.module.showsProviderIcons {
                                    ProviderIconView(balance: balance, color: palette.primaryText)
                                }
                                Text(balance.name).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.secondaryText.opacity(0.12)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let remaining = balance.remaining {
                                Text(String(format: "%.2f %@", remaining, balance.unit)).font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1).minimumScaleFactor(0.65)
                            } else {
                                quotaValue(balance, period: .fiveHour, label: "5h", palette: palette)
                                quotaValue(balance, period: .week, label: "Week", palette: palette)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if balance.id != model.balances.prefix(limit).last?.id {
                            Rectangle().fill(palette.separator).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var quotaModeControl: some View {
        let mode = model.module.providerQuotaDisplayMode
        return Group {
            if let onQuotaModeChange {
                Button(mode == .used ? "已使用" : "剩余") {
                    onQuotaModeChange(mode == .used ? .remaining : .used)
                }
                .buttonStyle(.plain)
            } else {
                Text(mode == .used ? "已使用" : "剩余")
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
    }

    private func quotaValue(
        _ balance: ProviderBalance,
        period: ProviderQuotaPeriod,
        label: String,
        palette: SharedCardPalette
    ) -> some View {
        let tier = ProviderQuotaPresentation.tier(for: period, in: balance.tiers)
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                Text(label).foregroundStyle(palette.secondaryText)
                Text(tier.map { String(format: "%.0f%%", ProviderQuotaPresentation.percent(for: $0, mode: model.module.providerQuotaDisplayMode)) } ?? "—")
                    .fontWeight(.bold)
            }
            .minimumScaleFactor(0.7)
            Text(tier.map { ProviderQuotaPresentation.resetText(for: $0, period: period, now: model.renderedAt) } ?? "暂无数据")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .frame(width: period == .fiveHour ? 78 : 84, alignment: .trailing)
    }

    private var title: String {
        switch model.module.configuration {
        case let .appCard(appID, range): "\(appID) · \(range.shortLabel)"
        case let .modelRanking(range): "模型用量排行 · \(range.shortLabel)"
        case let .usageTrend(range, _): range == .today ? "今日趋势" : (range == .sevenDays ? "近 7 日趋势" : "近 30 日趋势")
        default: model.module.kind.title
        }
    }

    private var configuredAppID: String {
        if case let .appCard(id, _) = model.module.configuration { return id }
        return "codex"
    }
    private var configuredRange: ChartRange {
        switch model.module.configuration {
        case let .appCard(_, range), let .modelRanking(range), let .usageTrend(range, _): range
        default: .sevenDays
        }
    }
    private var configuredTrendStyle: ModuleTrendStyle {
        if case let .usageTrend(_, style) = model.module.configuration { return style }
        return .stackedBars
    }
    private var updateDate: Date {
        if model.module.kind == .providerBalances {
            return model.balances.map(\.queriedAt).max() ?? model.snapshot.generatedAt
        }
        return model.snapshot.generatedAt
    }
}

public struct ProviderIconView: View {
    let balance: ProviderBalance
    let color: Color

    public init(balance: ProviderBalance, color: Color) {
        self.balance = balance
        self.color = color
    }

    public var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else if let image = providerImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Text(String(balance.name.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1).frame(width: 15, height: 15))
            }
        }
        .padding(2.5)
        .frame(width: 19, height: 19)
        .background(Circle().fill(Color.white.opacity(0.94)))
        .overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 0.6))
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        let key = (balance.iconName ?? fallbackKey).lowercased()
        return switch key {
        case "openai", "codex": "ProviderOpenAI"
        case "anthropic", "claude": "ProviderClaude"
        case "deepseek": "ProviderDeepSeek"
        case "zhipu", "zai", "glm": "ProviderZAI"
        default: nil
        }
    }

    private var providerImage: NSImage? {
        let icon = inferredIconKey
        let extensions = ["svg", "png", "jpg", "jpeg", "webp"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: icon, withExtension: ext, subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private var inferredIconKey: String {
        let explicit = (balance.iconName ?? "").lowercased()
        if !explicit.isEmpty { return iconAlias(explicit) }
        return iconAlias(fallbackKey.lowercased())
    }

    private func iconAlias(_ raw: String) -> String {
        let mappings: [(String, String)] = [
            ("github copilot", "githubcopilot"), ("copilot", "copilot"),
            ("openai", "openai"), ("codex", "openai"),
            ("anthropic", "anthropic"), ("claude", "claude"),
            ("deepseek", "deepseek"), ("zhipu", "zhipu"), ("智谱", "zhipu"), ("glm", "zhipu"),
            ("gemini", "gemini"), ("google", "google"), ("qwen", "qwen"), ("通义", "qwen"),
            ("bailian", "bailian"), ("alibaba", "alibaba"), ("aliyun", "alibaba"),
            ("kimi", "kimi"), ("moonshot", "moonshot"), ("minimax", "minimax"),
            ("mistral", "mistral"), ("openrouter", "openrouter"), ("siliconflow", "siliconflow"),
            ("hermes", "hermes"), ("hunyuan", "hunyuan"), ("tencent", "tencent"),
            ("doubao", "doubao"), ("豆包", "doubao"), ("bytedance", "bytedance"),
            ("aws", "aws"), ("azure", "azure"), ("nvidia", "nvidia"),
            ("baidu", "baidu"), ("wenxin", "wenxin"), ("stepfun", "stepfun"),
            ("cloudflare", "cloudflare"), ("huggingface", "huggingface"),
            ("ollama", "ollama"), ("opencode", "opencode-logo-light"), ("claw", "claw"),
            ("xai", "xai"), ("grok", "grok"), ("meta", "meta"), ("perplexity", "perplexity")
        ]
        for (needle, icon) in mappings where raw.contains(needle) { return icon }
        return raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "-")
    }

    private var fallbackKey: String {
        switch balance.kind {
        case .codexOAuth: "openai"
        case .claudeOAuth: "anthropic"
        case .balance: balance.name
        }
    }
}

private struct SharedMetric: View {
    let label: String
    let value: String
    let palette: SharedCardPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(palette.secondaryText).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SharedCardPalette {
    let model: CardRenderModel
    let colorScheme: ColorScheme
    var isDark: Bool {
        switch model.themeMode {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        case .custom: !(model.customPalette.first ?? 0xFFFFFF).isLightBackground
        }
    }
    var background: Color {
        if model.themeMode == .custom { return Color(hex: model.customPalette[safe: 0] ?? 0xF6FBFD) }
        return isDark ? Color(hex: 0x21100D) : Color(hex: 0xF6FBFD)
    }
    var primaryText: Color {
        if model.themeMode == .custom { return Color(hex: model.customPalette[safe: 6] ?? 0x212121) }
        return isDark ? .white : Color(hex: 0x212121)
    }
    var secondaryText: Color { primaryText.opacity(isDark ? 0.78 : 0.62) }
    var accent: Color {
        if model.themeMode == .custom { return Color(hex: model.customPalette[safe: 5] ?? 0x3752AA) }
        return isDark ? Color(hex: 0xEA3468) : Color(hex: 0x3752AA)
    }
    var colors: [Color] {
        if model.themeMode == .custom {
            return (1...4).map { Color(hex: model.customPalette[safe: $0] ?? 0x3752AA) }
        }
        return (isDark ? BuiltInThemePalette.darkSeriesHexes : BuiltInThemePalette.lightSeriesHexes)
            .map(Color.init(hex:))
    }
    func series(_ index: Int) -> Color { colors[index % colors.count] }
    var visualization: UsageVisualizationPalette {
        UsageVisualizationPalette(
            primaryText: primaryText,
            secondaryText: secondaryText,
            accent: accent,
            series: colors,
            separator: separator,
            isDark: isDark
        )
    }
    var separator: Color { isDark ? .white.opacity(0.26) : .black.opacity(0.13) }
    var track: Color { isDark ? Color(hex: 0x89062B).opacity(0.82) : Color(hex: 0xD1F8EF) }
    var warning: Color { isDark ? Color(hex: 0xFFB86B) : Color(hex: 0x8A4C00) }
    var up: Color {
        switch model.movementColorMode {
        case .redDownGreenUp: isDark ? Color(hex: 0x34C759) : Color(hex: 0x00A854)
        case .redUpGreenDown: isDark ? Color(hex: 0xFF453A) : Color(hex: 0xE60012)
        case .custom: Color(hex: model.customMovementColors[safe: 0] ?? 0xE60012)
        }
    }
    var down: Color {
        switch model.movementColorMode {
        case .redDownGreenUp: isDark ? Color(hex: 0xFF453A) : Color(hex: 0xE60012)
        case .redUpGreenDown: isDark ? Color(hex: 0x34C759) : Color(hex: 0x00A854)
        case .custom: Color(hex: model.customMovementColors[safe: 1] ?? 0x00A854)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private func cardTokens(_ value: Int64) -> String {
    let number = Double(value)
    if value >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", number / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
}
private func cardPercent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }
private func cardSignedPercent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())) }
private func cardUSD(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(2))) }
private func cardDelta(_ today: Int64, _ yesterday: Int64) -> String {
    guard yesterday != 0 else { return "0%" }
    return cardSignedPercent(Double(today) / Double(yesterday) - 1)
}
public enum CardUpdateTimeFormatter {
    public static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let todayStart = calendar.dateInterval(of: .day, for: now)?.start,
           let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart),
           date >= yesterdayStart, date < todayStart {
            return "昨天 \(time)"
        }
        return "\(components.month ?? 0)月\(components.day ?? 0)日 \(time)"
    }
}
