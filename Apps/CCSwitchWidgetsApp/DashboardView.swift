#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import Charts
import AppKit
import SwiftUI

/// 菜单栏卡片的独立配置列表。它不渲染 App 仪表盘，也不再承担桌面组件发布职责。
struct MenuBarConfigurationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ccswitch.menuBarConfigurationExpanded") private var isExpanded = false
    @State private var editingModuleID: UUID?
    @State private var draggedModuleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(surface.secondaryText)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text("菜单栏卡片").font(.headline)
                    Text(isExpanded ? "拖动卡片调整顺序；设置只影响菜单栏。" : "\(model.dashboardModules.filter(\.showInMenuBar).count) 张正在显示")
                        .font(.caption)
                        .foregroundStyle(surface.secondaryText)
                }
                Spacer()
                if isExpanded {
                    Menu {
                        ForEach(ModuleKind.allCases) { kind in
                            Button(kind.title) { model.addModule(kind: kind) }
                        }
                    } label: {
                        Label("添加卡片", systemImage: "plus")
                    }
                }
            }
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(model.orderedMenuBarConfigurationModules) { module in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(surface.secondaryText)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.kind.title).font(.subheadline.weight(.semibold))
                            Text(module.desktopBindingTitle)
                                .font(.caption)
                                .foregroundStyle(surface.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("显示", isOn: Binding(
                            get: { module.showInMenuBar },
                            set: { _ in model.toggleMenuBar(module.id) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        Button {
                            editingModuleID = module.id
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { editingModuleID == module.id },
                            set: { if !$0 { editingModuleID = nil } }
                        ), arrowEdge: .trailing) {
                            ModuleSettingsPanel(
                                moduleID: module.id,
                                onUnpublish: {},
                                onDelete: {
                                    editingModuleID = nil
                                    model.removeModule(module.id)
                                }
                            )
                            .environmentObject(model)
                        }
                        Button(role: .destructive) {
                            model.removeModule(module.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .draggable(module.id.uuidString) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.stack")
                            Text(module.kind.title)
                        }
                        .padding(8)
                        .background(surface.card)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let rawID = ids.first,
                              let sourceID = UUID(uuidString: rawID),
                              sourceID != module.id else { return false }
                        model.moveMenuBarModule(sourceID, before: module.id)
                        draggedModuleID = nil
                        return true
                    } isTargeted: { targeted in
                        draggedModuleID = targeted ? module.id : nil
                    }
                    .background(draggedModuleID == module.id ? surface.accent.opacity(0.08) : .clear)
                    if module.id != model.orderedMenuBarConfigurationModules.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(18)
        .background(surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var surface: AppSurface {
        AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme)
    }
}

private struct ModuleSpanKey: LayoutValueKey { static let defaultValue = ModuleSize.small }
private extension View {
    func dashboardModuleSize(_ size: ModuleSize) -> some View { layoutValue(key: ModuleSpanKey.self, value: size) }
}

/// 以 WidgetKit 的 small=1×1、medium=2×1、large=2×2 为单位自动装箱。
/// 窗口变宽会增加列数，模块保持桌面组件比例而不是被拉成长条。
private struct WidgetFlowLayout: Layout {
    let spacing: CGFloat
    let columnWidth: CGFloat
    let managementHeight: CGFloat

    private struct Placement { let column: Int; let row: Int; let width: Int; let height: Int }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? columnWidth
        let result = placements(width: width, subviews: subviews)
        return CGSize(width: width, height: CGFloat(result.rows) * (result.columnWidth + managementHeight) + CGFloat(max(0, result.rows - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = placements(width: bounds.width, subviews: subviews)
        for (index, placement) in result.items.enumerated() {
            let x = bounds.minX + CGFloat(placement.column) * (result.columnWidth + spacing)
            let y = bounds.minY + CGFloat(placement.row) * (result.columnWidth + managementHeight + spacing)
            let width = CGFloat(placement.width) * result.columnWidth + CGFloat(placement.width - 1) * spacing
            let height = CGFloat(placement.height) * result.columnWidth + CGFloat(placement.height - 1) * spacing + managementHeight
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
        }
    }

    private func placements(width: CGFloat, subviews: Subviews) -> (items: [Placement], rows: Int, columnWidth: CGFloat) {
        let columns = max(1, Int((width + spacing) / (columnWidth + spacing)))
        var occupied: [[Bool]] = []
        var items: [Placement] = []
        for subview in subviews {
            let size = subview[ModuleSpanKey.self]
            let itemWidth = min(columns, size == .small ? 1 : 2)
            let itemHeight = size == .large && columns > 1 ? 2 : 1
            var row = 0
            var placed: Placement?
            while placed == nil {
                while occupied.count < row + itemHeight { occupied.append(Array(repeating: false, count: columns)) }
                for column in 0 ... max(0, columns - itemWidth) {
                    let free = (row ..< row + itemHeight).allSatisfy { r in
                        (column ..< column + itemWidth).allSatisfy { !occupied[r][$0] }
                    }
                    if free { placed = Placement(column: column, row: row, width: itemWidth, height: itemHeight); break }
                }
                if placed == nil { row += 1 }
            }
            let value = placed!
            for r in value.row ..< value.row + value.height {
                for c in value.column ..< value.column + value.width { occupied[r][c] = true }
            }
            items.append(value)
        }
        return (items, occupied.count, columnWidth)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedModuleID: UUID?
    @State private var pendingAction: PendingDashboardAction?
    @AppStorage("ccswitch.dashboardExpanded") private var isDashboardExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isDashboardExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .rotationEffect(.degrees(isDashboardExpanded ? 90 : 0))
                            .foregroundStyle(surface.secondaryText)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("仪表盘").font(.title2.weight(.semibold))
                            Text("拖动卡片排序；右键打开卡片设置。")
                                .font(.caption)
                                .foregroundStyle(surface.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    ForEach(ModuleKind.allCases) { kind in
                        Button(kind.title) { model.addModule(kind: kind) }
                    }
                } label: {
                    Label("添加卡片", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            if isDashboardExpanded {
                WidgetFlowLayout(
                    spacing: WidgetPresentationMetrics.spacing,
                    columnWidth: WidgetPresentationMetrics.unit,
                    managementHeight: 0
                ) {
                    ForEach(model.dashboardModules) { module in
                        ViewingModuleCard(
                            module: module,
                            onUnpublish: { pendingAction = .unpublish(module) },
                            onDelete: { pendingAction = .delete(module) }
                        )
                            .contentShape(Rectangle())
                            .onDrag {
                                draggedModuleID = module.id
                                return NSItemProvider(object: module.id.uuidString as NSString)
                            }
                            .onDrop(of: [.plainText], delegate: ModuleReorderDropDelegate(
                                targetID: module.id,
                                targetWidth: WidgetPresentationMetrics.width(for: module.size),
                                draggedModuleID: $draggedModuleID,
                                model: model
                            ))
                            .dashboardModuleSize(module.size)
                    }
                }
            }
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case let .unpublish(module):
                Alert(
                    title: Text("取消供桌面使用？"),
                    message: Text("使用此卡片的桌面组件将立即失效。"),
                    primaryButton: .destructive(Text("取消发布")) { model.setDesktopPublished(module.id, false) },
                    secondaryButton: .cancel()
                )
            case let .delete(module):
                Alert(
                    title: Text("删除卡片？"),
                    message: Text(module.isPublishedToDesktop ? "使用此卡片的桌面组件将立即失效。" : "此操作无法撤销。"),
                    primaryButton: .destructive(Text("删除")) { model.removeModule(module.id) },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var surface: AppSurface { AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme) }
}

private enum PendingDashboardAction: Identifiable {
    case unpublish(DashboardModule)
    case delete(DashboardModule)
    var id: String {
        switch self {
        case let .unpublish(module): "unpublish-\(module.id)"
        case let .delete(module): "delete-\(module.id)"
        }
    }
}

private struct EditableModuleEnvelope: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let module: DashboardModule
    @Binding var draggedModuleID: UUID?
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                NativeModuleDragHandle(moduleID: module.id) { draggedModuleID = module.id }
                    .frame(width: 22, height: 26)
                    .help("按住拖动卡片排序")
                Button {
                    module.isPublishedToDesktop ? onUnpublish() : model.setDesktopPublished(module.id, true)
                } label: {
                    Label(module.isPublishedToDesktop ? "已发布" : "未发布", systemImage: module.isPublishedToDesktop ? "checkmark.circle.fill" : "circle")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { model.toggleMenuBar(module.id) } label: {
                    Image(systemName: module.showInMenuBar ? "menubar.rectangle" : "rectangle.slash")
                }.buttonStyle(.plain).help(module.showInMenuBar ? "从菜单栏隐藏" : "在菜单栏显示")
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        ModuleSettingsPanel(moduleID: module.id, onUnpublish: onUnpublish, onDelete: onDelete)
                            .environmentObject(model)
                    }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("删除卡片")
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .foregroundStyle(surface.primaryText)
            .background(surface.card.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            DashboardModuleCard(module: module, compact: false)
                .frame(width: WidgetPresentationMetrics.width(for: module.size), height: WidgetPresentationMetrics.height(for: module.size))
        }
        .frame(width: WidgetPresentationMetrics.width(for: module.size), height: WidgetPresentationMetrics.height(for: module.size) + 36)
        .contextMenu {
            Button("设置卡片…") { showSettings = true }
        }
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            ModuleSettingsPanel(moduleID: module.id, onUnpublish: onUnpublish, onDelete: onDelete)
                .environmentObject(model)
        }
    }

    private var surface: AppSurface { AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme) }
}

/// 非编辑模式下展示的卡片：保留与编辑态一致的右键「设置卡片…」菜单，
/// 不渲染拖拽/发布/删除工具栏。
private struct ViewingModuleCard: View {
    @EnvironmentObject private var model: AppModel
    let module: DashboardModule
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    @State private var showSettings = false

    var body: some View {
        DashboardModuleCard(module: module, compact: false)
            .frame(width: WidgetPresentationMetrics.width(for: module.size), height: WidgetPresentationMetrics.height(for: module.size))
            .contextMenu {
                Button("设置卡片…") { showSettings = true }
            }
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                ModuleSettingsPanel(moduleID: module.id, onUnpublish: onUnpublish, onDelete: onDelete)
                    .environmentObject(model)
            }
    }
}

private struct NativeModuleDragHandle: NSViewRepresentable {
    let moduleID: UUID
    let onBegin: () -> Void

    func makeNSView(context: Context) -> NativeModuleDragHandleView {
        NativeModuleDragHandleView(moduleID: moduleID, onBegin: onBegin)
    }

    func updateNSView(_ nsView: NativeModuleDragHandleView, context: Context) {
        nsView.moduleID = moduleID
        nsView.onBegin = onBegin
    }
}

private final class NativeModuleDragHandleView: NSView, NSDraggingSource {
    var moduleID: UUID
    var onBegin: () -> Void

    init(moduleID: UUID, onBegin: @escaping () -> Void) {
        self.moduleID = moduleID
        self.onBegin = onBegin
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")
        image?.draw(in: bounds.insetBy(dx: 4, dy: 5))
    }

    override func mouseDragged(with event: NSEvent) {
        onBegin()
        let item = NSPasteboardItem()
        item.setString(moduleID.uuidString, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

private struct ModuleSettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let moduleID: UUID
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    @State private var draggedProviderID: String?

    var body: some View {
        Group {
            if let module {
                Form {
                    Section("菜单栏") {
                        Toggle("在菜单栏显示", isOn: Binding(
                            get: { module.showInMenuBar },
                            set: { _ in model.toggleMenuBar(module.id) }
                        ))
                    }
                    if module.kind == .appCard {
                        Section("应用") {
                            Picker("应用", selection: Binding(
                                get: { configuredAppID(module) },
                                set: { model.updateModule(module.id, configuration: .appCard(appID: $0, range: configuredRange(module))) }
                            )) {
                                ForEach(availableApps, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    if [.appCard, .modelRanking, .usageTrend].contains(module.kind) {
                        Section("绘图范围") {
                            Picker("范围", selection: Binding(
                                get: { configuredRange(module) },
                                set: { updateRange(module, $0) }
                            )) {
                                Text("当天").tag(ChartRange.today)
                                Text("7 天").tag(ChartRange.sevenDays)
                                Text("30 天").tag(ChartRange.thirtyDays)
                            }.pickerStyle(.segmented)
                        }
                    }
                    if module.kind == .usageTrend {
                        Section("图表样式") {
                            Picker("样式", selection: Binding(
                                get: { configuredTrendStyle(module) },
                                set: { model.updateModule(module.id, configuration: .usageTrend(range: configuredRange(module), style: $0)) }
                            )) {
                                Text("堆叠柱状图").tag(ModuleTrendStyle.stackedBars)
                                Text("折线图").tag(ModuleTrendStyle.lines)
                            }.pickerStyle(.segmented)
                        }
                        Section("统计维度") {
                            Picker("维度", selection: Binding(
                                get: { module.trendScope },
                                set: { model.setTrendScope(module.id, $0) }
                            )) {
                                Text("按工具").tag(ModuleTrendScope.byTool)
                                Text("按模型").tag(ModuleTrendScope.byModel)
                                Text("总消耗量").tag(ModuleTrendScope.total)
                            }.pickerStyle(.segmented)
                        }
                        if module.trendScope == .byModel {
                            Section("显示模型") {
                                TrendModelSelectionView(
                                    availableModelIDs: availableModelIDs,
                                    savedModelIDs: module.trendModelIDs,
                                    isInitialized: module.trendModelSelectionInitialized,
                                    textColor: surface.primaryText,
                                    secondaryTextColor: surface.secondaryText,
                                    onSelectionChanged: { model.setTrendModels($0, for: module.id) },
                                    onMove: {
                                        model.moveTrendModel(
                                            in: module.id,
                                            sourceID: $0,
                                            before: $1,
                                            availableIDs: availableModelIDs
                                        )
                                    }
                                )
                            }
                        }
                    }
                    if module.kind == .modelRanking || module.kind == .providerBalances {
                        Section("尺寸") {
                            Picker("尺寸", selection: Binding(
                                get: { module.size },
                                set: { model.updateModule(module.id, size: $0) }
                            )) {
                                Text("中号").tag(ModuleSize.medium)
                                Text("大号").tag(ModuleSize.large)
                            }.pickerStyle(.segmented)
                        }
                    }
                    if module.kind == .providerBalances {
                        Section("额度显示") {
                            Picker("数值", selection: Binding(
                                get: { module.providerQuotaDisplayMode },
                                set: { model.setProviderQuotaDisplayMode(module.id, $0) }
                            )) {
                                Text("已使用").tag(ProviderQuotaDisplayMode.used)
                                Text("剩余").tag(ProviderQuotaDisplayMode.remaining)
                            }.pickerStyle(.segmented)
                            Toggle("显示 Provider 图标", isOn: Binding(
                                get: { module.showsProviderIcons },
                                set: { model.setProviderIconsVisible(module.id, $0) }
                            ))
                        }
                        Section("Provider / 账户") {
                            Text(module.size == .large ? "卡片显示前 6 个已选择项目；缩小卡片不会删除其余选择。" : "卡片显示前 3 个已选择项目；切回大号会恢复其余选择。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(orderedProviders) { provider in
                                HStack(spacing: 8) {
                                    if selectedProviderIDs.contains(provider.id) {
                                        ProviderSelectionDragHandle(providerID: provider.id) { draggedProviderID = provider.id }
                                            .frame(width: 20, height: 22)
                                    } else {
                                        Color.clear.frame(width: 20, height: 22)
                                    }
                                    ProviderIconView(balance: provider, color: surface.primaryText)
                                        .frame(width: 16, height: 16)
                                    Toggle(provider.name, isOn: Binding(
                                        get: { selectedProviderIDs.contains(provider.id) },
                                        set: { model.setProvider(provider.id, selected: $0, for: module.id) }
                                    ))
                                    .toggleStyle(.checkbox)
                                }
                                .onDrop(of: [.plainText], delegate: ProviderSelectionDropDelegate(
                                    moduleID: module.id,
                                    targetID: provider.id,
                                    draggedProviderID: $draggedProviderID,
                                    model: model
                                ))
                            }
                        }
                    }
                    Section {
                        Button("删除卡片", role: .destructive, action: onDelete)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .tint(surface.accent)
                .foregroundStyle(surface.primaryText)
                .background(surface.background)
            } else {
                Text("此卡片已不存在").foregroundStyle(surface.secondaryText)
            }
        }
        .padding(12)
        .frame(width: 330)
        .background(surface.background)
        .foregroundStyle(surface.primaryText)
        .tint(surface.accent)
        .preferredColorScheme(surface.isDark ? .dark : .light)
    }

    private var surface: AppSurface {
        AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme)
    }
    private var module: DashboardModule? { model.dashboardModules.first { $0.id == moduleID } }
    private var snapshot: UsageSnapshot? {
        switch model.dataState {
        case let .live(value), let .cached(value, _): value
        case .disconnected, .failed: nil
        }
    }
    private var availableApps: [String] {
        Array(Set(["codex", "claude", "gemini"] + (snapshot?.apps.map(\.id) ?? []))).sorted()
    }
    private var availableModelIDs: [String] {
        snapshot?.availableTrendModelIDs ?? []
    }
    private var selectedProviderIDs: [String] { module?.providerIDs ?? [] }
    private var orderedProviders: [ProviderBalance] {
        let selected = selectedProviderIDs
        let position = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element, $0.offset) })
        return model.orderedProviderBalances.sorted { lhs, rhs in
            switch (position[lhs.id], position[rhs.id]) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
    private func configuredAppID(_ module: DashboardModule) -> String {
        if case let .appCard(id, _) = module.configuration { return id }
        return "codex"
    }
    private func configuredRange(_ module: DashboardModule) -> ChartRange {
        switch module.configuration {
        case let .appCard(_, range), let .modelRanking(range), let .usageTrend(range, _): range
        default: .sevenDays
        }
    }
    private func configuredTrendStyle(_ module: DashboardModule) -> ModuleTrendStyle {
        if case let .usageTrend(_, style) = module.configuration { return style }
        return .stackedBars
    }
    private func configuredBalanceGroup(_ module: DashboardModule) -> Int {
        if case let .providerBalances(index) = module.configuration { return index }
        return 0
    }
    private func balanceGroupCount(for module: DashboardModule) -> Int {
        let capacity = module.size == .large ? 6 : 3
        return max(1, Int(ceil(Double(model.orderedProviderBalances.count) / Double(capacity))))
    }
    private func updateRange(_ module: DashboardModule, _ range: ChartRange) {
        switch module.configuration {
        case let .appCard(appID, _): model.updateModule(module.id, configuration: .appCard(appID: appID, range: range))
        case .modelRanking: model.updateModule(module.id, configuration: .modelRanking(range: range))
        case let .usageTrend(_, style): model.updateModule(module.id, configuration: .usageTrend(range: range, style: style))
        case .none, .providerBalances: break
        }
    }
}

private struct ProviderSelectionDragHandle: NSViewRepresentable {
    let providerID: String
    let onBegin: () -> Void
    func makeNSView(context: Context) -> ProviderSelectionDragHandleView { ProviderSelectionDragHandleView(providerID: providerID, onBegin: onBegin) }
    func updateNSView(_ nsView: ProviderSelectionDragHandleView, context: Context) { nsView.providerID = providerID; nsView.onBegin = onBegin }
}

private final class ProviderSelectionDragHandleView: NSView, NSDraggingSource {
    var providerID: String
    var onBegin: () -> Void
    init(providerID: String, onBegin: @escaping () -> Void) { self.providerID = providerID; self.onBegin = onBegin; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")?.draw(in: bounds.insetBy(dx: 3, dy: 4))
    }
    override func mouseDragged(with event: NSEvent) {
        onBegin()
        let item = NSPasteboardItem(); item.setString(providerID, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}

private struct ProviderSelectionDropDelegate: DropDelegate {
    let moduleID: UUID
    let targetID: String
    @Binding var draggedProviderID: String?
    let model: AppModel
    func dropEntered(info: DropInfo) {
        guard let source = draggedProviderID, source != targetID else { return }
        model.moveProvider(in: moduleID, sourceID: source, before: targetID)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggedProviderID = nil; return true }
}

private struct ModuleManagementEnvelope: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var confirmUnpublish = false
    @State private var confirmDelete = false
    let module: DashboardModule
    @Binding var draggedModuleID: UUID?

    var body: some View {
        ZStack(alignment: .top) {
            DashboardModuleCard(module: module, compact: false)
                .frame(
                    width: WidgetPresentationMetrics.width(for: module.size),
                    height: WidgetPresentationMetrics.height(for: module.size)
                )

            HStack(spacing: 6) {
                Button {
                    if module.isPublishedToDesktop { confirmUnpublish = true }
                    else { model.setDesktopPublished(module.id, true) }
                } label: {
                    Label(
                        module.isPublishedToDesktop ? "已发布" : "发布",
                        systemImage: module.isPublishedToDesktop ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption2.weight(.semibold))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help(module.isPublishedToDesktop ? "已供桌面组件使用，点击取消" : "点击供桌面组件使用")
                DashboardModuleCard(module: module, compact: false).settingsMenu(model: model)
                Menu {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(module.id.uuidString, forType: .string)
                    } label: { Label("复制卡片 ID（\(shortID)）", systemImage: "doc.on.doc") }
                    Button { model.toggleMenuBar(module.id) } label: {
                        Label(module.showInMenuBar ? "从菜单栏隐藏" : "在菜单栏显示", systemImage: "menubar.rectangle")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("删除卡片", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .help("更多卡片操作")
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .foregroundStyle(Color.white)
            .tint(Color.white)
            .background(surface.chartColors[1])
            .clipShape(Capsule())
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .frame(
            width: WidgetPresentationMetrics.width(for: module.size),
            height: WidgetPresentationMetrics.height(for: module.size)
        )
        .contentShape(Rectangle())
        .onDrag {
            draggedModuleID = module.id
            return NSItemProvider(object: module.id.uuidString as NSString)
        }
        .help("拖动卡片调整顺序")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .alert("取消供桌面使用？", isPresented: $confirmUnpublish) {
            Button("取消", role: .cancel) {}
            Button("取消发布", role: .destructive) { model.setDesktopPublished(module.id, false) }
        } message: {
            Text("使用此卡片的桌面组件将立即失效。")
        }
        .alert("删除卡片？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                let id = module.id
                DispatchQueue.main.async { model.removeModule(id) }
            }
        } message: {
            Text(module.isPublishedToDesktop ? "使用此卡片的桌面组件将立即失效。" : "此操作无法撤销。")
        }
    }

    private var shortID: String { String(module.id.uuidString.prefix(8)) }
    private var surface: AppSurface { AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme) }
}

private struct ModuleReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let targetWidth: CGFloat
    @Binding var draggedModuleID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        reorder(info)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModuleID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        reorder(info)
        return DropProposal(operation: .move)
    }

    private func reorder(_ info: DropInfo) {
        guard let sourceID = draggedModuleID, sourceID != targetID else { return }
        let edge: ModuleDropEdge = info.location.x < targetWidth / 2 ? .before : .after
        model.moveModule(sourceID, targetID: targetID, edge: edge)
    }
}

struct DashboardModuleCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let module: DashboardModule
    let compact: Bool

    private var surface: AppSurface { AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme) }
    private var snapshot: UsageSnapshot? {
        switch model.dataState {
        case let .live(value), let .cached(value, _): value
        case .disconnected, .failed: nil
        }
    }

    var body: some View {
        SharedWidgetCard(
            model: CardRenderModel(
                module: module,
                snapshot: snapshot ?? .empty,
                balances: balanceGroup,
                themeMode: model.themeMode,
                movementColorMode: model.movementColorMode,
                customPalette: model.customPalette,
                customMovementColors: model.customMovementColors,
                message: snapshot == nil && module.kind != .providerBalances ? "等待 App 更新数据" : nil
            ),
            surface: .app,
            onQuotaModeChange: module.kind == .providerBalances ? { mode in
                model.setProviderQuotaDisplayMode(module.id, mode)
            } : nil
        )
    }

    @ViewBuilder private var moduleContent: some View {
        if let snapshot {
            switch module.kind {
            case .todayOverview:
                VStack(alignment: .leading, spacing: 0) {
                    Text(formattedToken(snapshot.today.totalTokens)).font(.system(size: 31, weight: .bold, design: .rounded))
                    Spacer(minLength: 8)
                    Text("昨日 \(formattedToken(snapshot.yesterday.totalTokens))").font(.caption).foregroundStyle(surface.secondaryText)
                    Spacer(minLength: 8)
                    HStack { miniMetric("环比", delta(snapshot.today.totalTokens, snapshot.yesterday.totalTokens)); miniMetric("请求", "\(snapshot.today.requestCount)") }
                }
            case .averageComparison:
                VStack(alignment: .leading, spacing: 10) {
                    Text(formattedToken(snapshot.today.totalTokens)).font(.system(size: 31, weight: .bold, design: .rounded))
                    GeometryReader { proxy in
                        let ratio = snapshot.sevenDayAverageTokens == 0 ? 0 : Double(snapshot.today.totalTokens) / snapshot.sevenDayAverageTokens
                        ZStack(alignment: .leading) {
                            Capsule().fill(surface.separator)
                            Capsule().fill(ratio > 1 ? Color.red : Color.green).frame(width: max(8, proxy.size.width * min(ratio / 1.5, 1)))
                        }
                    }.frame(height: 8)
                    HStack {
                        miniMetric("均值", formattedToken(Int64(snapshot.sevenDayAverageTokens)))
                        miniMetric(ratioLabel(snapshot), ratioDelta(snapshot))
                    }
                }
            case .appCard:
                let appID = appIDFromConfiguration
                let app = snapshot.apps.first { $0.id == appID }
                VStack(alignment: .leading, spacing: 8) {
                    Text(formattedToken(app?.totalTokens ?? 0)).font(.system(size: 29, weight: .bold, design: .rounded))
                    HStack(spacing: 5) { Text(formattedPercent(app?.share ?? 0)).fontWeight(.semibold); Text("区间占比").foregroundStyle(surface.secondaryText) }.font(.caption)
                    AppMiniLine(values: app?.trendTokens ?? [], color: surface.accent, secondary: surface.secondaryText)
                }
            case .topModel:
                let top = snapshot.models.first
                VStack(alignment: .leading, spacing: 8) {
                    Text(top?.id ?? "—").font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(formattedToken(top?.totalTokens ?? 0)).font(.system(size: 29, weight: .bold, design: .rounded))
                    HStack { miniMetric("占比", formattedPercent(top?.share ?? 0)); miniMetric("命中", formattedPercent(top?.cacheHitRate ?? 0)); miniMetric("请求", "\(top?.totals.requestCount ?? 0)") }
                }
            case .modelRanking:
                let range = rankingRange
                let buckets = snapshot.buckets(for: range)
                ForEach(Array(snapshot.modelSummaries(for: range).prefix(module.size == .large ? 6 : 3).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.id).font(.subheadline.weight(.bold)).lineLimit(1)
                            Text("\(formattedPercent(item.share)) 区间占比").font(.caption2).foregroundStyle(surface.secondaryText)
                        }.frame(width: 125, alignment: .leading)
                        AppMiniLine(values: buckets.map { $0.modelTokens?[item.id] ?? 0 }, color: surface.chartColors[index % surface.chartColors.count], secondary: surface.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 32)
                        Text(formattedToken(item.totalTokens)).font(.subheadline.weight(.bold)).frame(width: 72, alignment: .trailing)
                    }
                    if index < min(snapshot.models.count, module.size == .large ? 6 : 3) - 1 { Divider() }
                }
            case .usageTrend:
                AppTrendChart(snapshot: snapshot, module: module, colors: surface.chartColors, secondary: surface.secondaryText, separator: surface.separator)
            case .usageHeatmap:
                EmptyView()
            case .costOverview:
                metricRow(formattedUSD(snapshot.today.costUSD), "今日费用", "本月 \(formattedUSD(snapshot.monthCostUSD))")
            case .providerBalances:
                balanceContent
            }
        } else if module.kind == .providerBalances {
            balanceContent
        } else {
            Text("等待 App 更新数据").font(.caption).foregroundStyle(surface.secondaryText)
        }
    }

    @ViewBuilder private var balanceContent: some View {
        let balances = balanceGroup
        if balances.isEmpty {
            Text("暂无账户数据").font(.caption).foregroundStyle(surface.secondaryText)
        } else {
            ForEach(balances) { balance in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(balance.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if let remaining = balance.remaining {
                            Text(String(format: "%.2f %@", remaining, balance.unit)).monospacedDigit()
                        } else if let tier = balance.tiers.first {
                            Text(String(format: "%.0f%%", tier.utilization)).monospacedDigit()
                        }
                    }
                    if let tier = balance.tiers.first {
                        ProgressView(value: min(max(tier.utilization, 0), 100), total: 100).tint(surface.accent)
                    }
                    if let error = balance.errorMessage { Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
                }
                .draggable(balance.id)
                .dropDestination(for: String.self) { ids, _ in
                    guard let source = ids.first else { return false }
                    model.moveProvider(source, before: balance.id)
                    return true
                }
            }
        }
    }

    private func metricRow(_ value: String, _ label: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: compact ? 20 : 25, weight: .semibold, design: .rounded)).lineLimit(1)
            HStack { Text(label); Spacer(); Text(detail) }
                .font(.caption).foregroundStyle(surface.secondaryText).lineLimit(1)
        }
    }

    private func miniMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(surface.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delta(_ today: Int64, _ yesterday: Int64) -> String {
        guard yesterday != 0 else { return "0%" }
        return ((Double(today) / Double(yesterday)) - 1).formatted(.percent.precision(.fractionLength(0)))
    }

    private func ratioLabel(_ snapshot: UsageSnapshot) -> String {
        Double(snapshot.today.totalTokens) >= snapshot.sevenDayAverageTokens ? "高于均值" : "低于均值"
    }

    private func ratioDelta(_ snapshot: UsageSnapshot) -> String {
        guard snapshot.sevenDayAverageTokens > 0 else { return "0%" }
        return abs(Double(snapshot.today.totalTokens) / snapshot.sevenDayAverageTokens - 1).formatted(.percent.precision(.fractionLength(0)))
    }

    @ViewBuilder func settingsMenu(model: AppModel) -> some View {
        let snapshot: UsageSnapshot? = {
            switch model.dataState {
            case let .live(value), let .cached(value, _): value
            case .disconnected, .failed: nil
            }
        }()
        let availableApps = Array(Set(["codex", "claude", "gemini"] + (snapshot?.apps.map(\.id) ?? []))).sorted()
        let capacity = module.size == .large ? 6 : 3
        let groupCount = Int(ceil(Double(model.orderedProviderBalances.count) / Double(capacity)))
        Menu {
            if module.kind == .appCard {
                Section("应用") {
                    ForEach(availableApps, id: \.self) { appID in
                        Button { model.updateModule(module.id, configuration: .appCard(appID: appID, range: appRange)) } label: {
                            if appID == appIDFromConfiguration { Label(appID, systemImage: "checkmark") } else { Text(appID) }
                        }
                    }
                }
                rangeSection(model: model) { range in .appCard(appID: appIDFromConfiguration, range: range) }
            }
            if module.kind == .modelRanking {
                rangeSection(model: model) { range in .modelRanking(range: range) }
                Section("尺寸") {
                    sizeButton(.medium, label: "中号 · 3 个模型", model: model)
                    sizeButton(.large, label: "大号 · 6 个模型", model: model)
                }
            }
            if module.kind == .usageTrend {
                rangeSection(model: model) { range in .usageTrend(range: range, style: trendStyle) }
                Section("图表样式") {
                    Button { model.updateModule(module.id, configuration: .usageTrend(range: trendRange, style: .stackedBars)) } label: {
                        if trendStyle == .stackedBars { Label("堆叠柱状图", systemImage: "checkmark") } else { Text("堆叠柱状图") }
                    }
                    Button { model.updateModule(module.id, configuration: .usageTrend(range: trendRange, style: .lines)) } label: {
                        if trendStyle == .lines { Label("折线图", systemImage: "checkmark") } else { Text("折线图") }
                    }
                }
                Section("统计维度") {
                    Button { model.setTrendScope(module.id, .byTool) } label: {
                        if module.trendScope == .byTool { Label("按工具", systemImage: "checkmark") } else { Text("按工具") }
                    }
                    Button { model.setTrendScope(module.id, .byModel) } label: {
                        if module.trendScope == .byModel { Label("按模型", systemImage: "checkmark") } else { Text("按模型") }
                    }
                    Button { model.setTrendScope(module.id, .total) } label: {
                        if module.trendScope == .total { Label("总消耗量", systemImage: "checkmark") } else { Text("总消耗量") }
                    }
                }
            }
            if module.kind == .providerBalances {
                Section("尺寸") {
                    sizeButton(.medium, label: "中号 · 每组 3 项", model: model)
                    sizeButton(.large, label: "大号 · 每组 6 项", model: model)
                }
                Section("显示分组") {
                    ForEach(0 ..< max(1, groupCount), id: \.self) { group in
                        Button { model.updateModule(module.id, configuration: .providerBalances(groupIndex: group)) } label: {
                            if group == balanceGroupIndex { Label("第 \(group + 1) 组", systemImage: "checkmark") } else { Text("第 \(group + 1) 组") }
                        }
                    }
                }
            }
            if ![ModuleKind.appCard, .modelRanking, .usageTrend, .providerBalances].contains(module.kind) {
                Text("此组件没有其他设置")
            }
        } label: { Image(systemName: "gearshape") }
        .menuStyle(.borderlessButton)
        .help("设置此组件")
    }

    private func rangeSection(model: AppModel, configuration: @escaping (ChartRange) -> ModuleConfiguration) -> some View {
        Section("绘图范围") {
            ForEach(ChartRange.allCases) { range in
                Button { model.updateModule(module.id, configuration: configuration(range)) } label: {
                    if range == configuredRange { Label(rangeLabel(range), systemImage: "checkmark") } else { Text(rangeLabel(range)) }
                }
            }
        }
    }

    private func sizeButton(_ size: ModuleSize, label: String, model: AppModel) -> some View {
        Button { model.updateModule(module.id, size: size) } label: {
            if module.size == size { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
    }

    private var appIDFromConfiguration: String {
        if case let .appCard(appID, _) = module.configuration { return appID }
        return "codex"
    }

    private var appRange: ChartRange {
        if case let .appCard(_, range) = module.configuration { return range }
        return .sevenDays
    }

    private var trendRange: ChartRange {
        if case let .usageTrend(range, _) = module.configuration { return range }
        return .sevenDays
    }

    private var trendStyle: ModuleTrendStyle {
        if case let .usageTrend(_, style) = module.configuration { return style }
        return .stackedBars
    }

    private var configuredRange: ChartRange {
        switch module.configuration {
        case let .appCard(_, range), let .modelRanking(range), let .usageTrend(range, _): return range
        default: return .sevenDays
        }
    }

    private var availableApps: [String] {
        Array(Set(["codex", "claude", "gemini"] + (snapshot?.apps.map(\.id) ?? []))).sorted()
    }

    private func rangeLabel(_ range: ChartRange) -> String {
        switch range { case .today: "当天"; case .sevenDays: "最近 7 日"; case .thirtyDays: "最近 30 日" }
    }

    private var balanceGroupIndex: Int {
        if case let .providerBalances(value) = module.configuration { return value }
        return 0
    }

    private var displayTitle: String {
        switch module.configuration {
        case let .appCard(appID, range): return "\(appID) · \(range.shortLabel)"
        case let .modelRanking(range): return "模型用量排行 · \(range.shortLabel)"
        case let .usageTrend(range, _):
            switch range { case .today: return "今日趋势"; case .sevenDays: return "近 7 日趋势"; case .thirtyDays: return "近 30 日趋势" }
        default: return module.kind.title
        }
    }

    private var updatedText: String {
        guard let date = snapshot?.generatedAt else { return "等待更新" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return minutes == 0 ? "刚刚更新" : "更新于 \(minutes) 分钟前"
    }

    private var rankingRange: ChartRange {
        if case let .modelRanking(value) = module.configuration { return value }
        return .sevenDays
    }

    private var balanceGroup: [ProviderBalance] {
        let availableIDs = model.orderedProviderBalances.map(\.id)
        let ids: [String]
        if module.providerIDs.isEmpty {
            let index: Int
            if case let .providerBalances(value) = module.configuration { index = value } else { index = 0 }
            ids = ProviderBalanceOrder.group(ids: availableIDs, index: index, size: module.size)
        } else {
            ids = ProviderBalanceOrder.visibleSelection(savedIDs: module.providerIDs, availableIDs: availableIDs, size: module.size)
        }
        let map = Dictionary(uniqueKeysWithValues: model.orderedProviderBalances.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

    private var balanceGroupCount: Int {
        let capacity = module.size == .large ? 6 : 3
        return Int(ceil(Double(model.orderedProviderBalances.count) / Double(capacity)))
    }

    private var height: CGFloat {
        if compact { return module.kind == .providerBalances ? 92 : 70 }
        return 0
    }

    private var shellPadding: CGFloat { WidgetPresentationMetrics.insets(for: module.size) }
    private var titleSpacing: CGFloat { WidgetPresentationMetrics.titleSpacing(for: module.size) }
}

private struct AppMiniLine: View {
    let values: [Int64]
    let color: Color
    let secondary: Color
    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { point in
                AreaMark(x: .value("点", point.offset), y: .value("Token", point.element))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("点", point.offset), y: .value("Token", point.element))
                    .interpolationMethod(.monotone).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.4))
            }
            if !values.isEmpty {
                RuleMark(y: .value("均值", Double(values.reduce(0, +)) / Double(values.count)))
                    .foregroundStyle(secondary).lineStyle(StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
    }
}

private struct AppTrendChart: View {
    let snapshot: UsageSnapshot
    let module: DashboardModule
    let colors: [Color]
    let secondary: Color
    let separator: Color

    var body: some View {
        let buckets = snapshot.buckets(for: range)
        let apps = Array(Set(buckets.flatMap { $0.appTokens.keys })).sorted()
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                if style == .stackedBars {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        ForEach(apps, id: \.self) { app in
                            BarMark(x: .value("日期", index), y: .value("Token", bucket.appTokens[app] ?? 0), stacking: .standard)
                                .foregroundStyle(colors[apps.firstIndex(of: app)! % colors.count])
                        }
                    }
                } else {
                    ForEach(apps, id: \.self) { app in
                        ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                            LineMark(x: .value("日期", index), y: .value("Token", bucket.appTokens[app] ?? 0), series: .value("应用", app))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(colors[apps.firstIndex(of: app)! % colors.count])
                                .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }
                    }
                }
                if !buckets.isEmpty {
                    RuleMark(y: .value("均值", Double(buckets.reduce(Int64(0)) { $0 + $1.totalTokens }) / Double(buckets.count)))
                        .foregroundStyle(secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                let halfStep = Double(range.axisStep(bucketCount: buckets.count)) / 2
                let labelIndices = range.axisLabelIndices(bucketCount: buckets.count)
                let labelMarks: [Double] = {
                    var marks = labelIndices.map { Double($0) - halfStep }
                    if let last = labelIndices.last { marks.append(Double(last) + halfStep) }
                    return marks
                }()
                AxisMarks(values: labelIndices) { _ in
                    AxisGridLine().foregroundStyle(separator)
                }
                AxisMarks(values: labelMarks) { value in
                    AxisValueLabel(centered: true) {
                        if let shifted = value.as(Double.self) {
                            let index = Int((shifted + halfStep).rounded())
                            if buckets.indices.contains(index) { Text(axisLabel(buckets[index].date)) }
                        }
                    }
                }
            }
            .chartXScale(domain: -1 ... Double(max(1, buckets.count)))
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(separator) } }
            HStack(spacing: 14) {
                ForEach(Array(apps.prefix(4).enumerated()), id: \.element) { index, app in
                    HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(colors[index % colors.count]).frame(width: 12, height: 8); Text(app) }
                }
            }.font(.caption).foregroundStyle(secondary)
        }
    }

    private var range: ChartRange {
        if case let .usageTrend(value, _) = module.configuration { return value }
        return .sevenDays
    }
    private var style: ModuleTrendStyle {
        if case let .usageTrend(_, value) = module.configuration { return value }
        return .stackedBars
    }
    private func axisLabel(_ date: Date) -> String { "\(Calendar.current.component(range == .today ? .hour : .day, from: date))" }
}

struct MenuBarPanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let onOpenDashboard: () -> Void
    @State private var draggedModuleID: UUID?
    @State private var previewOrder: [UUID]?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CC Switch").font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
            }
            ScrollView(.vertical, showsIndicators: false) {
                let modules = model.orderedMenuBarModules(order: previewOrder)
                if modules.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.title2)
                        Text("尚未选择菜单栏卡片").font(.headline)
                        Text("请在编辑布局中为卡片开启“在菜单栏显示”。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("打开编辑布局", action: onOpenDashboard)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    let rows = MenuBarPackingLayout.pack(modules)
                    let moduleMap = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
                    VStack(spacing: WidgetPresentationMetrics.spacing) {
                        ForEach(Array(rows.enumerated()), id: \.element.moduleIDs) { rowIndex, row in
                            let rowStart = rows.prefix(rowIndex).reduce(0) { $0 + $1.moduleIDs.count }
                            HStack(spacing: WidgetPresentationMetrics.spacing) {
                                ForEach(row.moduleIDs, id: \.self) { id in
                                    if let module = moduleMap[id] {
                                        MenuBarDraggableCard(
                                            module: module,
                                            draggedModuleID: $draggedModuleID,
                                            previewOrder: $previewOrder
                                        )
                                    }
                                }
                                if row.size == .small && row.moduleIDs.count == 1 {
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(width: WidgetPresentationMetrics.width(for: .medium), alignment: .leading)
                            .overlay {
                                if draggedModuleID != nil {
                                    MenuBarDropSlots(
                                        count: row.moduleIDs.count + 1,
                                        rowStart: rowStart,
                                        draggedModuleID: $draggedModuleID,
                                        previewOrder: $previewOrder
                                    )
                                    .environmentObject(model)
                                }
                            }
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: modules.map(\.id))
                    .frame(width: WidgetPresentationMetrics.width(for: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
            }
            .scrollIndicators(.hidden)
            .background(ScrollViewScrollerConfigurator())
            .frame(width: 348)
            .frame(maxHeight: 500)
            Divider()
            HStack {
                Button("打开仪表盘") {
                    onOpenDashboard()
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 376)
        .background(AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme).background)
        .foregroundStyle(AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme).primaryText)
        .onDisappear {
            draggedModuleID = nil
            previewOrder = nil
        }
    }
}

private struct ScrollViewScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ScrollerHidingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 视图进入 window 后再向上查找包裹它的 NSScrollView，此时层级才完整，
/// 能可靠地把滚动条轨道隐藏（早于 window 挂载时查找会落空）。
private final class ScrollerHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        hideAllScrollers()
        DispatchQueue.main.async { [weak self] in self?.hideAllScrollers() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.hideAllScrollers() }
    }

    override func layout() {
        super.layout()
        hideAllScrollers()
    }

    private func hideAllScrollers() {
        guard let root = window?.contentView else { return }
        for scrollView in scrollViews(below: root) {
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.verticalScroller = nil
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScroller = nil
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = false
            scrollView.automaticallyAdjustsContentInsets = false
            let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scrollView.contentInsets = zeroInsets
            scrollView.scrollerInsets = zeroInsets
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
        }
    }

    private func scrollViews(below view: NSView) -> [NSScrollView] {
        var result = view.subviews.compactMap { $0 as? NSScrollView }
        for child in view.subviews { result.append(contentsOf: scrollViews(below: child)) }
        return result
    }
}

private struct MenuBarDraggableCard: View {
    @EnvironmentObject private var model: AppModel
    let module: DashboardModule
    @Binding var draggedModuleID: UUID?
    @Binding var previewOrder: [UUID]?
    @State private var showSettings = false

    var body: some View {
        DashboardModuleCard(module: module, compact: false)
            .frame(
                width: WidgetPresentationMetrics.width(for: module.size),
                height: WidgetPresentationMetrics.height(for: module.size)
            )
        .contentShape(Rectangle())
        .onDrag {
            draggedModuleID = module.id
            previewOrder = model.orderedMenuBarModules.map(\.id)
            return NSItemProvider(object: module.id.uuidString as NSString)
        }
        .opacity(draggedModuleID == module.id ? 0.58 : 1)
        .scaleEffect(draggedModuleID == module.id ? 0.97 : 1)
        .help("拖动卡片调整菜单栏顺序")
        .contextMenu { Button("设置卡片…") { showSettings = true } }
        .popover(isPresented: $showSettings, arrowEdge: .leading) {
            ModuleSettingsPanel(moduleID: module.id, onUnpublish: {}, onDelete: {})
            .environmentObject(model)
        }
    }
}

private struct MenuBarDropSlots: View {
    @EnvironmentObject private var model: AppModel
    let count: Int
    let rowStart: Int
    @Binding var draggedModuleID: UUID?
    @Binding var previewOrder: [UUID]?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< count, id: \.self) { localSlot in
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText], delegate: MenuBarInsertionDropDelegate(
                        slot: rowStart + localSlot,
                        draggedModuleID: $draggedModuleID,
                        previewOrder: $previewOrder,
                        model: model
                    ))
            }
        }
    }
}

private struct MenuBarInsertionDropDelegate: DropDelegate {
    let slot: Int
    @Binding var draggedModuleID: UUID?
    @Binding var previewOrder: [UUID]?
    let model: AppModel

    func dropEntered(info: DropInfo) { reorder() }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        reorder()
        return DropProposal(operation: .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        if let previewOrder { model.commitVisibleMenuBarModuleOrder(previewOrder) }
        draggedModuleID = nil
        previewOrder = nil
        return true
    }
    private func reorder() {
        guard let sourceID = draggedModuleID else { return }
        let current = previewOrder ?? model.orderedMenuBarModules.map(\.id)
        let reordered = MenuBarPackingLayout.inserting(current, draggedID: sourceID, atSlot: slot)
        guard reordered != current else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            previewOrder = reordered
        }
    }
}
