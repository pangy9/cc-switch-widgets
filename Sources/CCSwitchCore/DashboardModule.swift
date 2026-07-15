import Foundation

public enum ModuleSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var title: String {
        switch self { case .small: "小号"; case .medium: "中号"; case .large: "大号" }
    }
}

public enum WidgetPresentationMetrics {
    public static let unit: CGFloat = 160
    public static let spacing: CGFloat = 16

    public static func width(for size: ModuleSize) -> CGFloat {
        size == .small ? unit : unit * 2 + spacing
    }

    public static func height(for size: ModuleSize) -> CGFloat {
        size == .large ? unit * 2 + spacing : unit
    }

    public static func insets(for size: ModuleSize) -> CGFloat {
        size == .large ? 20 : 18
    }

    public static func titleSpacing(for size: ModuleSize) -> CGFloat {
        switch size { case .small: 4; case .medium: 5; case .large: 6 }
    }
}

public enum ModuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case todayOverview
    case averageComparison
    case appCard
    case topModel
    case modelRanking
    case usageTrend
    case usageHeatmap
    case costOverview
    case providerBalances

    public var id: String { rawValue }

    public var requiresWidgetIntentConfiguration: Bool {
        switch self {
        case .appCard, .modelRanking, .usageTrend, .providerBalances:
            true
        case .todayOverview, .averageComparison, .topModel, .usageHeatmap, .costOverview:
            false
        }
    }

    public var title: String {
        switch self {
        case .todayOverview: "今日总览"
        case .averageComparison: "今日 vs 7 日均值"
        case .appCard: "应用用量"
        case .topModel: "Top 模型"
        case .modelRanking: "模型用量排行"
        case .usageTrend: "用量趋势"
        case .usageHeatmap: "热力图"
        case .costOverview: "费用概览"
        case .providerBalances: "账户"
        }
    }

    public func supports(_ size: ModuleSize) -> Bool {
        switch self {
        case .todayOverview, .averageComparison, .appCard, .topModel, .costOverview:
            size == .small
        case .modelRanking:
            size == .medium || size == .large
        case .usageTrend:
            size == .large
        case .usageHeatmap:
            size == .medium
        case .providerBalances:
            size == .medium || size == .large
        }
    }
}

public enum ModuleTrendStyle: String, Codable, CaseIterable, Sendable {
    case stackedBars, lines

    public var title: String { self == .stackedBars ? "堆叠柱状图" : "折线图" }
}

public enum ModuleTrendScope: String, Codable, CaseIterable, Sendable {
    case byTool, byModel, total

    public var title: String {
        switch self {
        case .byTool: "按工具"
        case .byModel: "按模型"
        case .total: "总消耗量"
        }
    }
}

private extension ChartRange {
    var desktopBindingLabel: String {
        switch self {
        case .today: "当天"
        case .sevenDays: "7 天"
        case .thirtyDays: "30 天"
        }
    }
}

public enum ProviderQuotaDisplayMode: String, Codable, CaseIterable, Sendable {
    case used, remaining
}

public enum ModuleDropEdge: Sendable {
    case before, after
}

public enum ModuleConfiguration: Codable, Equatable, Sendable {
    case none
    case appCard(appID: String, range: ChartRange)
    case modelRanking(range: ChartRange)
    case usageTrend(range: ChartRange, style: ModuleTrendStyle)
    case providerBalances(groupIndex: Int)
}

/// 每个桌面组件实例独立保存的展示参数。
///
/// 它只负责把 AppIntent 参数转换成共享渲染层已经认识的 `DashboardModule`，
/// 不读取 App 仪表盘配置，也不参与菜单栏卡片持久化。
public struct StandaloneWidgetConfiguration: Equatable, Sendable {
    public var appID: String
    public var range: ChartRange
    public var trendStyle: ModuleTrendStyle
    public var trendScope: ModuleTrendScope
    public var modelIDs: [String]
    public var modelSelectionInitialized: Bool
    public var providerQuotaDisplayMode: ProviderQuotaDisplayMode
    public var showsProviderIcons: Bool
    public var providerIDs: [String]

