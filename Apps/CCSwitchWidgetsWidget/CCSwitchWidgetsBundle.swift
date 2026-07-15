import AppIntents
#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import Charts
import SwiftUI
import WidgetKit

@main
struct CCSwitchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayOverviewWidget()
        AverageComparisonWidget()
        AppCardWidget()
        TopModelWidget()
        ModelRankingWidget()
        SevenDayTrendWidget()
        UsageHeatmapWidget()
        CostOverviewWidget()
        ProviderBalancesWidget()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: DataState
    let themeMode: ThemeMode
    let movementColorMode: MovementColorMode
    let selectedApp: String
    let chartRange: ChartRange
    var trendChartStyle: TrendChartStyle = .stackedBars
    var customPalette: [UInt32] = CustomPalette.defaultHexes
    var customMovementColors: [UInt32] = CustomPalette.defaultMovementHexes
    var moduleMessage: String? = nil
    var resolvedModule: DashboardModule? = nil

    var snapshot: UsageSnapshot {
        switch state {
        case let .live(snapshot), let .cached(snapshot, _):
            snapshot
        case .disconnected, .failed:
            .empty
        }
    }

    var message: String? {
        if let moduleMessage { return moduleMessage }
        return switch state {
        case .disconnected:
            "打开 App 连接 CC Switch 数据"
        case .cached:
            nil
        case let .failed(reason):
            reason
        case .live:
            nil
        }
    }
}

private extension UsageEntry {
    func sharedCardModel(kind: ModuleKind, size: ModuleSize) -> CardRenderModel {
        let configuration: ModuleConfiguration = switch kind {
        case .appCard: .appCard(appID: selectedApp, range: chartRange)
        case .modelRanking: .modelRanking(range: chartRange)
        case .usageTrend: .usageTrend(range: chartRange, style: trendChartStyle.moduleStyle)
        default: .none
        }
        return CardRenderModel(
            module: resolvedModule ?? DashboardModule(kind: kind, size: size, configuration: configuration),
            snapshot: snapshot,
            themeMode: themeMode,
            movementColorMode: movementColorMode,
            customPalette: customPalette,
            customMovementColors: customMovementColors,
            message: moduleMessage == nil ? message : nil,
            unavailableMessage: moduleMessage
        )
    }
}

private struct SharedFamilyCard: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry
    let kind: ModuleKind

    var body: some View {
        SharedWidgetCard(model: entry.sharedCardModel(kind: kind, size: moduleSize(for: family)), surface: .widget)
    }
}

enum TrendChartStyle: Equatable, Sendable {
    case stackedBars
    case lines
}

private extension TrendChartStyle {
    var moduleStyle: ModuleTrendStyle {
        switch self {
        case .stackedBars: .stackedBars
        case .lines: .lines
        }
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), state: .live(.preview), themeMode: .system, movementColorMode: .redUpGreenDown, selectedApp: "codex", chartRange: .sevenDays)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(loadEntry(selectedApp: "codex"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = loadEntry(selectedApp: "codex")
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate())))
    }

    private func nextRefreshDate() -> Date {
        Date().addingTimeInterval(SharedUsageStore().loadRefreshInterval())
    }

    private func loadEntry(selectedApp: String) -> UsageEntry {
        UsageEntry(
            date: Date(),
            state: SnapshotLoader(mode: .widget).load(),
            themeMode: SharedUsageStore().loadThemeMode(),
            movementColorMode: SharedUsageStore().loadMovementColorMode(),
            selectedApp: selectedApp,
            chartRange: .sevenDays,
            customPalette: SharedUsageStore().loadCustomPalette(),
            customMovementColors: SharedUsageStore().loadCustomMovementColors()
        )
    }
}

enum ChartRangeOption: String, AppEnum {
    case today
    case sevenDays
    case thirtyDays

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "绘图范围")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "当天",
        .sevenDays: "最近 7 日",
        .thirtyDays: "最近 30 日",
    ]

    var chartRange: ChartRange {
        switch self {
        case .today: .today
        case .sevenDays: .sevenDays
        case .thirtyDays: .thirtyDays
        }
    }
}

enum TrendChartStyleOption: String, AppEnum {
    case stackedBars
    case lines

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "图表样式")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .stackedBars: "堆叠柱状图",
        .lines: "折线图",
    ]

    var trendStyle: TrendChartStyle {
        switch self {
        case .stackedBars: .stackedBars
        case .lines: .lines
        }
    }
}

enum TrendScopeOption: String, AppEnum {
    case byTool
    case byModel
    case total

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "统计维度")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .byTool: "按工具",
        .byModel: "按模型",
        .total: "总消耗量",
    ]

    var moduleScope: ModuleTrendScope {
        switch self {
        case .byTool: .byTool
        case .byModel: .byModel
        case .total: .total
        }
    }
}

