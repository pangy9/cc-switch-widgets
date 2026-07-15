#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isProviderSourceExpanded = false

    private var surface: AppSurface { AppSurface(mode: model.themeMode, palette: model.customPalette, colorScheme: colorScheme) }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.customPalette[index]) },
            set: { model.setCustomColor(at: index, to: $0.hexValue) }
        )
    }

    private func movementColorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.customMovementColors[index]) },
            set: { model.setCustomMovementColor(at: index, to: $0.hexValue) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                snapshotCard
                UsageAnalysisView()
                providerSourceCard
                connectionCard
                themeCard
                refreshCard
                MenuBarConfigurationView()
            }
            .padding(28)
        }
        .background(surface.background)
        .foregroundStyle(surface.primaryText)
        .tint(surface.accent)
    }

    private var providerSourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isProviderSourceExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(isProviderSourceExpanded ? 90 : 0))
                        .foregroundStyle(surface.secondaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("额度数据源").font(.headline)
                        Text("\(model.orderedProviderBalances.count) 个可用 Provider")
                            .font(.caption).foregroundStyle(surface.secondaryText)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isProviderSourceExpanded {
                VStack(spacing: 0) {
                    ForEach(model.orderedProviderBalances) { balance in
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                ProviderIconView(balance: balance, color: surface.primaryText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(balance.name).font(.subheadline.weight(.semibold))
                                    Text("\(balance.appType) · \(CardUpdateTimeFormatter.string(from: balance.queriedAt))")
                                        .font(.caption2).foregroundStyle(surface.secondaryText)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(surface.secondaryText.opacity(0.12)))
                            Spacer()
                            if let remaining = balance.remaining {
                                Text(String(format: "%.2f %@", remaining, balance.unit)).font(.subheadline.weight(.semibold))
                            } else if ProviderQuotaPresentation.tier(for: .fiveHour, in: balance.tiers) != nil
                                        || ProviderQuotaPresentation.tier(for: .week, in: balance.tiers) != nil {
                                HStack(spacing: 14) {
                                    quotaColumn(balance: balance, period: .fiveHour, label: "5h")
                                    quotaColumn(balance: balance, period: .week, label: "Week")
                                }
                            } else {
                                Text(balance.errorMessage ?? "暂无额度").font(.caption).foregroundStyle(surface.secondaryText)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .draggable(balance.id)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let source = ids.first, source != balance.id else { return false }
                            model.moveProvider(source, before: balance.id)
                            return true
                        }
                        if balance.id != model.orderedProviderBalances.last?.id { Divider() }
                    }
                    HStack {
                        Spacer()
                        Button("立即刷新全部额度") { model.refreshProviderBalances() }
                    }.padding(.top, 10)
                }
                .padding(.top, 12)
            }
        }
        .padding(18)
        .background(surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 与桌面卡片 quotaValue 对齐的两行配额列：标签 + 百分比 / 重置时间。
    @ViewBuilder
    private func quotaColumn(balance: ProviderBalance, period: ProviderQuotaPeriod, label: String) -> some View {
        if let tier = ProviderQuotaPresentation.tier(for: period, in: balance.tiers) {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    Text(label).foregroundStyle(surface.secondaryText)
                    Text(String(format: "%.0f%%", ProviderQuotaPresentation.percent(for: tier, mode: .used)))
                        .fontWeight(.bold)
                }
                Text(ProviderQuotaPresentation.resetText(for: tier, period: period, now: Date()))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(surface.secondaryText)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("CC Switch Token Widgets")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("统一查看用量分析和账户状态；桌面组件与菜单栏可按各自需要独立配置。")
                    .font(.callout)
                    .foregroundStyle(surface.secondaryText)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ProminentButtonStyle(tint: surface.accent))
        }
    }

    private var connectionCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据连接")
                        .font(.headline)
                    Text(model.connectedPath)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(surface.secondaryText)
                }
                Spacer()
                Button {
                    model.connect()
                } label: {
                    Label("重新连接 CC Switch 数据", systemImage: "folder.badge.gearshape")
                        .foregroundStyle(
                            surface.isDark
                                ? Color.white.opacity(0.72)
                                : Color(hex: 0x212121).opacity(0.68)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var themeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("组件主题")
                            .font(.headline)
                        Text("所有桌面组件共享此设置。")
                            .foregroundStyle(surface.secondaryText)
                    }
                    Spacer()
                    ThemedSegmentedControl(selection: Binding(
                        get: { model.themeMode },
                        set: { model.setTheme($0) }
                    ), options: [
                        .init(value: .system, label: "跟随系统"),
                        .init(value: .light, label: "浅色"),
                        .init(value: .dark, label: "深色"),
                        .init(value: .custom, label: "自定义"),
                    ], isDark: surface.isDark, accent: surface.accent)
                    .frame(width: 280)
                }

                if model.themeMode == .custom {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("自定义色板")
                            .font(.headline)
                        Text("第 1 个为背景，后 4 个为图表与模型排行数据色；深浅由背景色亮度自动判断。")
                            .font(.caption)
                            .foregroundStyle(surface.secondaryText)
                        HStack(spacing: 12) {
                            ColorPicker("背景", selection: colorBinding(0), supportsOpacity: false)
                            ColorPicker("数据 1", selection: colorBinding(1), supportsOpacity: false)
                            ColorPicker("数据 2", selection: colorBinding(2), supportsOpacity: false)
                            ColorPicker("数据 3", selection: colorBinding(3), supportsOpacity: false)
                            ColorPicker("数据 4", selection: colorBinding(4), supportsOpacity: false)
                            ColorPicker("高亮", selection: colorBinding(5), supportsOpacity: false)
                            ColorPicker("字体", selection: colorBinding(6), supportsOpacity: false)
                        }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("涨跌颜色")
                            .font(.headline)
                        Text("用于环比、偏离均值和趋势变化状态。")
                            .foregroundStyle(surface.secondaryText)
                    }
                    Spacer()
                    ThemedSegmentedControl(selection: Binding(
                        get: { model.movementColorMode },
                        set: { model.setMovementColorMode($0) }
                    ), options: [
                        .init(value: .redDownGreenUp, label: "红跌绿涨"),
                        .init(value: .redUpGreenDown, label: "红涨绿跌"),
                        .init(value: .custom, label: "自定义"),
                    ], isDark: surface.isDark, accent: surface.accent)
                    .frame(width: 280)
                }

                if model.movementColorMode == .custom {
                    Divider()
                    HStack(spacing: 14) {
                        ColorPicker("涨色", selection: movementColorBinding(0), supportsOpacity: false)
                        ColorPicker("跌色", selection: movementColorBinding(1), supportsOpacity: false)
                    }
                }
            }
        }
    }

    private var snapshotCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("当前状态")
                    .font(.headline)
                switch model.dataState {
                case .disconnected:
                    statusRow("未连接", detail: "请选择 ~/.cc-switch 文件夹。", symbol: "link.badge.plus")
                case let .live(snapshot):
                    summary(snapshot, prefix: "已更新")
                case let .cached(snapshot, reason):
                    summary(snapshot, prefix: "显示上次数据")
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                case let .failed(message):
                    statusRow("读取失败", detail: message, symbol: "exclamationmark.triangle")
                }
            }
        }
    }

    private var balanceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账户").font(.headline)
                    Spacer()
                    Button {
                        model.refreshProviderBalances()
                    } label: {
                        Label("查询", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ProminentButtonStyle(tint: surface.accent))
                }
                if model.providerBalances.isEmpty {
                    Text("点「查询」读取 Claude/Codex 额度和供应商余额。")
                        .font(.caption)
                        .foregroundStyle(surface.secondaryText)
                } else {
                    ForEach(model.providerBalances) { balance in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(balance.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                if balance.kind == .balance, let remaining = balance.remaining, balance.isValid {
                                    Text(String(format: "%.2f %@", remaining, balance.unit))
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                }
                            }
                            ForEach(balance.tiers) { tier in
                                TierProgressRow(tier: tier, palette: surface)
                            }
                            if let err = balance.errorMessage {
                                Text(err).font(.caption).foregroundStyle(.orange).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var refreshCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("组件更新频率")
                            .font(.headline)
                        Text("设置最早刷新间隔；实际时间仍受 macOS WidgetKit 调度影响。")
                            .font(.caption)
                            .foregroundStyle(surface.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Text("更新频率")
                            .foregroundStyle(surface.secondaryText)
                        ThemedRefreshPicker(
                            selection: Binding(
                                get: { model.refreshPreset },
                                set: { model.setRefreshPreset($0) }
                            ),
                            isDark: surface.isDark
                        )
                        .frame(width: 92)
                    }
                }

                if model.refreshPreset == .custom {
                    HStack(spacing: 10) {
                        Stepper("\(model.customHours) 小时", value: $model.customHours, in: 0 ... 168)
                            .frame(width: 130)
                        Stepper("\(model.customMinutes) 分钟", value: $model.customMinutes, in: 0 ... 59)
                            .frame(width: 140)
                        Spacer()
                        Button("应用自定义频率") {
                            model.saveCustomRefreshInterval()
                        }
                        .buttonStyle(ProminentButtonStyle(tint: surface.accent))
                    }
                }

                Divider()
                Toggle("登录时自动启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("在 Dock 中显示", isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.setShowDockIcon($0) }
                ))
                HStack(spacing: 12) {
                    Text("菜单栏主数值")
                    Spacer()
                    ThemedSegmentedControl(selection: Binding(
                        get: { model.menuBarPrimaryMetric },
                        set: { model.setMenuBarPrimaryMetric($0) }
                    ), options: MenuBarPrimaryMetric.allCases.map {
                        .init(value: $0, label: $0.segmentTitle)
                    }, isDark: surface.isDark, accent: surface.accent)
                    .frame(width: 320)
                }
            }
        }
    }

    private func summary(_ snapshot: UsageSnapshot, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                prefix,
                detail: "更新于 \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))",
                symbol: "checkmark.circle"
            )
            HStack(spacing: 18) {
                metric("今日 Token", formattedToken(snapshot.today.totalTokens))
                metric("请求数", "\(snapshot.today.requestCount)")
                metric("成功率", formattedPercent(snapshot.today.successRate))
                metric("本月费用", formattedUSD(snapshot.monthCostUSD))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(surface.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(surface.secondaryText)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// token-monitor 风格的 tier 进度条：tier 名 + 进度条（utilization%）+ 重置时间。
private struct TierProgressRow: View {
    let tier: QuotaTier
    let palette: AppSurface

    private var barColor: Color {
        if tier.utilization >= 80 { return .red }
        if tier.utilization >= 50 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(ProviderBalanceService.tierDisplayName(tier.name))
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(width: 40, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.separator)
                    Capsule().fill(barColor)
                        .frame(width: proxy.size.width * CGFloat(min(max(tier.utilization, 0), 100) / 100))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.0f%%", tier.utilization))
                .font(.caption.weight(.medium))
                .foregroundStyle(barColor)
                .frame(width: 38, alignment: .trailing)
            if let resetsAt = tier.resetsAt {
                Text(resetsAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }
}

private struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// 不失焦变灰的强调按钮：背景固定用传入 tint，文字按 tint 亮度自动黑白。解决系统 borderedProminent 在窗口失焦时变灰的问题。
private struct ProminentButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        let text: Color = tint.hexValue.isLightBackground ? .black : .white
        return configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .foregroundStyle(text)
    }
}

private struct ThemedSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SegmentOption<Value>]
    let isDark: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            isSelected
                                ? (accent.hexValue.isLightBackground ? Color.black : Color.white)
                                : (isDark ? Color.white.opacity(0.72) : Color(hex: 0x212121).opacity(0.68))
                        )
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(isSelected ? accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(3)
        .background(isDark ? Color.white.opacity(0.10) : Color(hex: 0x212121).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ThemedRefreshPicker: View {
    @Binding var selection: RefreshPreset
    let isDark: Bool

    private var foreground: Color {
        isDark ? .white.opacity(0.72) : Color(hex: 0x212121).opacity(0.68)
    }

    private var background: Color {
        isDark ? .white.opacity(0.12) : Color(hex: 0x212121).opacity(0.07)
    }

    var body: some View {
        Menu {
            ForEach(RefreshPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    if preset == selection {
                        Label(preset.label, systemImage: "checkmark")
                    } else {
                        Text(preset.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .tint(foreground)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppSurface {
    let mode: ThemeMode
    let palette: [UInt32]
    let colorScheme: ColorScheme

    init(mode: ThemeMode, palette: [UInt32] = CustomPalette.defaultHexes, colorScheme: ColorScheme = .light) {
        self.mode = mode
        self.palette = palette
        self.colorScheme = colorScheme
    }

    var isDark: Bool {
        switch mode {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        case .custom: !palette[0].isLightBackground
        }
    }

    var background: Color {
        switch mode {
        case .dark: Color(hex: 0x21100D)
        case .light: Color(hex: 0xF6FBFD)
        case .system: isDark ? Color(hex: 0x21100D) : Color(hex: 0xF6FBFD)
        case .custom: Color(hex: palette[0])
        }
    }

    var card: Color {
        switch mode {
        case .dark: Color(hex: 0x89062B).opacity(0.82)
        case .light: Color(hex: 0x212121).opacity(0.04)
        case .system: isDark ? Color(hex: 0x89062B).opacity(0.82) : Color(hex: 0x212121).opacity(0.04)
        case .custom: Color(hex: palette[3]).opacity(0.4)
        }
    }

    var primaryText: Color {
        if case .custom = mode { return Color(hex: palette[6]) }
        return isDark ? .white : Color(hex: 0x212121)
    }

    var secondaryText: Color {
        if case .custom = mode { return Color(hex: palette[6]).opacity(0.62) }
        return isDark ? .white.opacity(0.68) : Color(hex: 0x212121).opacity(0.62)
    }

    var separator: Color {
        isDark ? .white.opacity(0.12) : .black.opacity(0.13)
    }

    var chartColors: [Color] {
        switch mode {
        case .dark: BuiltInThemePalette.darkSeriesHexes.map(Color.init(hex:))
        case .light: BuiltInThemePalette.lightSeriesHexes.map(Color.init(hex:))
        case .system: (isDark ? BuiltInThemePalette.darkSeriesHexes : BuiltInThemePalette.lightSeriesHexes).map(Color.init(hex:))
        case .custom: [Color(hex: palette[1]), Color(hex: palette[2]), Color(hex: palette[3]), Color(hex: palette[4])]
        }
    }

    /// 按钮等强调色：custom 时用自定义的按钮高亮色（palette[5]），非 custom 保持原 tint。
    var accent: Color {
        switch mode {
        case .dark: Color(hex: 0xEA3468)
        case .light: Color(hex: 0x3752AA)
        case .system: isDark ? Color(hex: 0xEA3468) : Color(hex: 0x3752AA)
        case .custom: Color(hex: palette[5])
        }
    }
}

func formattedToken(_ value: Int64) -> String {
    let number = Double(value)
    if value >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", number / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
}

func formattedPercent(_ value: Double) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .percent)
}

func formattedUSD(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
}
