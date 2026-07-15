import XCTest
@testable import CCSwitchCore

final class DashboardModuleTests: XCTestCase {
    func testOnlyApprovedModuleNamesChange() {
        XCTAssertEqual(ModuleKind.appCard.title, "应用用量")
        XCTAssertEqual(ModuleKind.modelRanking.title, "模型用量排行")
        XCTAssertEqual(ModuleKind.todayOverview.title, "今日总览")
        XCTAssertEqual(ModuleKind.averageComparison.title, "今日 vs 7 日均值")
        XCTAssertEqual(ModuleKind.topModel.title, "Top 模型")
        XCTAssertEqual(ModuleKind.usageTrend.title, "用量趋势")
        XCTAssertEqual(ModuleKind.usageHeatmap.title, "热力图")
        XCTAssertEqual(ModuleKind.costOverview.title, "费用概览")
        XCTAssertEqual(ModuleKind.providerBalances.title, "账户")
    }

    func testHeatmapWidgetDoesNotRequireIntentConfiguration() {
        XCTAssertFalse(ModuleKind.usageHeatmap.requiresWidgetIntentConfiguration)
        XCTAssertTrue(ModuleKind.usageTrend.requiresWidgetIntentConfiguration)
    }

    func testStandaloneWidgetConfigurationBuildsRenderModuleWithoutPublishedDashboardCard() {
        let configuration = StandaloneWidgetConfiguration(
            appID: "claude",
            range: .thirtyDays,
            trendStyle: .lines,
            trendScope: .byModel,
            modelIDs: ["claude-opus-4-8"],
            providerQuotaDisplayMode: .remaining,
            showsProviderIcons: false,
            providerIDs: ["provider-a", "provider-b"]
        )

        let appModule = configuration.module(kind: .appCard, size: .small)
        XCTAssertEqual(appModule.configuration, .appCard(appID: "claude", range: .thirtyDays))
        XCTAssertFalse(appModule.isPublishedToDesktop)

        let trendModule = configuration.module(kind: .usageTrend, size: .large)
        XCTAssertEqual(trendModule.configuration, .usageTrend(range: .thirtyDays, style: .lines))
        XCTAssertEqual(trendModule.trendScope, .byModel)
        XCTAssertEqual(trendModule.trendModelIDs, ["claude-opus-4-8"])

        let balanceModule = configuration.module(kind: .providerBalances, size: .medium)
        XCTAssertEqual(balanceModule.providerQuotaDisplayMode, .remaining)
        XCTAssertFalse(balanceModule.showsProviderIcons)
        XCTAssertEqual(balanceModule.providerIDs, ["provider-a", "provider-b"])
    }

    func testStandaloneTrendDefaultsToAutomaticTopModelsUntilUserSelectsModels() {
        let automatic = StandaloneWidgetConfiguration(trendScope: .byModel)
            .module(kind: .usageTrend, size: .large)
        XCTAssertFalse(automatic.trendModelSelectionInitialized)

        let explicit = StandaloneWidgetConfiguration(
            trendScope: .byModel,
            modelIDs: ["gpt-5.6-sol"],
            modelSelectionInitialized: true
        ).module(kind: .usageTrend, size: .large)
        XCTAssertTrue(explicit.trendModelSelectionInitialized)
        XCTAssertEqual(explicit.trendModelIDs, ["gpt-5.6-sol"])
    }

    func testDashboardModuleRoundTripsWithConfiguration() throws {
        let module = DashboardModule(
            id: UUID(uuidString: "7F850B75-3E91-42A5-9782-13B3B3E9D28D")!,
            kind: .usageTrend,
            size: .large,
            configuration: .usageTrend(range: .thirtyDays, style: .lines),
            showInMenuBar: true,
            trendScope: .total
        )

        let data = try JSONEncoder().encode(module)
        let decoded = try JSONDecoder().decode(DashboardModule.self, from: data)

        XCTAssertEqual(decoded, module)
    }