struct TrendModelEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "模型")
    static let defaultQuery = TrendModelEntityQuery()

    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct TrendModelEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TrendModelEntity] {
        identifiers.map(TrendModelEntity.init(id:))
    }

    func suggestedEntities() async throws -> [TrendModelEntity] {
        let ids = SharedUsageStore().loadSnapshot()?.availableTrendModelIDs ?? []
        return ids.map(TrendModelEntity.init(id:))
    }
}

struct PublishedTrendIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "趋势图设置"
    static let description = IntentDescription("选择统计范围和图表样式。")

    @Parameter(title: "绘图范围", default: .sevenDays)
    var range: ChartRangeOption

    @Parameter(title: "图表样式", default: .stackedBars)
    var style: TrendChartStyleOption

    @Parameter(title: "统计维度", default: .byTool)
    var scope: TrendScopeOption

    @Parameter(title: "显示模型")
    var models: [TrendModelEntity]?

    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$range)的\(\.$style)，\(\.$scope)，模型 \(\.$models)")
    }
}

struct PublishedTrendProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        makeEntry(range: .sevenDays, style: .stackedBars, scope: .byTool, modelIDs: [], source: "trend.placeholder")
    }

    func snapshot(for configuration: PublishedTrendIntent, in context: Context) async -> UsageEntry {
        makeEntry(
            range: configuration.range.chartRange,
            style: configuration.style.trendStyle,
            scope: configuration.scope.moduleScope,
            modelIDs: configuration.models?.map(\.id) ?? [],
            source: "trend.snapshot"
        )
    }

    func timeline(for configuration: PublishedTrendIntent, in context: Context) async -> Timeline<UsageEntry> {
        Timeline(
            entries: [makeEntry(
                range: configuration.range.chartRange,
                style: configuration.style.trendStyle,
                scope: configuration.scope.moduleScope,
                modelIDs: configuration.models?.map(\.id) ?? [],
                source: "trend.timeline"
            )],
            policy: .after(Date().addingTimeInterval(SharedUsageStore().loadRefreshInterval()))
        )
    }

    private func makeEntry(
        range: ChartRange,
        style: TrendChartStyle,
        scope: ModuleTrendScope,
        modelIDs: [String],
        source: String
    ) -> UsageEntry {
        let module = StandaloneWidgetConfiguration(
            range: range,
            trendStyle: style.moduleStyle,
            trendScope: scope,
            modelIDs: modelIDs
        ).module(kind: .usageTrend, size: .large)
        let entry = UsageEntry(
            date: Date(),
            state: SnapshotLoader(mode: .widget).load(),
            themeMode: SharedUsageStore().loadThemeMode(),
            movementColorMode: SharedUsageStore().loadMovementColorMode(),
            selectedApp: "codex",
            chartRange: range,
            trendChartStyle: style,
            customPalette: SharedUsageStore().loadCustomPalette(),
            customMovementColors: SharedUsageStore().loadCustomMovementColors(),
            resolvedModule: module
        )
        SharedUsageStore().recordRangeDebug(
            source: source,
            range: range,
            appID: entry.selectedApp,
            bucketCount: entry.snapshot.buckets(for: range).count
        )
        return entry
    }
}

struct PublishedRankingIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "图表范围"
    static let description = IntentDescription("选择图表显示当天、最近 7 日或最近 30 日。")

    @Parameter(title: "绘图范围", default: .sevenDays)
    var range: ChartRangeOption

    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$range)")
    }
}

struct PublishedRankingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        makeEntry(range: .sevenDays, source: "chart.placeholder")
    }

    func snapshot(for configuration: PublishedRankingIntent, in context: Context) async -> UsageEntry {
        makeEntry(range: configuration.range.chartRange, source: "chart.snapshot")
    }

    func timeline(for configuration: PublishedRankingIntent, in context: Context) async -> Timeline<UsageEntry> {
        Timeline(
            entries: [makeEntry(range: configuration.range.chartRange, source: "chart.timeline")],
            policy: .after(Date().addingTimeInterval(SharedUsageStore().loadRefreshInterval()))
        )
    }

    private func makeEntry(range: ChartRange, source: String) -> UsageEntry {
        let entry = UsageEntry(
            date: Date(),
            state: SnapshotLoader(mode: .widget).load(),
            themeMode: SharedUsageStore().loadThemeMode(),
            movementColorMode: SharedUsageStore().loadMovementColorMode(),
            selectedApp: "codex",
            chartRange: range,
            customPalette: SharedUsageStore().loadCustomPalette(),
            customMovementColors: SharedUsageStore().loadCustomMovementColors()
        )
        SharedUsageStore().recordRangeDebug(
            source: source,
            range: range,
            appID: entry.selectedApp,
            bucketCount: entry.snapshot.buckets(for: range).count
        )
        return entry
    }
}