    public init(
        appID: String = "codex",
        range: ChartRange = .sevenDays,
        trendStyle: ModuleTrendStyle = .stackedBars,
        trendScope: ModuleTrendScope = .byTool,
        modelIDs: [String] = [],
        modelSelectionInitialized: Bool? = nil,
        providerQuotaDisplayMode: ProviderQuotaDisplayMode = .used,
        showsProviderIcons: Bool = true,
        providerIDs: [String] = []
    ) {
        self.appID = appID
        self.range = range
        self.trendStyle = trendStyle
        self.trendScope = trendScope
        self.modelIDs = modelIDs
        self.modelSelectionInitialized = modelSelectionInitialized ?? !modelIDs.isEmpty
        self.providerQuotaDisplayMode = providerQuotaDisplayMode
        self.showsProviderIcons = showsProviderIcons
        self.providerIDs = providerIDs
    }

    public func module(kind: ModuleKind, size: ModuleSize) -> DashboardModule {
        let configuration: ModuleConfiguration = switch kind {
        case .appCard:
            .appCard(appID: appID, range: range)
        case .modelRanking:
            .modelRanking(range: range)
        case .usageTrend:
            .usageTrend(range: range, style: trendStyle)
        case .providerBalances:
            .providerBalances(groupIndex: 0)
        case .todayOverview, .averageComparison, .topModel, .usageHeatmap, .costOverview:
            .none
        }

        return DashboardModule(
            kind: kind,
            size: size,
            configuration: configuration,
            showInMenuBar: false,
            isPublishedToDesktop: false,
            providerQuotaDisplayMode: providerQuotaDisplayMode,
            trendScope: trendScope,
            trendModelIDs: modelIDs,
            trendModelSelectionInitialized: modelSelectionInitialized,
            showsProviderIcons: showsProviderIcons,
            providerIDs: providerIDs
        )
    }
}