    func testLegacyModuleDefaultsTrendScopeToByTool() throws {
        let module = DashboardModule(kind: .usageTrend, size: .large, configuration: .usageTrend(range: .sevenDays, style: .lines))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(module)) as? [String: Any])
        object.removeValue(forKey: "trendScope")

        let legacy = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try JSONDecoder().decode(DashboardModule.self, from: legacy).trendScope, .byTool)
    }

    func testTrendModelSelectionPersistsAndLegacyModulesInferInitialization() throws {
        let module = DashboardModule(
            kind: .usageTrend,
            size: .large,
            configuration: .usageTrend(range: .sevenDays, style: .lines),
            trendScope: .byModel,
            trendModelIDs: ["gpt-5.5", "glm-5.2"]
        )
        let roundTrip = try JSONDecoder().decode(DashboardModule.self, from: JSONEncoder().encode(module))
        XCTAssertEqual(roundTrip.trendModelIDs, ["gpt-5.5", "glm-5.2"])
        XCTAssertTrue(roundTrip.trendModelSelectionInitialized)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(module)) as? [String: Any])
        object.removeValue(forKey: "trendModelIDs")
        object.removeValue(forKey: "trendModelSelectionInitialized")
        let legacy = try JSONDecoder().decode(DashboardModule.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.trendModelIDs, [])
        XCTAssertFalse(legacy.trendModelSelectionInitialized)
    }

    func testTrendModelSelectionDefaultsToTopSixAndExplicitEmptyMeansNone() {
        let available = (1 ... 8).map { "model-\($0)" }
        XCTAssertEqual(
            TrendModelSelection.visible(savedIDs: [], availableIDs: available, isInitialized: false),
            Array(available.prefix(6))
        )
        XCTAssertEqual(
            TrendModelSelection.visible(savedIDs: [], availableIDs: available, isInitialized: true),
            []
        )
        XCTAssertEqual(
            TrendModelSelection.visible(savedIDs: ["missing", "model-3", "model-1"], availableIDs: available, isInitialized: true),
            ["model-3", "model-1"]
        )
        XCTAssertEqual(
            TrendModelSelection.moving(["gpt-5.5", "glm-5.2", "claude-sonnet"], sourceID: "claude-sonnet", before: "gpt-5.5"),
            ["claude-sonnet", "gpt-5.5", "glm-5.2"]
        )
    }

    func testTrendBarWidthExpandsForFewerBucketsAndNeverCollapses() {
        let seven = TrendBarLayout.width(availableWidth: 296, bucketCount: 7)
        let thirty = TrendBarLayout.width(availableWidth: 296, bucketCount: 30)

        XCTAssertGreaterThan(seven, thirty)
        XCTAssertGreaterThanOrEqual(thirty, 3)
        XCTAssertLessThanOrEqual(seven, 28)
    }

    func testTrendAxisGeometryAlignsMarksGridAndLabels() {
        XCTAssertEqual(TrendAxisGeometry.domain(bucketCount: 1), -0.5 ... 0.5)
        XCTAssertEqual(TrendAxisGeometry.domain(bucketCount: 7), -0.5 ... 6.5)
        XCTAssertEqual(TrendAxisGeometry.domain(bucketCount: 30), -0.5 ... 29.5)
        XCTAssertTrue(ChartRange.thirtyDays.axisLabelIndices(bucketCount: 30).allSatisfy {
            TrendAxisGeometry.domain(bucketCount: 30).contains(Double($0))
        })
    }

    func testTrendAxisLayoutSharesOneDomainForGridLabelsAndHover() {
        let layout = TrendAxisLayout(bucketCount: 30, range: .thirtyDays)

        XCTAssertEqual(layout.domain, -0.5 ... 29.5)
        XCTAssertEqual(layout.gridIndices, layout.labelIndices)
        XCTAssertEqual(layout.nearestBucket(for: -0.49), 0)
        XCTAssertEqual(layout.nearestBucket(for: 12.4), 12)
        XCTAssertEqual(layout.nearestBucket(for: 29.49), 29)
        XCTAssertNil(TrendAxisLayout(bucketCount: 0, range: .sevenDays).nearestBucket(for: 0))
    }

    func testTrendAxisTypographyOffsetsLabelsAroundGridCenters() {
        let layout = TrendAxisLayout(bucketCount: 30, range: .thirtyDays)
        XCTAssertEqual(layout.labelOffsetX, -4)
        XCTAssertEqual(layout.xAxisFontSize, 8.5)
        XCTAssertEqual(layout.yAxisFontSize, 8.5)
    }

    func testHeatmapNoticeStaysInsideCardInsteadOfCoveringHoveredCell() {
        let position = HeatmapGeometry.noticePosition(
            hoverLocation: CGPoint(x: 30, y: 18),
            noticeSize: CGSize(width: 120, height: 44),
            canvasSize: CGSize(width: 300, height: 120)
        )
        XCTAssertGreaterThanOrEqual(position.y - 22, 4)
        XCTAssertGreaterThanOrEqual(position.x - 60, 4)
    }

    func testHeatmapNoticeAndMonthGridUseCompactSpacing() {
        let hover = CGPoint(x: 100, y: 50)
        let position = HeatmapGeometry.noticePosition(
            hoverLocation: hover,
            noticeSize: CGSize(width: 120, height: 44),
            canvasSize: CGSize(width: 500, height: 180)
        )
        XCTAssertGreaterThan(position.x, hover.x)
        XCTAssertGreaterThanOrEqual(position.x - 60, 4)
        XCTAssertLessThanOrEqual(position.x + 60, 496)
        XCTAssertGreaterThanOrEqual(position.y - 22, 4)
        XCTAssertLessThanOrEqual(position.y + 22, 176)
        XCTAssertEqual(HeatmapGeometry.monthGridSpacing, 1.25)
    }

    func testHeatmapNoticeFlipsInsideCardAtRightEdge() {
        let position = HeatmapGeometry.noticePosition(
            hoverLocation: CGPoint(x: 290, y: 16),
            noticeSize: CGSize(width: 150, height: 50),
            canvasSize: CGSize(width: 300, height: 120)
        )
        XCTAssertLessThan(position.x, 290)
        XCTAssertGreaterThanOrEqual(position.x - 75, 4)
        XCTAssertLessThanOrEqual(position.x + 75, 296)
        XCTAssertGreaterThanOrEqual(position.y - 25, 4)
    }

    func testTrendLegendLayoutWrapsAtThreeAndLimitsVisibleSeries() {
        XCTAssertEqual(TrendLegendLayout.rowCount(seriesCount: 2), 1)
        XCTAssertEqual(TrendLegendLayout.rowCount(seriesCount: 3), 2)
        XCTAssertEqual(TrendLegendLayout.rowCount(seriesCount: 6), 2)
        XCTAssertEqual(TrendLegendLayout.visibleCount(seriesCount: 13), 6)
        XCTAssertEqual(TrendLegendLayout.remainingCount(seriesCount: 13), 7)
    }

    func testHeatmapMonthLabelIncludesWeekdayGutterOffset() {
        XCTAssertEqual(
            HeatmapGeometry.monthLabelLeading(gridLeading: 13, weekdayGutter: 13, week: 2, pitch: 12),
            50
        )
    }

    func testDesktopBindingTitlesDescribeConfigurationWithoutUUIDs() {
        let ranking = DashboardModule(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .modelRanking,
            size: .medium,
            configuration: .modelRanking(range: .sevenDays)
        )
        let trend = DashboardModule(
            kind: .usageTrend,
            size: .large,
            configuration: .usageTrend(range: .thirtyDays, style: .stackedBars),
            trendScope: .total
        )

        XCTAssertEqual(ranking.desktopBindingTitle, "模型用量排行 · 7 天 · 中号")
        XCTAssertEqual(trend.desktopBindingTitle, "用量趋势 · 30 天 · 堆叠柱状图 · 总消耗量")
        XCTAssertFalse(ranking.desktopBindingTitle.contains("AAAAAAAA"))
    }

    func testEveryTrendScopeHasAReadableConfigurationLabel() {
        XCTAssertEqual(ModuleTrendScope.byTool.title, "按工具")
        XCTAssertEqual(ModuleTrendScope.byModel.title, "按模型")
        XCTAssertEqual(ModuleTrendScope.total.title, "总消耗量")

        let trend = DashboardModule(
            kind: .usageTrend,
            size: .large,
            configuration: .usageTrend(range: .sevenDays, style: .lines),
            trendScope: .byModel
        )
        XCTAssertEqual(trend.desktopBindingTitle, "用量趋势 · 7 天 · 折线图 · 按模型 · 默认前 6")
    }

    func testDuplicateDesktopBindingTitlesUseReadableCopySuffix() {
        let first = DashboardModule(kind: .todayOverview, size: .small)
        let second = DashboardModule(kind: .todayOverview, size: .small)

        let titles = DashboardModule.desktopBindingTitles(in: [first, second])

        XCTAssertEqual(titles[first.id], "今日总览")
        XCTAssertEqual(titles[second.id], "今日总览 · 副本 2")
    }

    func testKindRejectsUnsupportedSizes() {
        XCTAssertTrue(ModuleKind.todayOverview.supports(.small))
        XCTAssertFalse(ModuleKind.todayOverview.supports(.medium))
        XCTAssertTrue(ModuleKind.providerBalances.supports(.medium))
        XCTAssertTrue(ModuleKind.providerBalances.supports(.large))
        XCTAssertFalse(ModuleKind.providerBalances.supports(.small))
        XCTAssertTrue(ModuleKind.usageHeatmap.supports(.medium))
        XCTAssertFalse(ModuleKind.usageHeatmap.supports(.large))
    }

    func testProviderBalanceOrderingAppendsNewIDsAndRetainsMissingIDs() {
        let result = ProviderBalanceOrder.reconcile(
            savedIDs: ["codex", "missing", "claude"],
            availableIDs: ["claude", "deepseek", "codex"]
        )

        XCTAssertEqual(result.savedIDs, ["codex", "missing", "claude", "deepseek"])
        XCTAssertEqual(result.visibleIDs, ["codex", "claude", "deepseek"])
    }

    func testBalanceGroupsUseFamilyCapacity() {
        let ids = (1 ... 8).map(String.init)

        XCTAssertEqual(ProviderBalanceOrder.group(ids: ids, index: 1, size: .medium), ["4", "5", "6"])
        XCTAssertEqual(ProviderBalanceOrder.group(ids: ids, index: 1, size: .large), ["7", "8"])
    }

    func testDefaultModulesExcludeLegacyTrendAndIncludeBalances() {
        let modules = DashboardModule.defaults

        XCTAssertEqual(modules.filter { $0.kind == .usageTrend }.count, 1)
        XCTAssertTrue(modules.contains { $0.kind == .providerBalances && $0.size == .medium })
        XCTAssertEqual(Set(modules.map(\.id)).count, modules.count)
        XCTAssertTrue(modules.first(where: { $0.kind == .providerBalances })?.showsProviderIcons == true)
        XCTAssertEqual(modules.first(where: { $0.kind == .usageHeatmap })?.size, .medium)
    }

    func testHeatmapCalendarLayoutUsesMondayRowsAndWholeWeekColumns() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let dates = [13, 14, 15, 16, 17, 18, 19, 20].compactMap {
            calendar.date(from: DateComponents(year: 2026, month: 1, day: $0))
        }
        let days = dates.map {
            DailyUsage(
                date: $0,
                totals: UsageTotals(totalTokens: Int64(calendar.component(.day, from: $0)))
            )
        }

        let layout = HeatmapCalendarLayout(days: days, calendar: calendar)

        XCTAssertEqual(layout.weekCount, 2)
        XCTAssertNil(layout.day(week: 0, weekday: 0)) // Jan 13 is Tuesday.
        XCTAssertEqual(layout.day(week: 0, weekday: 1)?.totalTokens, 13)
        XCTAssertEqual(layout.day(week: 0, weekday: 6)?.totalTokens, 18)
        XCTAssertEqual(layout.day(week: 1, weekday: 0)?.totalTokens, 19)
        XCTAssertEqual(layout.day(week: 1, weekday: 1)?.totalTokens, 20)
        XCTAssertFalse(layout.hasDay(week: 1, weekday: 2))
        XCTAssertEqual(layout.state(week: 0, weekday: 0), .padding)
        XCTAssertEqual(layout.state(week: 0, weekday: 1), .data(days[0]))
        XCTAssertEqual(layout.state(week: 1, weekday: 2), .future)
        XCTAssertEqual(layout.monthMarkers.first?.week, 0)
    }

    func testHeatmapIntensityUsesDistributionLevelsInsteadOfOneLowOpacityRamp() {
        let values: [Int64] = [0, 10, 20, 30, 40, 10_000]

        XCTAssertEqual(HeatmapIntensity.level(for: 0, among: values), 0)
        XCTAssertEqual(HeatmapIntensity.level(for: 10, among: values), 1)
        XCTAssertEqual(HeatmapIntensity.level(for: 20, among: values), 2)
        XCTAssertEqual(HeatmapIntensity.level(for: 30, among: values), 3)
        XCTAssertEqual(HeatmapIntensity.level(for: 40, among: values), 4)
        XCTAssertEqual(HeatmapIntensity.level(for: 10_000, among: values), 4)
    }

    func testSharedStorePersistsModulesBalanceOrderAndRunSettings() {
        let suite = "DashboardModuleTests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let store = SharedUsageStore(suiteName: suite, storageDirectory: directory)
        let modules = [DashboardModule(kind: .providerBalances, size: .large, configuration: .providerBalances(groupIndex: 1))]

        store.saveDashboardModules(modules)
        store.saveProviderBalanceOrder(["claude", "codex"])
        store.saveLaunchAtLogin(true)
        store.saveShowDockIcon(false)

        XCTAssertEqual(store.loadDashboardModules(), modules)
        XCTAssertEqual(store.loadProviderBalanceOrder(), ["claude", "codex"])
        XCTAssertTrue(store.loadLaunchAtLogin())
        XCTAssertFalse(store.loadShowDockIcon())
    }

    func testProviderIconDefaultMigrationRestoresIconsOnlyOnce() {
        let suite = "ProviderIconMigration-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let store = SharedUsageStore(suiteName: suite, storageDirectory: directory)
        let module = DashboardModule(kind: .providerBalances, size: .medium, showsProviderIcons: false)
        store.saveDashboardModules([module])

        store.enableProviderIconsByDefaultIfNeeded()
        XCTAssertTrue(store.loadDashboardModules()[0].showsProviderIcons)

        var deliberatelyHidden = store.loadDashboardModules()[0]
        deliberatelyHidden.showsProviderIcons = false
        store.saveDashboardModules([deliberatelyHidden])
        store.enableProviderIconsByDefaultIfNeeded()
        XCTAssertFalse(store.loadDashboardModules()[0].showsProviderIcons)
    }

    func testHeatmapSizeMigrationConvertsExistingLargeCardToMedium() {
        let suite = "HeatmapSizeMigration-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let store = SharedUsageStore(suiteName: suite, storageDirectory: directory)
        store.saveDashboardModules([DashboardModule(kind: .usageHeatmap, size: .large)])

        store.migrateHeatmapCardsToMediumIfNeeded()

        XCTAssertEqual(store.loadDashboardModules()[0].size, .medium)
    }

    func testDashboardConfigurationUsesVersionedAtomicDocumentAndIncrementsRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DashboardConfig-\(UUID().uuidString)", isDirectory: true)
        let store = SharedUsageStore(suiteName: "DashboardConfig-\(UUID().uuidString)", storageDirectory: directory)
        XCTAssertEqual(store.loadDashboardConfiguration(), .initial)

        let modules = [DashboardModule(kind: .appCard, size: .small, configuration: .appCard(appID: "claude", range: .thirtyDays))]
        let saved = store.saveDashboardModules(modules)

        XCTAssertEqual(saved.schemaVersion, DashboardConfigurationDocument.currentSchemaVersion)
        XCTAssertEqual(saved.revision, 2)
        XCTAssertEqual(store.loadDashboardConfiguration(), saved)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [SharedConstants.dashboardConfigurationFileName])
    }

    func testCorruptDashboardConfigurationFallsBackToFreshDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DashboardCorrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent(SharedConstants.dashboardConfigurationFileName))
        let store = SharedUsageStore(suiteName: "DashboardCorrupt-\(UUID().uuidString)", storageDirectory: directory)

        XCTAssertEqual(store.loadDashboardConfiguration(), .initial)
    }

    func testFailedBalanceRefreshKeepsLastSuccessfulValue() {
        let old = ProviderBalance(name: "Claude", appType: "claude", remaining: 20, unit: "USD", queriedAt: Date(timeIntervalSince1970: 10))
        let failed = ProviderBalance(name: "Claude", appType: "claude", unit: "—", isValid: false, errorMessage: "网络错误", queriedAt: Date(timeIntervalSince1970: 20))

        let merged = ProviderBalanceMerge.merge(previous: [old], refreshed: [failed])

        XCTAssertEqual(merged.first?.remaining, 20)
        XCTAssertEqual(merged.first?.errorMessage, "网络错误")
        XCTAssertEqual(merged.first?.queriedAt, old.queriedAt)
    }

    func testFailedBalanceRefreshUsesLatestProviderNameAndIcon() {
        let old = ProviderBalance(id: "provider-1", name: "旧名称", appType: "claude", remaining: 20, unit: "USD", queriedAt: Date(timeIntervalSince1970: 10), iconName: "deepseek")
        let failed = ProviderBalance(id: "provider-1", name: "新名称", appType: "claude", unit: "—", isValid: false, errorMessage: "网络错误", queriedAt: Date(timeIntervalSince1970: 20), iconName: "zhipu")

        let merged = ProviderBalanceMerge.merge(previous: [old], refreshed: [failed])

        XCTAssertEqual(merged.first?.name, "新名称")
        XCTAssertEqual(merged.first?.iconName, "zhipu")
        XCTAssertEqual(merged.first?.remaining, 20)
    }

    func testWidgetPresentationMetricsKeepNativeFamilyGeometry() {
        XCTAssertEqual(WidgetPresentationMetrics.width(for: .small), 160)
        XCTAssertEqual(WidgetPresentationMetrics.width(for: .medium), 336)
        XCTAssertEqual(WidgetPresentationMetrics.height(for: .medium), 160)
        XCTAssertEqual(WidgetPresentationMetrics.width(for: .large), 336)
        XCTAssertEqual(WidgetPresentationMetrics.height(for: .large), 336)
        XCTAssertEqual(WidgetPresentationMetrics.insets(for: .small), 18)
        XCTAssertEqual(WidgetPresentationMetrics.insets(for: .large), 20)
    }

    func testLegacyModuleWithoutPublishedFlagDefaultsToPublished() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"todayOverview","size":"small","configuration":{"none":{}},"showInMenuBar":true}
        """.data(using: .utf8)!

        let module = try JSONDecoder().decode(DashboardModule.self, from: legacy)

        XCTAssertTrue(module.isPublishedToDesktop)
        XCTAssertEqual(module.providerQuotaDisplayMode, .used)
    }

    func testDesktopCandidatesRequirePublishedMatchingKindAndSize() {
        let modules = [
            DashboardModule(kind: .appCard, size: .small, isPublishedToDesktop: true),
            DashboardModule(kind: .appCard, size: .small, isPublishedToDesktop: false),
            DashboardModule(kind: .todayOverview, size: .small, isPublishedToDesktop: true),
            DashboardModule(kind: .modelRanking, size: .large, isPublishedToDesktop: true),
        ]

        XCTAssertEqual(DashboardModule.desktopCandidates(in: modules, kind: .appCard, size: .small).count, 1)
        XCTAssertEqual(DashboardModule.desktopCandidates(in: modules, kind: .modelRanking, size: .medium).count, 0)
        XCTAssertEqual(DashboardModule.desktopCandidates(in: modules, kind: .modelRanking, size: .large).count, 1)
    }

    func testResolvingExplicitUnpublishedModuleDoesNotFallback() {
        let published = DashboardModule(kind: .appCard, size: .small, isPublishedToDesktop: true)
        let unpublished = DashboardModule(kind: .appCard, size: .small, isPublishedToDesktop: false)

        let result = DashboardModule.resolveDesktopModule(
            id: unpublished.id.uuidString,
            in: [published, unpublished],
            kind: .appCard,
            size: .small
        )

        XCTAssertEqual(result, .unpublished)
    }

    func testModuleReorderingMovesOnlyTheDraggedCard() {
        let modules = DashboardModule.defaults
        let reordered = DashboardModule.moving(modules, sourceID: modules[0].id, targetID: modules[3].id, edge: .before)

        XCTAssertEqual(reordered.map(\.id), [modules[1].id, modules[2].id, modules[0].id] + modules.dropFirst(3).map(\.id))
        XCTAssertEqual(Set(reordered.map(\.id)), Set(modules.map(\.id)))
    }

    func testMovingModuleUsesTargetEdgeWithoutForwardIndexDrift() {
        let modules = DashboardModule.defaults

        let before = DashboardModule.moving(modules, sourceID: modules[0].id, targetID: modules[3].id, edge: .before)
        XCTAssertEqual(before.prefix(4).map(\.id), [modules[1].id, modules[2].id, modules[0].id, modules[3].id])

        let after = DashboardModule.moving(modules, sourceID: modules[0].id, targetID: modules[3].id, edge: .after)
        XCTAssertEqual(after.prefix(4).map(\.id), [modules[1].id, modules[2].id, modules[3].id, modules[0].id])

        let backwardAfter = DashboardModule.moving(modules, sourceID: modules[3].id, targetID: modules[0].id, edge: .after)
        XCTAssertEqual(backwardAfter.prefix(4).map(\.id), [modules[0].id, modules[3].id, modules[1].id, modules[2].id])
    }

    func testQuotaPresentationCalculatesUsedRemainingAndResetPrecision() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fiveHour = QuotaTier(name: "five_hour", utilization: 32, resetsAt: now.addingTimeInterval(2 * 3600 + 36 * 60))
        let week = QuotaTier(name: "seven_day", utilization: 68, resetsAt: now.addingTimeInterval(4 * 86400 + 5 * 3600 + 40 * 60))

        XCTAssertEqual(ProviderQuotaPresentation.percent(for: fiveHour, mode: .used), 32)
        XCTAssertEqual(ProviderQuotaPresentation.percent(for: fiveHour, mode: .remaining), 68)
        XCTAssertEqual(ProviderQuotaPresentation.resetText(for: fiveHour, period: .fiveHour, now: now), "2h 36min")
        XCTAssertEqual(ProviderQuotaPresentation.resetText(for: week, period: .week, now: now), "4d 5h")
        XCTAssertEqual(ProviderQuotaPresentation.resetText(for: fiveHour, period: .fiveHour, now: now.addingTimeInterval(3 * 3600)), "待刷新")
    }

    func testQuotaPresentationFindsCanonicalFiveHourAndWeekTiers() {
        let tiers = [
            QuotaTier(name: "secondary_window", utilization: 70),
            QuotaTier(name: "primary_window", utilization: 20),
        ]

        XCTAssertEqual(ProviderQuotaPresentation.tier(for: .fiveHour, in: tiers)?.utilization, 20)
        XCTAssertEqual(ProviderQuotaPresentation.tier(for: .week, in: tiers)?.utilization, 70)
    }

    func testCardUpdateTimeUsesConcreteLocalTimeAndCalendarContext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 20, minute: 40)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 19, minute: 5)))
        let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 23, minute: 9)))
        let older = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 8, minute: 3)))

        XCTAssertEqual(CardUpdateTimeFormatter.string(from: today, now: now, calendar: calendar), "19:05")
        XCTAssertEqual(CardUpdateTimeFormatter.string(from: yesterday, now: now, calendar: calendar), "昨天 23:09")
        XCTAssertEqual(CardUpdateTimeFormatter.string(from: older, now: now, calendar: calendar), "7月8日 08:03")
    }

    func testUnavailableCardRenderModelNeverAllowsContentRendering() {
        let model = CardRenderModel(
            module: DashboardModule(kind: .appCard, size: .small),
            snapshot: .empty,
            themeMode: .dark,
            movementColorMode: .redUpGreenDown,
            unavailableMessage: "此 App 卡片已取消供桌面使用"
        )

        XCTAssertFalse(model.shouldRenderContent)
    }

    func testMenuBarModulesPreserveDashboardOrderAndFilterDisabledCards() {
        var modules = Array(DashboardModule.defaults.prefix(4))
        modules[1].showInMenuBar = false
        modules[3].showInMenuBar = false

        XCTAssertEqual(DashboardModule.menuBarModules(in: modules).map(\.id), [modules[0].id, modules[2].id])
    }

    func testMenuBarOrderReconcilesAndMovesIndependently() {
        let modules = Array(DashboardModule.defaults.prefix(4))
        let saved = [modules[2].id, modules[0].id]
        let reconciled = MenuBarModuleOrder.reconcile(saved: saved, modules: modules)
        XCTAssertEqual(reconciled, [modules[2].id, modules[0].id, modules[1].id, modules[3].id])

        let moved = MenuBarModuleOrder.moving(reconciled, sourceID: modules[2].id, targetID: modules[1].id, edge: .after)
        XCTAssertEqual(moved, [modules[0].id, modules[1].id, modules[2].id, modules[3].id])
        XCTAssertEqual(modules.map(\.id), DashboardModule.defaults.prefix(4).map(\.id))
    }

    func testMenuBarPackingSupportsSmallCardInsertionAndMixedSizes() {
        let smallA = DashboardModule(kind: .todayOverview, size: .small)
        let smallB = DashboardModule(kind: .averageComparison, size: .small)
        let smallC = DashboardModule(kind: .topModel, size: .small)
        let medium = DashboardModule(kind: .modelRanking, size: .medium)
        let large = DashboardModule(kind: .usageTrend, size: .large)
        let modules = [smallA, smallB, medium, large, smallC]

        let rows = MenuBarPackingLayout.pack(modules)
        XCTAssertEqual(rows.map { $0.moduleIDs }, [
            [smallA.id, smallB.id], [medium.id], [large.id], [smallC.id],
        ])

        let visible = modules.map(\.id)
        XCTAssertEqual(
            MenuBarPackingLayout.inserting(visible, draggedID: smallC.id, atSlot: 1),
            [smallA.id, smallC.id, smallB.id, medium.id, large.id]
        )
    }

    func testMenuBarPackingMergesVisiblePreviewWithoutMovingHiddenCards() {
        let ids = (0 ..< 5).map { _ in UUID() }
        let full = ids
        let visible = [ids[2], ids[0], ids[4]]
        XCTAssertEqual(
            MenuBarPackingLayout.mergingVisibleOrder(fullOrder: full, visibleOrder: visible),
            [ids[2], ids[1], ids[0], ids[3], ids[4]]
        )
    }

    func testLegacyBalanceModuleDefaultsProviderIconsOn() throws {
        let module = DashboardModule(kind: .providerBalances, size: .medium, configuration: .providerBalances(groupIndex: 0))
        let data = try JSONEncoder().encode(module)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "showsProviderIcons")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        XCTAssertTrue(try JSONDecoder().decode(DashboardModule.self, from: legacy).showsProviderIcons)
    }

    func testProviderCardSelectionKeepsIndependentOrderAndMissingIDs() {
        let saved = ["zhipu", "missing", "openai", "deepseek"]
        XCTAssertEqual(
            ProviderBalanceOrder.visibleSelection(savedIDs: saved, availableIDs: ["openai", "deepseek", "zhipu"], size: .medium),
            ["zhipu", "openai", "deepseek"]
        )
        XCTAssertEqual(
            ProviderBalanceOrder.visibleSelection(savedIDs: saved, availableIDs: ["openai", "deepseek", "zhipu"], size: .large),
            ["zhipu", "openai", "deepseek"]
        )
        XCTAssertEqual(saved, ["zhipu", "missing", "openai", "deepseek"])
    }

    func testLegacyBalanceModuleDefaultsToAutomaticProviderSelection() throws {
        let module = DashboardModule(kind: .providerBalances, size: .medium, configuration: .providerBalances(groupIndex: 1))
        let data = try JSONEncoder().encode(module)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "providerIDs")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try JSONDecoder().decode(DashboardModule.self, from: legacy).providerIDs, [])
    }
}