struct PublishedAppCardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "应用用量"
    static let description = IntentDescription("选择一个应用显示今日 Token。")

    @Parameter(title: "应用", optionsProvider: AppOptionsProvider())
    var appID: String?

    @Parameter(title: "绘图范围", default: .sevenDays)
    var range: ChartRangeOption

    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$appID) 的 \(\.$range)")
    }

    init() {
        appID = "codex"
        range = .sevenDays
    }

    init(appID: String?, range: ChartRangeOption = .sevenDays) {
        self.appID = appID
        self.range = range
    }
}

struct AppOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let defaults = ["codex", "claude", "gemini"]
        let stored = SharedUsageStore().loadSnapshot()?.apps.map(\.id) ?? []
        return Array(Set(defaults + stored)).sorted()
    }
}

struct PublishedAppCardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        entry(appID: "codex", range: .sevenDays, source: "app.placeholder")
    }

    func snapshot(for configuration: PublishedAppCardIntent, in context: Context) async -> UsageEntry {
        entry(appID: configuration.appID ?? "codex", range: configuration.range.chartRange, source: "app.snapshot")
    }

    func timeline(for configuration: PublishedAppCardIntent, in context: Context) async -> Timeline<UsageEntry> {
        Timeline(
            entries: [entry(appID: configuration.appID ?? "codex", range: configuration.range.chartRange, source: "app.timeline")],
            policy: .after(Date().addingTimeInterval(SharedUsageStore().loadRefreshInterval()))
        )
    }

    private func entry(appID: String, range: ChartRange, source: String) -> UsageEntry {
        let entry = UsageEntry(
            date: Date(),
            state: SnapshotLoader(mode: .widget).load(),
            themeMode: SharedUsageStore().loadThemeMode(),
            movementColorMode: SharedUsageStore().loadMovementColorMode(),
            selectedApp: appID,
            chartRange: range,
            customPalette: SharedUsageStore().loadCustomPalette(),
            customMovementColors: SharedUsageStore().loadCustomMovementColors()
        )
        SharedUsageStore().recordRangeDebug(
            source: source,
            range: range,
            appID: appID,
            bucketCount: entry.snapshot.buckets(for: range).count
        )
        return entry
    }
}

struct TodayOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today-overview", provider: SnapshotProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .todayOverview, size: .small), surface: .widget)
        }
        .configurationDisplayName("今日总览")
        .description("今日 Token、昨日对比、环比和请求数。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct AverageComparisonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "average-comparison", provider: SnapshotProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .averageComparison, size: .small), surface: .widget)
        }
        .configurationDisplayName("今日 vs 7 日均值")
        .description("今日用量和此前 7 个完整自然日均值对比。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct AppCardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "app-card-v3", intent: PublishedAppCardIntent.self, provider: PublishedAppCardProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .appCard, size: .small), surface: .widget)
                .widgetURL(chartURL(kind: "app", range: entry.chartRange, app: entry.selectedApp))
        }
        .configurationDisplayName("应用用量")
        .description("选择 Codex、Claude、Gemini 或数据库中的其他应用。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct TopModelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "top-model", provider: SnapshotProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .topModel, size: .small), surface: .widget)
        }
        .configurationDisplayName("Top 模型")
        .description("自动显示今日 Token 最高的模型。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct ModelRankingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "model-ranking-v3", intent: PublishedRankingIntent.self, provider: PublishedRankingProvider()) { entry in
            SharedFamilyCard(entry: entry, kind: .modelRanking)
                .widgetURL(chartURL(kind: "models", range: entry.chartRange))
        }
        .configurationDisplayName("模型用量排行")
        .description("Top 模型、区间占比和排名变化。中号显示 3 个，大号显示 6 个。")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct SevenDayTrendWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "usage-trend-v4", intent: PublishedTrendIntent.self, provider: PublishedTrendProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .usageTrend, size: .large), surface: .widget)
                .widgetURL(chartURL(kind: "apps", range: entry.chartRange))
        }
        .configurationDisplayName("近 7 日趋势")
        .description("按应用显示 Token 趋势，可选择堆叠柱状图或折线图。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct UsageHeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "usage-heatmap-v1",
            provider: SnapshotProvider()
        ) { entry in
            SharedFamilyCard(entry: entry, kind: .usageHeatmap)
        }
        .configurationDisplayName("热力图")
        .description("以 GitHub 风格按周展示最近 6 个月的每日 Token 用量。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct CostOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cost-overview", provider: SnapshotProvider()) { entry in
            SharedWidgetCard(model: entry.sharedCardModel(kind: .costOverview, size: .small), surface: .widget)
        }
        .configurationDisplayName("费用概览")
        .description("今日费用、昨日环比和本月累计。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

enum QuotaDisplayOption: String, AppEnum {
    case used
    case remaining

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "额度显示")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .used: "已使用",
        .remaining: "剩余",
    ]

    var mode: ProviderQuotaDisplayMode { self == .used ? .used : .remaining }
}

struct ProviderBalanceEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "账户")
    static let defaultQuery = ProviderBalanceEntityQuery()

    let id: String
    let name: String
    let appType: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(appType)",
            image: iconName.map { DisplayRepresentation.Image(named: $0, isTemplate: true, displayStyle: .circular) }
        )
    }
    let iconName: String?
}