public struct DashboardModule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: ModuleKind
    public var size: ModuleSize
    public var configuration: ModuleConfiguration
    public var showInMenuBar: Bool
    public var isPublishedToDesktop: Bool
    public var providerQuotaDisplayMode: ProviderQuotaDisplayMode
    public var trendScope: ModuleTrendScope
    public var trendModelIDs: [String]
    public var trendModelSelectionInitialized: Bool
    public var showsProviderIcons: Bool
    public var providerIDs: [String]

    public init(
        id: UUID = UUID(),
        kind: ModuleKind,
        size: ModuleSize,
        configuration: ModuleConfiguration = .none,
        showInMenuBar: Bool = true,
        isPublishedToDesktop: Bool = true,
        providerQuotaDisplayMode: ProviderQuotaDisplayMode = .used,
        trendScope: ModuleTrendScope = .byTool,
        trendModelIDs: [String] = [],
        trendModelSelectionInitialized: Bool? = nil,
        showsProviderIcons: Bool = true,
        providerIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.size = size
        self.configuration = configuration
        self.showInMenuBar = showInMenuBar
        self.isPublishedToDesktop = isPublishedToDesktop
        self.providerQuotaDisplayMode = providerQuotaDisplayMode
        self.trendScope = trendScope
        self.trendModelIDs = trendModelIDs
        self.trendModelSelectionInitialized = trendModelSelectionInitialized ?? !trendModelIDs.isEmpty
        self.showsProviderIcons = showsProviderIcons
        self.providerIDs = providerIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, size, configuration, showInMenuBar, isPublishedToDesktop, providerQuotaDisplayMode, trendScope, trendModelIDs, trendModelSelectionInitialized, showsProviderIcons, providerIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ModuleKind.self, forKey: .kind)
        size = try container.decode(ModuleSize.self, forKey: .size)
        configuration = try container.decode(ModuleConfiguration.self, forKey: .configuration)
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        isPublishedToDesktop = try container.decodeIfPresent(Bool.self, forKey: .isPublishedToDesktop) ?? true
        providerQuotaDisplayMode = try container.decodeIfPresent(ProviderQuotaDisplayMode.self, forKey: .providerQuotaDisplayMode) ?? .used
        trendScope = try container.decodeIfPresent(ModuleTrendScope.self, forKey: .trendScope) ?? .byTool
        trendModelIDs = try container.decodeIfPresent([String].self, forKey: .trendModelIDs) ?? []
        trendModelSelectionInitialized = try container.decodeIfPresent(Bool.self, forKey: .trendModelSelectionInitialized) ?? !trendModelIDs.isEmpty
        showsProviderIcons = try container.decodeIfPresent(Bool.self, forKey: .showsProviderIcons) ?? true
        providerIDs = try container.decodeIfPresent([String].self, forKey: .providerIDs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(size, forKey: .size)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(isPublishedToDesktop, forKey: .isPublishedToDesktop)
        try container.encode(providerQuotaDisplayMode, forKey: .providerQuotaDisplayMode)
        try container.encode(trendScope, forKey: .trendScope)
        try container.encode(trendModelIDs, forKey: .trendModelIDs)
        try container.encode(trendModelSelectionInitialized, forKey: .trendModelSelectionInitialized)
        try container.encode(showsProviderIcons, forKey: .showsProviderIcons)
        try container.encode(providerIDs, forKey: .providerIDs)
    }

    public static func desktopCandidates(in modules: [DashboardModule], kind: ModuleKind, size: ModuleSize) -> [DashboardModule] {
        modules.filter { $0.kind == kind && $0.size == size && $0.isPublishedToDesktop }
    }

    public var desktopBindingTitle: String {
        switch configuration {
        case let .appCard(appID, range):
            return "\(appID) · \(range.desktopBindingLabel) · \(size.title)"
        case let .modelRanking(range):
            return "模型用量排行 · \(range.desktopBindingLabel) · \(size.title)"
        case let .usageTrend(range, style):
            if trendScope == .byModel {
                let selection = trendModelSelectionInitialized
                    ? (trendModelIDs.isEmpty ? "未选择模型" : "\(trendModelIDs.count) 个模型")
                    : "默认前 6"
                return "用量趋势 · \(range.desktopBindingLabel) · \(style.title) · \(trendScope.title) · \(selection)"
            } else {
                return "用量趋势 · \(range.desktopBindingLabel) · \(style.title) · \(trendScope.title)"
            }
        case .providerBalances:
            return "账户 · \(size.title) · \(providerIDs.count) 项"
        case .none:
            return kind == .usageHeatmap ? "热力图 · 6 个月 · \(size.title)" : kind.title
        }
    }

    public static func desktopBindingTitles(in modules: [DashboardModule]) -> [UUID: String] {
        var seen: [String: Int] = [:]
        var result: [UUID: String] = [:]
        for module in modules {
            let base = module.desktopBindingTitle
            let copy = (seen[base] ?? 0) + 1
            seen[base] = copy
            result[module.id] = copy == 1 ? base : "\(base) · 副本 \(copy)"
        }
        return result
    }

    public static func menuBarModules(in modules: [DashboardModule]) -> [DashboardModule] {
        modules.filter(\.showInMenuBar)
    }

    public static func resolveDesktopModule(
        id: String?, in modules: [DashboardModule], kind: ModuleKind, size: ModuleSize
    ) -> DesktopModuleResolution {
        guard let id, !id.isEmpty else {
            guard let first = desktopCandidates(in: modules, kind: kind, size: size).first else { return .unavailable }
            return .resolved(first)
        }
        guard let module = modules.first(where: { $0.id.uuidString == id }) else { return .missing }
        guard module.kind == kind, module.size == size else { return .missing }
        guard module.isPublishedToDesktop else { return .unpublished }
        return .resolved(module)
    }

    public static func moving(
        _ modules: [DashboardModule], sourceID: UUID, targetID: UUID, edge: ModuleDropEdge
    ) -> [DashboardModule] {
        guard sourceID != targetID,
              let source = modules.firstIndex(where: { $0.id == sourceID }) else { return modules }
        var result = modules
        let module = result.remove(at: source)
        guard let target = result.firstIndex(where: { $0.id == targetID }) else { return modules }
        let destination = edge == .before ? target : target + 1
        result.insert(module, at: min(max(0, destination), result.count))
        return result
    }

    public static let defaults: [DashboardModule] = [
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .todayOverview, size: .small),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, kind: .averageComparison, size: .small),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, kind: .appCard, size: .small, configuration: .appCard(appID: "codex", range: .sevenDays)),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, kind: .topModel, size: .small),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, kind: .modelRanking, size: .medium, configuration: .modelRanking(range: .sevenDays)),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, kind: .usageTrend, size: .large, configuration: .usageTrend(range: .sevenDays, style: .stackedBars)),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, kind: .costOverview, size: .small),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, kind: .providerBalances, size: .medium, configuration: .providerBalances(groupIndex: 0)),
        DashboardModule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, kind: .usageHeatmap, size: .medium),
    ]
}

