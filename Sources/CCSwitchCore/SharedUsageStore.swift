import Darwin
import Foundation

public enum MenuBarPrimaryMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case iconOnly
    case requests
    case tokens
    case cost

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .iconOnly: "仅图标"
        case .requests: "请求数"
        case .tokens: "总 Token 消耗量"
        case .cost: "总花费"
        }
    }

    public var segmentTitle: String {
        switch self {
        case .iconOnly: "图标"
        case .requests: "请求数"
        case .tokens: "Token"
        case .cost: "花费"
        }
    }
}

public enum SharedConstants {
    public static let appGroupIdentifier = "group.com.pangyun.CCSwitchWidgets"
    public static let appBundleIdentifier = "com.pangyun.CCSwitchWidgets"
    public static let widgetBundleIdentifier = "com.pangyun.CCSwitchWidgets.Widget"
    public static let databaseFileName = "cc-switch.db"
    public static let supportDirectoryName = "CCSwitchWidgets"
    public static let snapshotFileName = "usage-snapshot.json"
    public static let themeFileName = "theme-mode.txt"
    public static let movementColorFileName = "movement-color-mode.txt"
    public static let customPaletteFileName = "custom-palette.txt"
    public static let customMovementFileName = "custom-movement.txt"
    public static let rangeDebugFileName = "widget-range-debug.jsonl"
    public static let providerBalancesFileName = "provider-balances.json"
    public static let dashboardConfigurationFileName = "dashboard-configuration.json"
}

public struct DashboardConfigurationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let revision: Int64
    public let modules: [DashboardModule]

    public init(schemaVersion: Int = currentSchemaVersion, revision: Int64, modules: [DashboardModule]) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.modules = modules
    }

    public static let initial = DashboardConfigurationDocument(revision: 1, modules: DashboardModule.defaults)
}

public struct SharedUsageStore: Sendable {
    private enum Key {
        static let bookmarkData = "ccswitch.bookmarkData"
        static let themeMode = "ccswitch.themeMode"
        static let movementColorMode = "ccswitch.movementColorMode"
        static let customPalette = "ccswitch.customPalette"
        static let customMovement = "ccswitch.customMovement"
        static let providerBalances = "ccswitch.providerBalances"
        static let snapshot = "ccswitch.snapshot"
        static let lastStatus = "ccswitch.lastStatus"
        static let refreshInterval = "ccswitch.refreshIntervalSeconds"
        static let dashboardModules = "ccswitch.dashboardModules"
        static let providerBalanceOrder = "ccswitch.providerBalanceOrder"
        static let menuBarModuleOrder = "ccswitch.menuBarModuleOrder"
        static let launchAtLogin = "ccswitch.launchAtLogin"
        static let showDockIcon = "ccswitch.showDockIcon"
        static let menuBarPrimaryMetric = "ccswitch.menuBarPrimaryMetric"
        static let providerIconDefaultMigration = "ccswitch.providerIconDefaultMigration.v2"
        static let heatmapMediumMigration = "ccswitch.heatmapMediumMigration.v1"
    }

    private let suiteName: String
    private let storageDirectoryOverride: URL?

    public init(suiteName: String = SharedConstants.appGroupIdentifier, storageDirectory: URL? = nil) {
        self.suiteName = suiteName
        storageDirectoryOverride = storageDirectory
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func loadThemeMode() -> ThemeMode {
        guard let rawValue = defaults.string(forKey: Key.themeMode),
              let mode = ThemeMode(rawValue: rawValue) else {
            return loadThemeModeFromDisk() ?? .system
        }
        return mode
    }

    public func saveThemeMode(_ mode: ThemeMode) {
        defaults.set(mode.rawValue, forKey: Key.themeMode)
        saveThemeModeToDisk(mode)
    }

    public func loadMovementColorMode() -> MovementColorMode {
        guard let rawValue = defaults.string(forKey: Key.movementColorMode),
              let mode = MovementColorMode(rawValue: rawValue) else {
            return loadMovementColorModeFromDisk() ?? .redUpGreenDown
        }
        return mode
    }

    public func saveMovementColorMode(_ mode: MovementColorMode) {
        defaults.set(mode.rawValue, forKey: Key.movementColorMode)
        saveMovementColorModeToDisk(mode)
    }

    public func loadCustomPalette() -> [UInt32] {
        if let arr = defaults.array(forKey: Key.customPalette) as? [Int],
           arr.count == 7 {
            return arr.map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }
        }
        return loadCustomPaletteFromDisk() ?? CustomPalette.defaultHexes
    }