struct ProviderBalanceEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProviderBalanceEntity] {
        let wanted = Set(identifiers)
        return allEntities().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderBalanceEntity] { allEntities() }

    private func allEntities() -> [ProviderBalanceEntity] {
        let store = SharedUsageStore()
        let balances = store.loadProviderBalances()
        let ordered = ProviderBalanceOrder.reconcile(
            savedIDs: store.loadProviderBalanceOrder(),
            availableIDs: balances.map(\.id)
        ).visibleIDs
        let map = Dictionary(uniqueKeysWithValues: balances.map { ($0.id, $0) })
        return ordered.compactMap { id in
            map[id].map {
                ProviderBalanceEntity(id: id, name: $0.name, appType: $0.appType, iconName: $0.iconName)
            }
        }
    }
}

struct BalanceModuleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "账户设置"
    static let description = IntentDescription("直接选择此组件显示的账户和额度方式。")

    @Parameter(title: "显示账户")
    var providers: [ProviderBalanceEntity]?

    @Parameter(title: "额度显示", default: .used)
    var quotaDisplay: QuotaDisplayOption

    @Parameter(title: "显示 Provider 图标", default: true)
    var showsProviderIcons: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$providers)，\(\.$quotaDisplay)")
    }
}

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balances: [ProviderBalance]
    let module: DashboardModule?
    let themeMode: ThemeMode
    let movementColorMode: MovementColorMode
    let customPalette: [UInt32]
    let customMovementColors: [UInt32]
    let moduleMessage: String?
}

struct BalanceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        makeEntry(providerIDs: [], quotaDisplay: .used, showsProviderIcons: true, family: context.family)
    }
    func snapshot(for configuration: BalanceModuleIntent, in context: Context) async -> BalanceEntry {
        makeEntry(
            providerIDs: configuration.providers?.map(\.id) ?? [],
            quotaDisplay: configuration.quotaDisplay.mode,
            showsProviderIcons: configuration.showsProviderIcons,
            family: context.family
        )
    }
    func timeline(for configuration: BalanceModuleIntent, in context: Context) async -> Timeline<BalanceEntry> {
        let entry = makeEntry(
            providerIDs: configuration.providers?.map(\.id) ?? [],
            quotaDisplay: configuration.quotaDisplay.mode,
            showsProviderIcons: configuration.showsProviderIcons,
            family: context.family
        )
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(SharedUsageStore().loadRefreshInterval())))
    }

    private func makeEntry(
        providerIDs: [String],
        quotaDisplay: ProviderQuotaDisplayMode,
        showsProviderIcons: Bool,
        family: WidgetFamily
    ) -> BalanceEntry {
        let store = SharedUsageStore()
        let balances = store.loadProviderBalances()
        let ordered = ProviderBalanceOrder.reconcile(savedIDs: store.loadProviderBalanceOrder(), availableIDs: balances.map(\.id)).visibleIDs
        let map = Dictionary(uniqueKeysWithValues: balances.map { ($0.id, $0) })
        let size = moduleSize(for: family)
        let requested = providerIDs.isEmpty ? ordered : providerIDs
        let ids = ProviderBalanceOrder.visibleSelection(savedIDs: requested, availableIDs: ordered, size: size)
        let module = StandaloneWidgetConfiguration(
            providerQuotaDisplayMode: quotaDisplay,
            showsProviderIcons: showsProviderIcons,
            providerIDs: requested
        ).module(kind: .providerBalances, size: size)
        return BalanceEntry(
            date: Date(), balances: ids.compactMap { map[$0] }, module: module,
            themeMode: store.loadThemeMode(), movementColorMode: store.loadMovementColorMode(),
            customPalette: store.loadCustomPalette(), customMovementColors: store.loadCustomMovementColors(), moduleMessage: nil
        )
    }
}

struct ProviderBalancesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "provider-balances-v1", intent: BalanceModuleIntent.self, provider: BalanceTimelineProvider()) { entry in
            ProviderBalancesWidgetView(entry: entry)
        }
        .configurationDisplayName("账户")
        .description("独立选择账户、额度显示方式和 Provider 图标。中号最多 3 个，大号最多 6 个。")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

private struct ProviderBalancesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalanceEntry

    var body: some View {
        let size = moduleSize(for: family)
        let module = entry.module ?? DashboardModule(kind: .providerBalances, size: size, configuration: .providerBalances(groupIndex: 0))
        SharedWidgetCard(
            model: CardRenderModel(
                module: module,
                snapshot: .empty,
                balances: entry.balances,
                themeMode: entry.themeMode,
                movementColorMode: entry.movementColorMode,
                customPalette: entry.customPalette,
                customMovementColors: entry.customMovementColors,
                message: nil,
                unavailableMessage: entry.moduleMessage
            ),
            surface: .widget
        )
    }
}