public enum MenuBarModuleOrder {
    public static func reconcile(saved: [UUID], modules: [DashboardModule]) -> [UUID] {
        let available = modules.map(\.id)
        var result = saved.filter { available.contains($0) }
        for id in available where !result.contains(id) { result.append(id) }
        return result
    }

    public static func moving(_ ids: [UUID], sourceID: UUID, targetID: UUID, edge: ModuleDropEdge) -> [UUID] {
        guard sourceID != targetID, let source = ids.firstIndex(of: sourceID) else { return ids }
        var result = ids
        let value = result.remove(at: source)
        guard let target = result.firstIndex(of: targetID) else { return ids }
        result.insert(value, at: edge == .before ? target : target + 1)
        return result
    }
}

public struct MenuBarPackedRow: Equatable, Sendable {
    public let moduleIDs: [UUID]
    public let size: ModuleSize

    public init(moduleIDs: [UUID], size: ModuleSize) {
        self.moduleIDs = moduleIDs
        self.size = size
    }
}

public enum MenuBarPackingLayout {
    public static func pack(_ modules: [DashboardModule]) -> [MenuBarPackedRow] {
        var rows: [MenuBarPackedRow] = []
        var pendingSmallIDs: [UUID] = []

        func flushSmallRow() {
            guard !pendingSmallIDs.isEmpty else { return }
            rows.append(MenuBarPackedRow(moduleIDs: pendingSmallIDs, size: .small))
            pendingSmallIDs.removeAll(keepingCapacity: true)
        }

        for module in modules {
            if module.size == .small {
                pendingSmallIDs.append(module.id)
                if pendingSmallIDs.count == 2 { flushSmallRow() }
            } else {
                flushSmallRow()
                rows.append(MenuBarPackedRow(moduleIDs: [module.id], size: module.size))
            }
        }
        flushSmallRow()
        return rows
    }

    public static func inserting(_ order: [UUID], draggedID: UUID, atSlot slot: Int) -> [UUID] {
        guard let source = order.firstIndex(of: draggedID) else { return order }
        var result = order
        result.remove(at: source)
        let adjustedSlot = source < slot ? slot - 1 : slot
        result.insert(draggedID, at: min(max(0, adjustedSlot), result.count))
        return result
    }

    public static func mergingVisibleOrder(fullOrder: [UUID], visibleOrder: [UUID]) -> [UUID] {
        let visibleSet = Set(visibleOrder)
        var iterator = visibleOrder.makeIterator()
        return fullOrder.map { visibleSet.contains($0) ? (iterator.next() ?? $0) : $0 }
    }
}

public enum DesktopModuleResolution: Equatable, Sendable {
    case resolved(DashboardModule)
    case unpublished
    case missing
    case unavailable
}

public enum TrendModelSelection {
    public static func visible(savedIDs: [String], availableIDs: [String], isInitialized: Bool) -> [String] {
        if !isInitialized { return Array(availableIDs.prefix(6)) }
        let available = Set(availableIDs)
        return savedIDs.filter(available.contains)
    }

    public static func moving(_ ids: [String], sourceID: String, before targetID: String) -> [String] {
        guard sourceID != targetID, let source = ids.firstIndex(of: sourceID) else { return ids }
        var result = ids
        let value = result.remove(at: source)
        guard let target = result.firstIndex(of: targetID) else { return ids }
        result.insert(value, at: target)
        return result
    }
}

public enum ProviderBalanceOrder {
    public struct Reconciliation: Equatable, Sendable {
        public let savedIDs: [String]
        public let visibleIDs: [String]
    }

    public static func reconcile(savedIDs: [String], availableIDs: [String]) -> Reconciliation {
        var persisted = unique(savedIDs)
        for id in unique(availableIDs) where !persisted.contains(id) {
            persisted.append(id)
        }
        let available = Set(availableIDs)
        return Reconciliation(savedIDs: persisted, visibleIDs: persisted.filter(available.contains))
    }

    public static func group(ids: [String], index: Int, size: ModuleSize) -> [String] {
        let capacity = size == .large ? 6 : 3
        let start = max(0, index) * capacity
        guard start < ids.count else { return [] }
        return Array(ids[start ..< min(start + capacity, ids.count)])
    }

    public static func visibleSelection(savedIDs: [String], availableIDs: [String], size: ModuleSize) -> [String] {
        let available = Set(availableIDs)
        let capacity = size == .large ? 6 : 3
        return Array(savedIDs.filter(available.contains).prefix(capacity))
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