    public func saveCustomPalette(_ hexes: [UInt32]) {
        let safe = hexes.count == 7 ? hexes : CustomPalette.defaultHexes
        defaults.set(safe.map { Int(bitPattern: UInt($0)) }, forKey: Key.customPalette)
        saveCustomPaletteToDisk(safe)
    }

    public func loadCustomMovementColors() -> [UInt32] {
        if let arr = defaults.array(forKey: Key.customMovement) as? [Int],
           arr.count == 2 {
            return arr.map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }
        }
        return loadCustomMovementFromDisk() ?? CustomPalette.defaultMovementHexes
    }

    public func saveCustomMovementColors(_ hexes: [UInt32]) {
        let safe = hexes.count == 2 ? hexes : CustomPalette.defaultMovementHexes
        defaults.set(safe.map { Int(bitPattern: UInt($0)) }, forKey: Key.customMovement)
        saveCustomMovementToDisk(safe)
    }

    public func loadProviderBalances() -> [ProviderBalance] {
        if let balances = loadProviderBalancesFromDisk() {
            return balances
        }
        guard let data = defaults.data(forKey: Key.providerBalances) else { return [] }
        return (try? JSONDecoder().decode([ProviderBalance].self, from: data)) ?? []
    }

    public func saveProviderBalances(_ balances: [ProviderBalance]) {
        guard let data = try? JSONEncoder().encode(balances) else { return }
        defaults.set(data, forKey: Key.providerBalances)
        saveProviderBalancesToDisk(data)
    }

    private func providerBalancesURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.providerBalancesFileName) }
    }

    private func loadProviderBalancesFromDisk() -> [ProviderBalance]? {
        let decoder = JSONDecoder()
        for url in providerBalancesURLs() {
            guard let data = try? Data(contentsOf: url),
                  let balances = try? decoder.decode([ProviderBalance].self, from: data) else {
                continue
            }
            return balances
        }
        return nil
    }

    private func saveProviderBalancesToDisk(_ data: Data) {
        for url in providerBalancesURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
            } catch {
                continue
            }
        }
    }

    public func loadBookmarkData() -> Data? {
        defaults.data(forKey: Key.bookmarkData)
    }

    public func saveBookmarkData(_ data: Data) {
        defaults.set(data, forKey: Key.bookmarkData)
    }

    public func clearBookmarkData() {
        defaults.removeObject(forKey: Key.bookmarkData)
    }

    public func loadSnapshot() -> UsageSnapshot? {
        if let snapshot = loadSnapshotFromDisk() {
            return snapshot
        }
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
        saveSnapshotToDisk(data)
    }

    public func loadLastStatus() -> String? {
        defaults.string(forKey: Key.lastStatus)
    }

    public func saveLastStatus(_ status: String) {
        defaults.set(status, forKey: Key.lastStatus)
    }

    public func loadRefreshInterval() -> TimeInterval {
        let value = defaults.double(forKey: Key.refreshInterval)
        return value >= 30 ? value : 15 * 60
    }

    public func saveRefreshInterval(_ interval: TimeInterval) {
        defaults.set(max(30, interval), forKey: Key.refreshInterval)
    }

    public func loadDashboardConfiguration() -> DashboardConfigurationDocument {
        let decoder = JSONDecoder()
        for url in dashboardConfigurationURLs() {
            guard let data = try? Data(contentsOf: url),
                  let document = try? decoder.decode(DashboardConfigurationDocument.self, from: data),
                  document.schemaVersion == DashboardConfigurationDocument.currentSchemaVersion,
                  !document.modules.isEmpty else { continue }
            return document
        }
        return .initial
    }

    public func loadDashboardModules() -> [DashboardModule] {
        loadDashboardConfiguration().modules
    }

    /// Provider 图标功能首次上线时曾错误地以关闭状态写入默认卡片；只修复一次，之后尊重用户手动关闭。
    public func enableProviderIconsByDefaultIfNeeded() {
        guard !defaults.bool(forKey: Key.providerIconDefaultMigration) else { return }
        var modules = loadDashboardModules()
        var changed = false
        for index in modules.indices where modules[index].kind == .providerBalances && !modules[index].showsProviderIcons {
            modules[index].showsProviderIcons = true
            changed = true
        }
        if changed { saveDashboardModules(modules) }
        defaults.set(true, forKey: Key.providerIconDefaultMigration)
    }

    public func migrateHeatmapCardsToMediumIfNeeded() {
        guard !defaults.bool(forKey: Key.heatmapMediumMigration) else { return }
        var modules = loadDashboardModules()
        var changed = false
        for index in modules.indices where modules[index].kind == .usageHeatmap && modules[index].size != .medium {
            modules[index].size = .medium
            changed = true
        }
        if changed { saveDashboardModules(modules) }
        defaults.set(true, forKey: Key.heatmapMediumMigration)
    }

    @discardableResult
    public func saveDashboardModules(_ modules: [DashboardModule]) -> DashboardConfigurationDocument {
        let current = loadDashboardConfiguration()
        let safeModules = modules.isEmpty ? DashboardModule.defaults : modules
        let document = DashboardConfigurationDocument(revision: current.revision + 1, modules: safeModules)
        guard let data = try? JSONEncoder().encode(document) else { return current }
        for url in dashboardConfigurationURLs() {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } catch { continue }
        }
        return document
    }

    private func dashboardConfigurationURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.dashboardConfigurationFileName) }
    }

    public func loadProviderBalanceOrder() -> [String] {
        defaults.stringArray(forKey: Key.providerBalanceOrder) ?? []
    }

    public func saveProviderBalanceOrder(_ ids: [String]) {
        defaults.set(ids, forKey: Key.providerBalanceOrder)
    }

    public func loadMenuBarModuleOrder() -> [UUID] {
        (defaults.stringArray(forKey: Key.menuBarModuleOrder) ?? []).compactMap(UUID.init(uuidString:))
    }

    public func saveMenuBarModuleOrder(_ ids: [UUID]) {
        defaults.set(ids.map(\.uuidString), forKey: Key.menuBarModuleOrder)
    }

    public func loadLaunchAtLogin() -> Bool {
        defaults.object(forKey: Key.launchAtLogin) == nil ? true : defaults.bool(forKey: Key.launchAtLogin)
    }

    public func saveLaunchAtLogin(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.launchAtLogin)
    }

    public func loadShowDockIcon() -> Bool {
        defaults.object(forKey: Key.showDockIcon) == nil ? true : defaults.bool(forKey: Key.showDockIcon)
    }

    public func saveShowDockIcon(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.showDockIcon)
    }

    public func loadMenuBarPrimaryMetric() -> MenuBarPrimaryMetric {
        MenuBarPrimaryMetric(rawValue: defaults.string(forKey: Key.menuBarPrimaryMetric) ?? "") ?? .iconOnly
    }

    public func saveMenuBarPrimaryMetric(_ metric: MenuBarPrimaryMetric) {
        defaults.set(metric.rawValue, forKey: Key.menuBarPrimaryMetric)
    }

    public func recordRangeDebug(source: String, range: ChartRange, appID: String, bucketCount: Int) {
        let object: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "source": source,
            "range": range.rawValue,
            "appID": appID,
            "bucketCount": bucketCount,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        for directory in storageDirectories() {
            let url = directory.appendingPathComponent(SharedConstants.rangeDebugFileName)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url)
                }
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } catch {
                continue
            }
        }
    }

    private func loadSnapshotFromDisk() -> UsageSnapshot? {
        let decoder = JSONDecoder()
        for url in snapshotURLs() {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(UsageSnapshot.self, from: data) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private func saveSnapshotToDisk(_ data: Data) {
        for url in snapshotURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
            } catch {
                continue
            }
        }
    }

    private func loadThemeModeFromDisk() -> ThemeMode? {
        for url in themeURLs() {
            guard let rawValue = try? String(contentsOf: url)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let mode = ThemeMode(rawValue: rawValue) else {
                continue
            }
            return mode
        }
        return nil
    }

    private func saveThemeModeToDisk(_ mode: ThemeMode) {
        for url in themeURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try mode.rawValue.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
    }

    private func loadMovementColorModeFromDisk() -> MovementColorMode? {
        for url in movementColorURLs() {
            guard let rawValue = try? String(contentsOf: url)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let mode = MovementColorMode(rawValue: rawValue) else {
                continue
            }
            return mode
        }
        return nil
    }

    private func saveMovementColorModeToDisk(_ mode: MovementColorMode) {
        for url in movementColorURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try mode.rawValue.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
    }

    private func snapshotURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.snapshotFileName) }
    }

    private func themeURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.themeFileName) }
    }

    private func movementColorURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.movementColorFileName) }
    }

    private func customPaletteURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.customPaletteFileName) }
    }

    private func loadCustomPaletteFromDisk() -> [UInt32]? {
        for url in customPaletteURLs() {
            guard let text = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines),
                  let data = text.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([UInt32].self, from: data),
                  arr.count == 7 else {
                continue
            }
            return arr
        }
        return nil
    }

    private func saveCustomPaletteToDisk(_ hexes: [UInt32]) {
        let text = String(data: (try? JSONEncoder().encode(hexes)) ?? Data(), encoding: .utf8) ?? "[]"
        for url in customPaletteURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
    }

    private func customMovementURLs() -> [URL] {
        storageDirectories().map { $0.appendingPathComponent(SharedConstants.customMovementFileName) }
    }

    private func loadCustomMovementFromDisk() -> [UInt32]? {
        for url in customMovementURLs() {
            guard let text = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines),
                  let data = text.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([UInt32].self, from: data),
                  arr.count == 2 else {
                continue
            }
            return arr
        }
        return nil
    }

    private func saveCustomMovementToDisk(_ hexes: [UInt32]) {
        let text = String(data: (try? JSONEncoder().encode(hexes)) ?? Data(), encoding: .utf8) ?? "[]"
        for url in customMovementURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
    }

    private func storageDirectories() -> [URL] {
        if let storageDirectoryOverride { return [storageDirectoryOverride] }
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier) {
            urls.append(group
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(SharedConstants.supportDirectoryName, isDirectory: true))
        }
        let home = realHomeDirectory()
        urls.append(home
            .appendingPathComponent("Library/Containers/\(SharedConstants.widgetBundleIdentifier)/Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(SharedConstants.supportDirectoryName, isDirectory: true))
        urls.append(home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(SharedConstants.supportDirectoryName, isDirectory: true))
        return uniqueURLs(urls)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}

public enum SnapshotLoadingMode: Sendable {
    case app
    case widget
}

public struct SnapshotLoader {
    private let store: SharedUsageStore
    private let calendar: Calendar
    private let mode: SnapshotLoadingMode

    public init(
        store: SharedUsageStore = SharedUsageStore(),
        calendar: Calendar = .current,
        mode: SnapshotLoadingMode = .app
    ) {
        self.store = store
        self.calendar = calendar
        self.mode = mode
    }

    public func load(now: Date = Date()) -> DataState {
        if mode == .widget {
            return loadStoredSnapshotOnly()
        }

        guard let bookmarkData = store.loadBookmarkData() else {
            if let state = loadDefaultDatabase(now: now) {
                return state
            }
            if let snapshot = store.loadSnapshot() {
                return .cached(snapshot, reason: "显示 App 最近刷新数据")
            }
            return .disconnected
        }

        var isStale = false
        do {
            let folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else {
                return cachedOrFailed("访问授权已过期，请在 App 中重新连接 CC Switch 数据。")
            }

            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { folderURL.stopAccessingSecurityScopedResource() }
            }

            let databaseURL = folderURL.appendingPathComponent(SharedConstants.databaseFileName)
            let snapshot = try SQLiteUsageRepository(
                databaseURL: databaseURL,
                calendar: calendar
            ).loadSnapshot(now: now)
            store.saveSnapshot(snapshot)
            store.saveLastStatus("更新于 \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            return .live(snapshot)
        } catch {
            return cachedOrFailed(error.localizedDescription)
        }
    }

    private func loadStoredSnapshotOnly() -> DataState {
        if let snapshot = store.loadSnapshot() {
            return .cached(snapshot, reason: "显示 App 最近刷新数据")
        }
        return .disconnected
    }

    private func cachedOrFailed(_ reason: String) -> DataState {
        if let snapshot = store.loadSnapshot() {
            return .cached(snapshot, reason: reason)
        }
        return .failed(reason)
    }

    private func loadDefaultDatabase(now: Date) -> DataState? {
        let databaseURL = realHomeDirectory()
            .appendingPathComponent(".cc-switch")
            .appendingPathComponent(SharedConstants.databaseFileName)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        do {
            let snapshot = try SQLiteUsageRepository(
                databaseURL: databaseURL,
                calendar: calendar
            ).loadSnapshot(now: now)
            store.saveSnapshot(snapshot)
            return .live(snapshot)
        } catch {
            return cachedOrFailed(error.localizedDescription)
        }
    }
}

public func realHomeDirectory() -> URL {
    if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
