#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct CCSwitchWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("CC Switch Widgets", id: "ccswitch-main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear {
                    appDelegate.configure(model: model)
                    model.refresh()
                }
                .onOpenURL { model.handleURL($0) }
        }
        .windowStyle(.hiddenTitleBar)

    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var themeMode: ThemeMode
    @Published var movementColorMode: MovementColorMode
    @Published var dataState: DataState = .disconnected
    @Published var connectedPath = "未连接"
    @Published var refreshPreset: RefreshPreset
    @Published var customHours: Int
    @Published var customMinutes: Int
    @Published var chartRange: ChartRange = .sevenDays
    @Published var chartKind: AppChartKind = .apps
    @Published var customPalette: [UInt32]
    @Published var customMovementColors: [UInt32]
    @Published var providerBalances: [ProviderBalance] = []
    @Published var dashboardModules: [DashboardModule]
    @Published private(set) var dashboardRevision: Int64
    @Published var providerBalanceOrder: [String]
    @Published var menuBarModuleOrder: [UUID]
    @Published var launchAtLogin: Bool
    @Published var showDockIcon: Bool
    @Published var menuBarPrimaryMetric: MenuBarPrimaryMetric
    @Published var isRefreshing = false

    private let store = SharedUsageStore()
    private var refreshTimer: Timer?
    private var customColorWorkItem: DispatchWorkItem?
    private var customMovementWorkItem: DispatchWorkItem?

    init() {
        store.enableProviderIconsByDefaultIfNeeded()
        store.migrateHeatmapCardsToMediumIfNeeded()
        themeMode = store.loadThemeMode()
        movementColorMode = store.loadMovementColorMode()
        customPalette = store.loadCustomPalette()
        customMovementColors = store.loadCustomMovementColors()
        providerBalances = store.loadProviderBalances()
        let dashboardConfiguration = store.loadDashboardConfiguration()
        dashboardModules = dashboardConfiguration.modules
        dashboardRevision = dashboardConfiguration.revision
        providerBalanceOrder = store.loadProviderBalanceOrder()
        menuBarModuleOrder = MenuBarModuleOrder.reconcile(saved: store.loadMenuBarModuleOrder(), modules: dashboardConfiguration.modules)
        launchAtLogin = store.loadLaunchAtLogin()
        showDockIcon = store.loadShowDockIcon()
        menuBarPrimaryMetric = store.loadMenuBarPrimaryMetric()
        let interval = store.loadRefreshInterval()
        refreshPreset = RefreshPreset.preset(for: interval) ?? .custom
        customHours = Int(interval) / 3600
        customMinutes = (Int(interval) % 3600) / 60
        updateConnectedPath()
        scheduleRefreshTimer()
        reconcileProviderOrder()
        reconcileMenuBarOrder()
        applyDockVisibility()
        applyLaunchAtLogin()
    }

    func connect() {
        let panel = NSOpenPanel()
        panel.title = "选择 .cc-switch 文件夹"
        panel.message = "请选择包含 cc-switch.db 的 CC Switch 数据目录。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            store.saveBookmarkData(bookmark)
            updateConnectedPath()
            refresh()
        } catch {
            dataState = .failed("保存访问授权失败：\(error.localizedDescription)")
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        dataState = SnapshotLoader(store: store).load()
        refreshProviderBalances()
    }

    /// 查询所有渠道额度：Claude/Codex OAuth（独立于 bookmark）+ cc-switch providers 余额。
    func refreshProviderBalances() {
        let service = ProviderBalanceService()
        let now = Date()

        Task { @MainActor in
            // 1. 先读取 CC Switch 的额度查询开关；普通与官方渠道都必须服从该配置。
            var policies: [ProviderUsageQueryPolicy] = []
            var providers: [ProviderConfig] = []
            if let bookmark = self.store.loadBookmarkData() {
                var isStale = false
                if let folderURL = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ), !isStale {
                    let didAccess = folderURL.startAccessingSecurityScopedResource()
                    let repository = SQLiteUsageRepository(databaseURL: folderURL.appendingPathComponent(SharedConstants.databaseFileName))
                    policies = (try? repository.loadUsageQueryPolicies()) ?? []
                    providers = (try? repository.loadProviders()) ?? []
                    if didAccess { folderURL.stopAccessingSecurityScopedResource() }
                }
            }

            // 2. OAuth 渠道：只有 CC Switch 对应官方 provider 开启用量查询时才请求。
            var oauthBalances: [ProviderBalance] = []
            let claudePolicy = policies.first {
                $0.appType == "claude" && $0.isEnabled && ($0.templateType == "official_subscription" || $0.name.localizedCaseInsensitiveContains("Claude Official"))
            }
            if let claudePolicy {
                let claudeCred = OAuthCredentialReader.readClaude()
                if claudeCred.status != .notFound, let token = claudeCred.token {
                    oauthBalances.append((await service.getClaudeQuota(accessToken: token, now: now)).withProviderMetadata(
                        id: claudePolicy.id, name: claudePolicy.name, appType: claudePolicy.appType, iconName: claudePolicy.iconName ?? "anthropic"
                    ))
                }
            }
            let codexPolicy = policies.first {
                $0.appType == "codex" && $0.isEnabled && ($0.templateType == "official_subscription" || $0.name.localizedCaseInsensitiveContains("OpenAI Official"))
            }
            if let codexPolicy {
                let codexCred = OAuthCredentialReader.readCodex()
                if codexCred.status != .notFound, let token = codexCred.token {
                    oauthBalances.append((await service.getCodexQuota(accessToken: token, accountId: codexCred.accountId, now: now)).withProviderMetadata(
                        id: codexPolicy.id, name: codexPolicy.name, appType: codexPolicy.appType, iconName: codexPolicy.iconName ?? "openai"
                    ))
                }
            }

            // 3. 普通 providers：loadProviders 已过滤 usage_script.enabled != true 的项。
            var providerResults: [ProviderBalance] = []
            providerResults = await withTaskGroup(of: ProviderBalance.self) { group in
                for provider in providers {
                    group.addTask {
                        let balance = await service.getBalance(
                            name: provider.name,
                            appType: provider.appType,
                            baseUrl: provider.baseUrl,
                            apiKey: provider.apiKey,
                            now: now,
                            usageScriptCode: provider.usageScriptCode,
                            iconName: provider.iconName
                        )
                        return balance.withProviderMetadata(
                            id: provider.id,
                            name: provider.name,
                            appType: provider.appType,
                            iconName: provider.iconName
                        )
                    }
                }
                var results: [ProviderBalance] = []
                for await balance in group { results.append(balance) }
                return results.sorted { lhs, rhs in
                    let l = providers.firstIndex { $0.name == lhs.name && $0.appType == lhs.appType } ?? Int.max
                    let r = providers.firstIndex { $0.name == rhs.name && $0.appType == rhs.appType } ?? Int.max
                    return l < r
                }
            }

            // 4. 只合并本轮仍启用的渠道；已关闭项不会从旧缓存回流。
            let allBalances = ProviderBalanceMerge.merge(previous: self.providerBalances, refreshed: oauthBalances + providerResults)
            self.providerBalances = allBalances
            self.store.saveProviderBalances(allBalances)
            self.reconcileProviderOrder()
            self.migrateProviderCardSelectionsIfNeeded()
            self.isRefreshing = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var orderedProviderBalances: [ProviderBalance] {
        let map = Dictionary(uniqueKeysWithValues: providerBalances.map { ($0.id, $0) })
        return providerBalanceOrder.compactMap { map[$0] }
    }

    func saveModules(reloading kinds: Set<ModuleKind>? = nil) {
        dashboardRevision = store.saveDashboardModules(dashboardModules).revision
        _ = kinds // 兼容现有菜单栏调用；菜单栏配置不再触发桌面组件刷新。
    }

    func addModule(kind: ModuleKind) {
        let module: DashboardModule
        switch kind {
        case .appCard:
            module = DashboardModule(kind: kind, size: .small, configuration: .appCard(appID: "codex", range: .sevenDays))
        case .modelRanking:
            module = DashboardModule(kind: kind, size: .medium, configuration: .modelRanking(range: .sevenDays))
        case .usageTrend:
            module = DashboardModule(kind: kind, size: .large, configuration: .usageTrend(range: .sevenDays, style: .stackedBars))
        case .usageHeatmap:
            module = DashboardModule(kind: kind, size: .medium)
        case .providerBalances:
            module = DashboardModule(kind: kind, size: .medium, configuration: .providerBalances(groupIndex: 0))
        default:
            module = DashboardModule(kind: kind, size: .small)
        }
        dashboardModules.append(module)
        reconcileMenuBarOrder()
        saveModules(reloading: [kind])
    }

    func removeModule(_ id: UUID) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        let kind = dashboardModules[index].kind
        dashboardModules.remove(at: index)
        reconcileMenuBarOrder()
        saveModules(reloading: [kind])
    }

    func moveModule(_ sourceID: UUID, targetID: UUID, edge: ModuleDropEdge) {
        let reordered = DashboardModule.moving(dashboardModules, sourceID: sourceID, targetID: targetID, edge: edge)
        guard reordered != dashboardModules else { return }
        dashboardModules = reordered
        saveModules(reloading: [])
    }

    func setProviderQuotaDisplayMode(_ id: UUID, _ mode: ProviderQuotaDisplayMode) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        dashboardModules[index].providerQuotaDisplayMode = mode
        saveModules(reloading: [.providerBalances])
    }

    func setTrendScope(_ id: UUID, _ scope: ModuleTrendScope) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        dashboardModules[index].trendScope = scope
        saveModules(reloading: [.usageTrend])
    }

    func setTrendModels(_ ids: [String], for moduleID: UUID) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == moduleID }) else { return }
        dashboardModules[index].trendModelIDs = ids
        dashboardModules[index].trendModelSelectionInitialized = true
        saveModules(reloading: [.usageTrend])
    }

    func moveTrendModel(in moduleID: UUID, sourceID: String, before targetID: String, availableIDs: [String]) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == moduleID }) else { return }
        let current = TrendModelSelection.visible(
            savedIDs: dashboardModules[index].trendModelIDs,
            availableIDs: availableIDs,
            isInitialized: dashboardModules[index].trendModelSelectionInitialized
        )
        let reordered = TrendModelSelection.moving(
            current,
            sourceID: sourceID,
            before: targetID
        )
        guard reordered != current || dashboardModules[index].trendModelIDs.isEmpty else { return }
        dashboardModules[index].trendModelIDs = reordered
        dashboardModules[index].trendModelSelectionInitialized = true
        saveModules(reloading: [.usageTrend])
    }

    func toggleMenuBar(_ id: UUID) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        dashboardModules[index].showInMenuBar.toggle()
        saveModules(reloading: [])
    }

    var orderedMenuBarModules: [DashboardModule] {
        orderedMenuBarModules(order: menuBarModuleOrder)
    }

    var orderedMenuBarConfigurationModules: [DashboardModule] {
        let map = Dictionary(uniqueKeysWithValues: dashboardModules.map { ($0.id, $0) })
        return menuBarModuleOrder.compactMap { map[$0] }
    }

    func orderedMenuBarModules(order: [UUID]?) -> [DashboardModule] {
        let map = Dictionary(uniqueKeysWithValues: dashboardModules.map { ($0.id, $0) })
        return (order ?? menuBarModuleOrder).compactMap { map[$0] }.filter(\.showInMenuBar)
    }

    func commitMenuBarModuleOrder(_ reordered: [UUID]) {
        guard reordered != menuBarModuleOrder else { return }
        menuBarModuleOrder = reordered
        store.saveMenuBarModuleOrder(reordered)
    }

    func commitVisibleMenuBarModuleOrder(_ visibleOrder: [UUID]) {
        commitMenuBarModuleOrder(MenuBarPackingLayout.mergingVisibleOrder(
            fullOrder: menuBarModuleOrder,
            visibleOrder: visibleOrder
        ))
    }

    func moveMenuBarModule(_ sourceID: UUID, before targetID: UUID) {
        let reordered = MenuBarModuleOrder.moving(
            menuBarModuleOrder,
            sourceID: sourceID,
            targetID: targetID,
            edge: .before
        )
        commitMenuBarModuleOrder(reordered)
    }

    func setProviderIconsVisible(_ id: UUID, _ visible: Bool) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        dashboardModules[index].showsProviderIcons = visible
        saveModules(reloading: [.providerBalances])
    }

    func setProvider(_ providerID: String, selected: Bool, for moduleID: UUID) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == moduleID }) else { return }
        var ids = dashboardModules[index].providerIDs
        if selected {
            if !ids.contains(providerID) { ids.append(providerID) }
        } else {
            ids.removeAll { $0 == providerID }
        }
        dashboardModules[index].providerIDs = ids
        saveModules(reloading: [.providerBalances])
    }

    func moveProvider(in moduleID: UUID, sourceID: String, before targetID: String) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == moduleID }), sourceID != targetID,
              let source = dashboardModules[index].providerIDs.firstIndex(of: sourceID),
              let target = dashboardModules[index].providerIDs.firstIndex(of: targetID) else { return }
        let value = dashboardModules[index].providerIDs.remove(at: source)
        dashboardModules[index].providerIDs.insert(value, at: source < target ? target - 1 : target)
        saveModules(reloading: [.providerBalances])
    }

    func setDesktopPublished(_ id: UUID, _ published: Bool) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        dashboardModules[index].isPublishedToDesktop = published
        saveModules(reloading: [dashboardModules[index].kind])
    }

    func updateModule(_ id: UUID, size: ModuleSize? = nil, configuration: ModuleConfiguration? = nil) {
        guard let index = dashboardModules.firstIndex(where: { $0.id == id }) else { return }
        if let size, dashboardModules[index].kind.supports(size) { dashboardModules[index].size = size }
        if let configuration { dashboardModules[index].configuration = configuration }
        saveModules(reloading: [dashboardModules[index].kind])
    }

    func moveProvider(_ sourceID: String, before targetID: String) {
        guard sourceID != targetID,
              let source = providerBalanceOrder.firstIndex(of: sourceID),
              let target = providerBalanceOrder.firstIndex(of: targetID) else { return }
        let id = providerBalanceOrder.remove(at: source)
        providerBalanceOrder.insert(id, at: source < target ? target - 1 : target)
        store.saveProviderBalanceOrder(providerBalanceOrder)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        store.saveLaunchAtLogin(enabled)
        applyLaunchAtLogin()
    }

    func setShowDockIcon(_ enabled: Bool) {
        showDockIcon = enabled
        store.saveShowDockIcon(enabled)
        applyDockVisibility()
    }

    func setMenuBarPrimaryMetric(_ metric: MenuBarPrimaryMetric) {
        menuBarPrimaryMetric = metric
        store.saveMenuBarPrimaryMetric(metric)
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        store.saveThemeMode(mode)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setMovementColorMode(_ mode: MovementColorMode) {
        movementColorMode = mode
        store.saveMovementColorMode(mode)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 修改自定义色板的单个颜色。拖动色板会高频回调，用 ~150ms 节流避免狂落盘 + reload widget。
    func setCustomColor(at index: Int, to hex: UInt32) {
        guard customPalette.indices.contains(index) else { return }
        customPalette[index] = hex
        customColorWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.saveCustomPalette(self.customPalette)
            WidgetCenter.shared.reloadAllTimelines()
        }
        customColorWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 修改自定义涨跌色的单个颜色（0=涨，1=跌），同样节流。
    func setCustomMovementColor(at index: Int, to hex: UInt32) {
        guard customMovementColors.indices.contains(index) else { return }
        customMovementColors[index] = hex
        customMovementWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.saveCustomMovementColors(self.customMovementColors)
            WidgetCenter.shared.reloadAllTimelines()
        }
        customMovementWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "ccswitchwidgets", url.host == "chart" else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let rawRange = values.first(where: { $0.name == "range" })?.value,
           let range = ChartRange(rawValue: rawRange) {
            chartRange = range
        }
        if values.first(where: { $0.name == "kind" })?.value == "models" {
            chartKind = .models
        } else {
            chartKind = .apps
        }
    }

    func setRefreshPreset(_ preset: RefreshPreset) {
        refreshPreset = preset
        if let seconds = preset.seconds {
            saveRefreshInterval(seconds)
        }
    }

    func saveCustomRefreshInterval() {
        let seconds = TimeInterval(customHours * 3600 + customMinutes * 60)
        saveRefreshInterval(max(30, seconds))
    }

    private func saveRefreshInterval(_ seconds: TimeInterval) {
        store.saveRefreshInterval(seconds)
        scheduleRefreshTimer()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: store.loadRefreshInterval(), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func reconcileProviderOrder() {
        let result = ProviderBalanceOrder.reconcile(savedIDs: providerBalanceOrder, availableIDs: providerBalances.map(\.id))
        providerBalanceOrder = result.savedIDs
        store.saveProviderBalanceOrder(result.savedIDs)
    }

    private func reconcileMenuBarOrder() {
        menuBarModuleOrder = MenuBarModuleOrder.reconcile(saved: menuBarModuleOrder, modules: dashboardModules)
        store.saveMenuBarModuleOrder(menuBarModuleOrder)
    }

    private func migrateProviderCardSelectionsIfNeeded() {
        let available = orderedProviderBalances.map(\.id)
        guard !available.isEmpty else { return }
        var changed = false
        for index in dashboardModules.indices where dashboardModules[index].kind == .providerBalances && dashboardModules[index].providerIDs.isEmpty {
            let groupIndex: Int
            if case let .providerBalances(value) = dashboardModules[index].configuration { groupIndex = value } else { groupIndex = 0 }
            dashboardModules[index].providerIDs = ProviderBalanceOrder.group(ids: available, index: groupIndex, size: dashboardModules[index].size)
            changed = true
        }
        if changed { saveModules(reloading: [.providerBalances]) }
    }

    private func applyDockVisibility() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 系统可能要求用户在“登录项”中确认；保留用户选择，供界面展示。
        }
    }

    private func updateConnectedPath() {
        guard let bookmark = store.loadBookmarkData() else {
            connectedPath = "未连接"
            return
        }
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale {
            connectedPath = url.path
        } else {
            connectedPath = "授权已失效"
        }
    }
}