private struct WidgetShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry
    let title: String
    @ViewBuilder let content: (WidgetPalette) -> Content

    var body: some View {
        let palette = WidgetPalette(
            mode: entry.themeMode,
            colorScheme: colorScheme,
            movementColorMode: entry.movementColorMode,
            customPalette: entry.customPalette,
            customMovementColors: entry.customMovementColors
        )
        VStack(alignment: .leading, spacing: shellTitleSpacing(for: family)) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(.system(size: family == .systemSmall ? 13 : 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 4)
                Text(relativeUpdate(entry.snapshot.generatedAt))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            content(palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let message = entry.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(palette.warning)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(palette.primaryText)
        .padding(shellInsets(for: family))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetAccentable(false)
        .containerBackground(for: .widget) {
            WidgetPalette(
                mode: entry.themeMode,
                colorScheme: colorScheme,
                movementColorMode: entry.movementColorMode,
                customPalette: entry.customPalette,
                customMovementColors: entry.customMovementColors
            ).background
        }
    }
}

private struct TodayOverviewView: View {
    let entry: UsageEntry

    var body: some View {
        WidgetShell(entry: entry, title: "今日总览") { palette in
            let today = entry.snapshot.today
            let yesterday = entry.snapshot.yesterday.totalTokens
            VStack(alignment: .leading, spacing: 0) {
                Text(formatTokens(today.totalTokens))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                Spacer(minLength: 6)
                Text("昨日 \(formatTokens(yesterday))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    MetricPill(label: "环比", value: delta(today.totalTokens, yesterday), palette: palette)
                    MetricPill(label: "请求", value: "\(today.requestCount)", palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct AverageComparisonView: View {
    let entry: UsageEntry

    var body: some View {
        WidgetShell(entry: entry, title: "今日 vs 均值") { palette in
            let today = Double(entry.snapshot.today.totalTokens)
            let average = entry.snapshot.sevenDayAverageTokens
            let change = average == 0 ? 0 : today / average - 1
            VStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 4)
                Text(formatTokens(Int64(today)))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Spacer(minLength: 10)
                ComparisonBaseline(ratio: average == 0 ? 0 : today / average, palette: palette)
                    .frame(height: 8)
                Spacer(minLength: 10)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("均值")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.opacity(0.72))
                        Text(formatTokens(Int64(average)))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(width: 72, alignment: .leading)
                    Spacer(minLength: 8)
                    AverageDeltaLabel(change: change, palette: palette)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct AppCardView: View {
    let entry: UsageEntry

    var body: some View {
        WidgetShell(entry: entry, title: "\(entry.selectedApp) · \(entry.chartRange.shortLabel)") { palette in
            let app = entry.snapshot.appSummary(id: entry.selectedApp, for: entry.chartRange)
            VStack(alignment: .leading, spacing: 0) {
                Text(formatTokens(app.totalTokens))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text(formatPercent(app.share))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("区间占比")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MiniLineChart(
                    values: entry.snapshot.buckets(for: entry.chartRange).map { $0.appTokens[entry.selectedApp] ?? 0 },
                    palette: palette
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct TopModelView: View {
    let entry: UsageEntry

    var body: some View {
        WidgetShell(entry: entry, title: "Top 模型") { palette in
            let model = entry.snapshot.models.first
            VStack(alignment: .leading, spacing: 0) {
                Text(model?.id ?? "暂无模型")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 5)
                Text(formatTokens(model?.totalTokens ?? 0))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    MetricPill(label: "占比", value: formatPercent(model?.share ?? 0), palette: palette)
                    MetricPill(label: "命中", value: formatPercent(model?.cacheHitRate ?? 0), palette: palette)
                    MetricPill(label: "请求", value: "\(model?.totals.requestCount ?? 0)", palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ModelRankingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var maxVisible: Int {
        family == .systemLarge ? 6 : 3
    }

    private var rowHeight: CGFloat? {
        family == .systemLarge ? nil : 34
    }

    private var rowVerticalPadding: CGFloat {
        family == .systemLarge ? 5 : 0
    }

    var body: some View {
        WidgetShell(entry: entry, title: "模型用量排行 · \(entry.chartRange.shortLabel)") { palette in
            let visibleModels = Array(entry.snapshot.modelSummaries(for: entry.chartRange).prefix(maxVisible))
            let buckets = entry.snapshot.buckets(for: entry.chartRange)
            let seriesColors = palette.rankingColors(count: visibleModels.count)
            VStack(spacing: 0) {
                ForEach(Array(visibleModels.enumerated()), id: \.element.id) { index, model in
                    ModelRankingRow(
                        model: model,
                        trend: buckets.map { $0.modelTokens?[model.id] ?? 0 },
                        buckets: buckets,
                        previousTokens: entry.snapshot.previousRangeTokens(for: entry.chartRange, model: model.id),
                        seriesIndex: index,
                        seriesColors: seriesColors,
                        palette: palette,
                        rowHeight: rowHeight,
                        verticalPadding: rowVerticalPadding
                    )
                    if index < visibleModels.count - 1 {
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: family == .systemLarge ? .infinity : nil, alignment: .top)
        }
    }
}

private struct ModelRankingRow: View {
    let model: RangeTokenSummary
    let trend: [Int64]
    let buckets: [DailyUsage]
    let previousTokens: Int64
    let seriesIndex: Int
    let seriesColors: [Color]
    let palette: WidgetPalette
    let rowHeight: CGFloat?
    let verticalPadding: CGFloat

    private var lineColor: Color { seriesColors[seriesIndex] }

    private var areaGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: lineColor.opacity(1.0), location: 0),
                .init(color: lineColor.opacity(0), location: 1),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        let rankDelta = modelRankDelta(buckets: buckets, modelID: model.id)
        let tokenChange = previousTokens == 0
            ? (model.totalTokens > 0 ? 1 : 0)
            : Double(model.totalTokens - previousTokens) / Double(previousTokens)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: rankSymbol(rankDelta))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(lineColor)
                    Text(model.id)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text("\(formatPercent(model.share)) 区间占比")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 126, alignment: .leading)

            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { point in
                    AreaMark(
                        x: .value("日", point.offset),
                        y: .value("Token", point.element)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(areaGradient)
                    LineMark(
                        x: .value("日", point.offset),
                        y: .value("Token", point.element)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                RuleMark(y: .value("均值", modelTrendAverage(trend)))
                    .foregroundStyle(palette.primaryText.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... max(trend.max() ?? 0, 1) * 13 / 10)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTokens(model.totalTokens))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                ModelDeltaLabel(change: tokenChange, palette: palette)
            }
            .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(height: rowHeight)
    }
}

private struct CostOverviewView: View {
    let entry: UsageEntry

    var body: some View {
        WidgetShell(entry: entry, title: "费用概览") { palette in
            let today = entry.snapshot.today.costUSD
            let yesterday = entry.snapshot.yesterday.costUSD
            VStack(alignment: .leading, spacing: 0) {
                Text(formatUSD(today))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Spacer(minLength: 6)
                Text("昨日 \(formatUSD(yesterday))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    MetricPill(label: "环比", value: signedPercent(yesterday == 0 ? 0 : today / yesterday - 1), palette: palette)
                    MetricPill(label: "本月", value: formatUSD(entry.snapshot.monthCostUSD), palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MetricPill: View {
    let label: String
    let value: String
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComparisonBaseline: View {
    let ratio: Double
    let palette: WidgetPalette

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(ratio, 0), 1.5)
            let width = proxy.size.width * min(clamped / 1.5, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track.opacity(0.82))
                Capsule()
                    .fill(clamped <= 1 ? palette.down : palette.up)
                    .frame(width: max(8, width))
            }
        }
    }
}

private struct AverageDeltaLabel: View {
    let change: Double
    let palette: WidgetPalette

    var body: some View {
        let isLower = change <= 0
        VStack(alignment: .trailing, spacing: 1) {
            Text(isLower ? "低于均值" : "高于均值")
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                Image(systemName: isLower ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .foregroundStyle(isLower ? palette.down : palette.up)
    }
}

private struct MiniLineChart: View {
    let values: [Int64]
    let palette: WidgetPalette

    var body: some View {
        let lineColor = palette.accent
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { point in
                AreaMark(
                    x: .value("日", point.offset),
                    y: .value("Token", point.element)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [lineColor.opacity(0.42), lineColor.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("日", point.offset),
                    y: .value("Token", point.element)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            RuleMark(y: .value("均值", modelTrendAverage(values)))
                .foregroundStyle(palette.primaryText.opacity(0.82))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... max(values.max() ?? 0, 1) * 13 / 10)
        .widgetAccentable(false)
    }
}

private struct ModelDeltaLabel: View {
    let change: Double
    let palette: WidgetPalette

    var body: some View {
        Text(signedPercent(change))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(change > 0 ? palette.up : (change < 0 ? palette.down : palette.secondaryText))
    }
}

private func modelTrendAverage(_ values: [Int64]) -> Double {
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

private func rangeTitle(_ range: ChartRange) -> String {
    switch range {
    case .today: "今日趋势"
    case .sevenDays: "近 7 日趋势"
    case .thirtyDays: "近 30 日趋势"
    }
}

private func chartURL(kind: String, range: ChartRange, app: String? = nil) -> URL? {
    var components = URLComponents()
    components.scheme = "ccswitchwidgets"
    components.host = "chart"
    var items = [
        URLQueryItem(name: "kind", value: kind),
        URLQueryItem(name: "range", value: range.rawValue),
    ]
    if let app { items.append(URLQueryItem(name: "app", value: app)) }
    components.queryItems = items
    return components.url
}

/// 折线图范围内排名变化：前半段名次 − 后半段名次；正值=上升，负值=下降，0=持平。
/// 段内名次按累计 token 降序、id 升序，与榜单口径一致。
private func modelRankDelta(buckets: [DailyUsage], modelID: String) -> Int {
    guard buckets.count >= 2 else { return 0 }
    let mid = buckets.count / 2
    guard mid > 0 else { return 0 }
    let firstRank = modelRank(of: modelID, in: Array(buckets.prefix(mid)))
    let secondRank = modelRank(of: modelID, in: Array(buckets.suffix(buckets.count - mid)))
    return firstRank - secondRank
}

private func modelRank(of modelID: String, in buckets: [DailyUsage]) -> Int {
    var totals: [String: Int64] = [:]
    for bucket in buckets {
        for (model, tokens) in bucket.modelTokens ?? [:] {
            totals[model, default: 0] += tokens
        }
    }
    let sorted = totals.sorted { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }
    if let index = sorted.firstIndex(where: { $0.key == modelID }) {
        return index + 1
    }
    return sorted.count + 1
}

private func rankSymbol(_ delta: Int) -> String {
    delta > 0 ? "arrowtriangle.up.fill" : (delta < 0 ? "arrowtriangle.down.fill" : "minus")
}

private struct AppLegend: View {
    let apps: [String]
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(apps.enumerated()), id: \.element) { index, app in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.seriesColor(at: index))
                        .frame(width: 10, height: 7)
                    Text(app)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(palette.secondaryText)
    }
}

private struct WidgetPalette {
    let mode: ThemeMode
    let colorScheme: ColorScheme
    let movementColorMode: MovementColorMode
    let customPalette: [UInt32]
    let customMovementColors: [UInt32]

    var isDark: Bool {
        switch mode {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        case .custom: !customPalette[0].isLightBackground
        }
    }

    var themeColors: [Color] {
        if case .custom = mode {
            return [
                Color(hex: customPalette[0]),
                Color(hex: customPalette[1]),
                Color(hex: customPalette[2]),
                Color(hex: customPalette[3]),
                Color(hex: customPalette[4])
            ]
        }
        return isDark
            ? [
                Color(hex: 0x21100D),
                Color(hex: 0x89062B),
                Color(hex: 0xC40A3E),
                Color(hex: 0xEA3468),
                .white,
            ]
            : [
                Color(hex: 0x3752aa),
                Color(hex: 0x578FCA),
                Color(hex: 0xA1E3F9),
                Color(hex: 0xD1F8EF),
                .white,
            ]
    }

    private var chartHexes: [UInt32] {
        if case .custom = mode {
            return [customPalette[1], customPalette[2], customPalette[3], customPalette[4]]
        }
        return isDark
            ? [0xEA3468, 0xFF668F, 0xFF9AB5, 0xFFFFFF]
            : [0x3752AA, 0x578FCA, 0xA1E3F9, 0xD1F8EF]
    }

    var chartColors: [Color] {
        chartHexes.map { Color(hex: $0) }
    }

    /// 模型排行专用色板：模型数不超过锚点数时直接取锚点前缀；超出时在相邻锚点间插入 RGB 中值色扩展。
    func rankingColors(count: Int) -> [Color] {
        let hexes = chartHexes
        guard count > hexes.count else {
            return Array(chartColors.prefix(max(1, count)))
        }
        var expanded: [UInt32] = []
        for index in 0..<(hexes.count - 1) {
            expanded.append(hexes[index])
            expanded.append(midHex(hexes[index], hexes[index + 1]))
        }
        expanded.append(hexes[hexes.count - 1])
        return Array(expanded.prefix(count).map { Color(hex: $0) })
    }

    private func midHex(_ lhs: UInt32, _ rhs: UInt32) -> UInt32 {
        let lr = (lhs >> 16) & 0xFF, lg = (lhs >> 8) & 0xFF, lb = lhs & 0xFF
        let rr = (rhs >> 16) & 0xFF, rg = (rhs >> 8) & 0xFF, rb = rhs & 0xFF
        let mr = (lr + rr) / 2, mg = (lg + rg) / 2, mb = (lb + rb) / 2
        return (mr << 16) | (mg << 8) | mb
    }

    var background: Color {
        if case .custom = mode { return Color(hex: customPalette[0]) }
        return isDark ? Color(hex: 0x21100D) : Color(hex: 0xF6FBFD)
    }

    var primaryText: Color {
        if case .custom = mode { return Color(hex: customPalette[6]) }
        return isDark ? .white : Color(hex: 0x212121)
    }

    var secondaryText: Color {
        if case .custom = mode { return Color(hex: customPalette[6]).opacity(0.68) }
        return isDark ? .white.opacity(0.78) : Color(hex: 0x212121).opacity(0.62)
    }

    var accent: Color {
        if case .custom = mode { return Color(hex: customPalette[5]) }
        return isDark ? Color(hex: 0xEA3468) : Color(hex: 0x3752aa)
    }

    func seriesColor(at index: Int) -> Color {
        chartColors[index % chartColors.count]
    }

    var up: Color {
        switch movementColorMode {
        case .redDownGreenUp:
            statusGreen
        case .redUpGreenDown:
            statusRed
        case .custom:
            Color(hex: customMovementColors[0])
        }
    }

    var down: Color {
        switch movementColorMode {
        case .redDownGreenUp:
            statusRed
        case .redUpGreenDown:
            statusGreen
        case .custom:
            Color(hex: customMovementColors[1])
        }
    }

    var track: Color {
        if case .custom = mode { return Color(hex: customPalette[1]).opacity(isDark ? 0.82 : 0.6) }
        return isDark ? Color(hex: 0x89062B).opacity(0.82) : Color(hex: 0xD1F8EF)
    }

    var warning: Color {
        isDark ? Color(hex: 0xFFB86B) : Color(hex: 0x8A4C00)
    }

    var separator: Color {
        isDark ? .white.opacity(0.26) : .black.opacity(0.13)
    }

    private var statusRed: Color {
        isDark ? Color(hex: 0xFF453A) : Color(hex: 0xE60012)
    }

    private var statusGreen: Color {
        isDark ? Color(hex: 0x34C759) : Color(hex: 0x00A854)
    }
}

private func shellInsets(for family: WidgetFamily) -> EdgeInsets {
    let value = WidgetPresentationMetrics.insets(for: moduleSize(for: family))
    return EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
}

private func shellTitleSpacing(for family: WidgetFamily) -> CGFloat {
    WidgetPresentationMetrics.titleSpacing(for: moduleSize(for: family))
}

private func moduleSize(for family: WidgetFamily) -> ModuleSize {
    switch family {
    case .systemSmall: .small
    case .systemMedium: .medium
    default: .large
    }
}

private func formatTokens(_ value: Int64) -> String {
    let number = Double(value)
    if value >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", number / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
}

private func formatPercent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

private func signedPercent(_ value: Double) -> String {
    let sign = value > 0 ? "+" : ""
    return "\(sign)\(value.formatted(.percent.precision(.fractionLength(0))))"
}

private func delta(_ today: Int64, _ yesterday: Int64) -> String {
    guard yesterday > 0 else { return "0%" }
    return signedPercent(Double(today - yesterday) / Double(yesterday))
}

private func formatUSD(_ value: Double) -> String {
    if value >= 1_000 {
        return String(format: "$%.1fK", value / 1_000)
    }
    return String(format: "$%.2f", value)
}

private func relativeUpdate(_ date: Date) -> String {
    guard date > .distantPast else { return "未更新" }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 1 { return "刚刚更新" }
    if minutes < 60 { return "更新于\(minutes)分钟前" }
    return "更新于\(minutes / 60)小时前"
}

private extension UsageSnapshot {
    static let preview = UsageSnapshot(
        generatedAt: Date(),
        today: UsageTotals(totalTokens: 2_640_000, requestCount: 184, successfulRequests: 172, costUSD: 4.28),
        yesterday: UsageTotals(totalTokens: 1_920_000, requestCount: 121, successfulRequests: 117, costUSD: 2.91),
        sevenDayAverageTokens: 1_580_000,
        trend: (0 ..< 7).map { offset in
            DailyUsage(
                date: Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) ?? Date(),
                totals: UsageTotals(totalTokens: Int64([920_000, 1_150_000, 780_000, 1_620_000, 1_380_000, 1_920_000, 2_640_000][offset])),
                appTokens: [
                    "codex": Int64([650_000, 820_000, 540_000, 1_100_000, 930_000, 1_300_000, 1_900_000][offset]),
                    "claude": Int64([270_000, 330_000, 240_000, 520_000, 450_000, 620_000, 740_000][offset]),
                ]
            )
        },
        apps: [
            AppUsage(id: "codex", totals: UsageTotals(totalTokens: 1_900_000, requestCount: 120, successfulRequests: 115, costUSD: 2.98), share: 0.72, trendTokens: [650_000, 820_000, 540_000, 1_100_000, 930_000, 1_300_000, 1_900_000]),
            AppUsage(id: "claude", totals: UsageTotals(totalTokens: 740_000, requestCount: 64, successfulRequests: 57, costUSD: 1.30), share: 0.28, trendTokens: [270_000, 330_000, 240_000, 520_000, 450_000, 620_000, 740_000]),
        ],
        models: [
            ModelUsage(id: "gpt-5.5", totals: UsageTotals(totalTokens: 1_540_000, requestCount: 86, successfulRequests: 83, costUSD: 2.48), share: 0.58),
            ModelUsage(id: "glm-5.2", totals: UsageTotals(totalTokens: 620_000, requestCount: 52, successfulRequests: 49, costUSD: 0.88), share: 0.23),
            ModelUsage(id: "claude-opus-4-8", totals: UsageTotals(totalTokens: 360_000, requestCount: 29, successfulRequests: 25, costUSD: 0.72), share: 0.14),
        ],
        monthCostUSD: 48.72
    )
}
