#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, onOpenDashboard: @escaping () -> Void) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 376, height: 590)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanelView(onOpenDashboard: onOpenDashboard)
                .environmentObject(model)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        model.$menuBarPrimaryMetric
            .combineLatest(model.$dataState, model.$isRefreshing)
            .sink { [weak self] metric, state, refreshing in
                self?.updateStatusItem(metric: metric, state: state, refreshing: refreshing)
            }
            .store(in: &cancellables)

        updateStatusItem(metric: model.menuBarPrimaryMetric, state: model.dataState, refreshing: model.isRefreshing)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem(metric: MenuBarPrimaryMetric, state: DataState, refreshing: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarCoin") ?? NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: "CC Switch Widgets")
        image?.isTemplate = true
        button.image = refreshing
            ? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "正在刷新")
            : image

        if metric == .iconOnly {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            statusItem.length = NSStatusItem.variableLength
            button.title = primaryMetricText(metric: metric, state: state)
            button.imagePosition = .imageLeading
        }
    }

    private func snapshot(from state: DataState) -> UsageSnapshot? {
        switch state {
        case let .live(value), let .cached(value, _): value
        case .disconnected, .failed: nil
        }
    }

    private func primaryMetricText(metric: MenuBarPrimaryMetric, state: DataState) -> String {
        guard let snapshot = snapshot(from: state) else { return "—" }
        switch metric {
        case .iconOnly: return ""
        case .requests: return snapshot.today.requestCount.formatted()
        case .tokens: return compactNumber(Double(snapshot.today.totalTokens))
        case .cost: return snapshot.today.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        }
    }

    private func compactNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return Int64(value).formatted()
    }
}
