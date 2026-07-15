#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import SwiftUI

private enum UsageAnalysisTab: String, CaseIterable, Identifiable {
    case trend
    case heatmap
    case distribution

    var id: String { rawValue }
    var title: String {
        switch self {
        case .trend: "趋势"
        case .heatmap: "热力图"
        case .distribution: "分布"
        }
    }
}

private extension View {
    func analysisPanel(surface: AppSurface) -> some View {
        padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(surface.background))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(surface.separator, lineWidth: 1))
    }
}

struct UsageAnalysisView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ccswitch.usageAnalysisExpanded") private var isExpanded = true
    @AppStorage("ccswitch.usageAnalysisTab") private var selectedTabRaw = UsageAnalysisTab.trend.rawValue
    @AppStorage("ccswitch.usageAnalysisRange") private var rangeRaw = ChartRange.sevenDays.rawValue
    @AppStorage("ccswitch.usageAnalysisScope") private var scopeRaw = ModuleTrendScope.byTool.rawValue
    @AppStorage("ccswitch.usageAnalysisTrendStyle") private var styleRaw = ModuleTrendStyle.stackedBars.rawValue
    @AppStorage("ccswitch.usageAnalysisModelIDs") private var analysisModelIDsJSON = "[]"
    @AppStorage("ccswitch.usageAnalysisModelSelectionInitialized") private var analysisModelSelectionInitialized = false
    @State private var showsModelSelection = false

    private var surface: AppSurface {
        AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme)
    }
    private var selectedTab: UsageAnalysisTab {
        get { UsageAnalysisTab(rawValue: selectedTabRaw) ?? .trend }
        nonmutating set { selectedTabRaw = newValue.rawValue }
    }
    private var range: ChartRange {
        get { ChartRange(rawValue: rangeRaw) ?? .sevenDays }
        nonmutating set { rangeRaw = newValue.rawValue }
    }
    private var scope: ModuleTrendScope {
        get { ModuleTrendScope(rawValue: scopeRaw) ?? .byTool }
        nonmutating set { scopeRaw = newValue.rawValue }
    }
    private var trendStyle: ModuleTrendStyle {
        get { ModuleTrendStyle(rawValue: styleRaw) ?? .stackedBars }
        nonmutating set { styleRaw = newValue.rawValue }
    }
    private var analysisModelIDs: [String] {
        get {
            guard let data = analysisModelIDsJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return ids
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else { return }
            analysisModelIDsJSON = value
        }
    }
    private var analysisSelectionIsInitialized: Bool {
        analysisModelSelectionInitialized || !analysisModelIDs.isEmpty
    }
    private var snapshot: UsageSnapshot? {
        switch model.dataState {
        case let .live(value), let .cached(value, _): value
        case .disconnected, .failed: nil
        }
    }
    private var visualizationPalette: UsageVisualizationPalette {
        UsageVisualizationPalette(
            primaryText: surface.primaryText,
            secondaryText: surface.secondaryText,
            accent: surface.accent,
            series: surface.chartColors,
            separator: surface.separator,
            isDark: surface.isDark
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("视图", selection: Binding(get: { selectedTab }, set: { selectedTab = $0 })) {
                        ForEach(UsageAnalysisTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(surface.accent)
                    .foregroundStyle(surface.primaryText)
                    .colorScheme(surface.isDark ? .dark : .light)
                    .frame(width: 200)
                    .padding(.vertical, 6)
                    .frame(width: 200, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 9).fill(surface.background.opacity(0.72)))

                    if let snapshot {
                        analysisContent(snapshot)
                    } else {
                        emptyState
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(surface.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(surface.separator, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(surface.secondaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("用量分析").font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(surface.secondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let snapshot {
                Text(CardUpdateTimeFormatter.string(from: snapshot.generatedAt))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(surface.secondaryText)
            }
        }
    }

    private var subtitle: String {
        switch selectedTab {
        case .trend: "\(rangeLabel) · \(scopeLabel)"
        case .heatmap: "最近 6 个月"
        case .distribution: "\(rangeLabel) · 应用与模型"
        }
    }

    @ViewBuilder
    private func analysisContent(_ snapshot: UsageSnapshot) -> some View {
        switch selectedTab {
        case .trend:
            VStack(alignment: .leading, spacing: 14) {
                trendControls
                if snapshot.analysis[range].totals.totalTokens == 0 {
                    zeroDataState
                } else {
                    UsageTrendVisualization(
                        buckets: snapshot.buckets(for: range),
                        projection: snapshot.analysis[range],
                        scope: scope,
                        style: trendStyle,
                        palette: visualizationPalette,
                        selectedModelIDs: analysisModelIDs,
                        selectedModelsInitialized: analysisSelectionIsInitialized
                    )
                    .frame(minHeight: 300)
                }
            }
            .analysisPanel(surface: surface)
        case .heatmap:
            Group {
                if snapshot.sixMonthTrend.allSatisfy({ $0.totalTokens == 0 }) {
                    zeroDataState
                } else {
                    UsageHeatmapVisualization(
                        days: snapshot.sixMonthTrend,
                        levels: snapshot.analysis.heatmapLevels,
                        palette: visualizationPalette
                    )
                    .frame(minHeight: 220, maxHeight: 270)
                }
            }
            .analysisPanel(surface: surface)
        case .distribution:
            VStack(alignment: .leading, spacing: 14) {
                rangeControl
                if snapshot.analysis[range].totals.totalTokens == 0 {
                    zeroDataState
                } else {
                    distribution(projection: snapshot.analysis[range])
                }
            }
            .analysisPanel(surface: surface)
        }
    }

    private var trendControls: some View {
        HStack(spacing: 16) {
            rangeControl
            Picker("维度", selection: Binding(get: { scope }, set: { scope = $0 })) {
                Text("按工具").tag(ModuleTrendScope.byTool)
                Text("按模型").tag(ModuleTrendScope.byModel)
                Text("总消耗量").tag(ModuleTrendScope.total)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            if scope == .byModel {
                Button {
                    showsModelSelection.toggle()
                } label: {
                    Label(modelSelectionLabel, systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showsModelSelection, arrowEdge: .bottom) {
                    TrendModelSelectionView(
                        availableModelIDs: availableAnalysisModelIDs,
                        savedModelIDs: analysisModelIDs,
                        isInitialized: analysisSelectionIsInitialized,
                        textColor: surface.primaryText,
                        secondaryTextColor: surface.secondaryText,
                        onSelectionChanged: {
                            analysisModelIDs = $0
                            analysisModelSelectionInitialized = true
                        },
                        onMove: { sourceID, targetID in
                            let current = TrendModelSelection.visible(
                                savedIDs: analysisModelIDs,
                                availableIDs: availableAnalysisModelIDs,
                                isInitialized: analysisSelectionIsInitialized
                            )
                            analysisModelIDs = TrendModelSelection.moving(current, sourceID: sourceID, before: targetID)
                            analysisModelSelectionInitialized = true
                        }
                    )
                    .padding(14)
                    .frame(width: 330, height: 420, alignment: .topLeading)
                    .background(surface.background)
                    .foregroundStyle(surface.primaryText)
                    .tint(surface.accent)
                    .preferredColorScheme(surface.isDark ? .dark : .light)
                }
            }
            Picker("样式", selection: Binding(get: { trendStyle }, set: { trendStyle = $0 })) {
                Text("堆叠柱状图").tag(ModuleTrendStyle.stackedBars)
                Text("折线图").tag(ModuleTrendStyle.lines)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            Spacer(minLength: 0)
        }
        .tint(surface.accent)
        .foregroundStyle(surface.primaryText)
        .colorScheme(surface.isDark ? .dark : .light)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(surface.background.opacity(0.72)))
    }

    private var rangeControl: some View {
        Picker("范围", selection: Binding(get: { range }, set: { range = $0 })) {
            Text("当天").tag(ChartRange.today)
            Text("7 天").tag(ChartRange.sevenDays)
            Text("30 天").tag(ChartRange.thirtyDays)
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .tint(surface.accent)
        .foregroundStyle(surface.primaryText)
        .colorScheme(surface.isDark ? .dark : .light)
    }

    private var availableAnalysisModelIDs: [String] {
        snapshot?.availableTrendModelIDs ?? []
    }

    private var modelSelectionLabel: String {
        if !analysisSelectionIsInitialized { return "默认前 6" }
        return analysisModelIDs.isEmpty ? "未选择模型" : "\(analysisModelIDs.count) 个模型"
    }

    private var scopeLabel: String {
        switch scope {
        case .byTool: "按工具"
        case .byModel: "按模型"
        case .total: "总消耗量"
        }
    }

    private func distribution(projection: UsageRangeProjection) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            distributionTable(title: "应用", items: projection.apps, usesModelIcons: false)
            distributionTable(title: "模型", items: projection.models, usesModelIcons: true)
        }
    }

    private func distributionTable(title: String, items: [RangeTokenSummary], usesModelIcons: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 10)
            HStack(spacing: 10) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("Token").frame(width: 110, alignment: .trailing)
                Text("缓存命中").frame(width: 92, alignment: .trailing)
                Text("成本").frame(width: 110, alignment: .trailing)
                Text("占比").frame(width: 62, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(surface.secondaryText)
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Group {
                        if usesModelIcons {
                            ModelFamilyIconView(modelName: item.id, color: surface.primaryText)
                                .frame(width: 18, height: 18)
                        } else {
                            ToolIconView(toolName: item.id, color: surface.primaryText)
                                .frame(width: 18, height: 18)
                        }
                    }
                    Text(item.id).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formattedToken(item.totalTokens))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(width: 110, alignment: .trailing)
                    Text(item.totals.cacheableTokens == 0 ? "—" : item.totals.cacheHitRate.formatted(.percent.precision(.fractionLength(0))))
                        .frame(width: 92, alignment: .trailing)
                        .foregroundStyle(surface.secondaryText)
                    Text(item.totals.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .frame(width: 110, alignment: .trailing)
                    Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                        .frame(width: 62, alignment: .trailing)
                        .foregroundStyle(surface.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                if index < items.count - 1 { Divider() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(surface.card.opacity(0.56)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(surface.separator, lineWidth: 1))
    }

    private var emptyState: some View {
        Label("连接 CC Switch 后查看用量分析", systemImage: "chart.xyaxis.line")
            .foregroundStyle(surface.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var zeroDataState: some View {
        Label("所选范围暂无用量", systemImage: "chart.bar.xaxis")
            .foregroundStyle(surface.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var rangeLabel: String {
        switch range {
        case .today: "当天"
        case .sevenDays: "7 天"
        case .thirtyDays: "30 天"
        }
    }
}