enum RefreshPreset: String, CaseIterable, Identifiable {
    case seconds30, seconds60, minutes3, minutes10, minutes30, minutes60, hours24, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .seconds30: "30 秒"
        case .seconds60: "60 秒"
        case .minutes3: "3 分钟"
        case .minutes10: "10 分钟"
        case .minutes30: "30 分钟"
        case .minutes60: "60 分钟"
        case .hours24: "24 小时"
        case .custom: "自定义"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .seconds30: 30
        case .seconds60: 60
        case .minutes3: 180
        case .minutes10: 600
        case .minutes30: 1_800
        case .minutes60: 3_600
        case .hours24: 86_400
        case .custom: nil
        }
    }
    static func preset(for seconds: TimeInterval) -> RefreshPreset? {
        allCases.first { $0.seconds == seconds }
    }
}

/// 主窗口已用 SwiftUI 的单窗口 Scene（Window），URL 唤起不会再新建窗口。
/// 这里再监听窗口成为 key 作为兜底：若意外出现多窗口，只保留 key 窗口。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    @MainActor
    func configure(model: AppModel) {
        guard menuBarController == nil else { return }
        menuBarController = MenuBarController(model: model) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor [weak self] in self?.showMainWindow() }
        return flag ? false : true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func showMainWindow() {
        let sender = NSApplication.shared
        if let window = sender.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
    }
}
