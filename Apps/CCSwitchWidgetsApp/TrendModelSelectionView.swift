#if canImport(CCSwitchCore)
import CCSwitchCore
#endif
import AppKit
import SwiftUI

struct TrendModelSelectionView: View {
    let availableModelIDs: [String]
    let savedModelIDs: [String]
    let isInitialized: Bool
    let textColor: Color
    let secondaryTextColor: Color
    let onSelectionChanged: ([String]) -> Void
    let onMove: (_ sourceID: String, _ targetID: String) -> Void
    @State private var draggedModelID: String?

    private var effectiveSelectedIDs: [String] {
        TrendModelSelection.visible(
            savedIDs: savedModelIDs,
            availableIDs: availableModelIDs,
            isInitialized: isInitialized
        )
    }

    private var orderedModelIDs: [String] {
        let selected = effectiveSelectedIDs
        return selected + availableModelIDs.filter { !selected.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(isInitialized ? "仅影响按模型模式；拖动手柄调整顺序。" : "首次使用默认显示用量排名前 6。")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                Spacer(minLength: 4)
                Button("全选") { onSelectionChanged(availableModelIDs) }
                    .buttonStyle(.borderless)
                Button("反选") {
                    let selected = Set(effectiveSelectedIDs)
                    onSelectionChanged(availableModelIDs.filter { !selected.contains($0) })
                }
                .buttonStyle(.borderless)
            }

            ForEach(orderedModelIDs, id: \.self) { modelID in
                let isSelected = effectiveSelectedIDs.contains(modelID)
                HStack(spacing: 8) {
                    if isSelected {
                        TrendModelDragHandle(modelID: modelID) { draggedModelID = modelID }
                            .frame(width: 20, height: 22)
                    } else {
                        Color.clear.frame(width: 20, height: 22)
                    }
                    ModelFamilyIconView(modelName: modelID, color: textColor)
                        .frame(width: 16, height: 16)
                    Toggle(modelID, isOn: Binding(
                        get: { isSelected },
                        set: { updateSelection(modelID: modelID, selected: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
                }
                .onDrop(of: [.plainText], delegate: TrendModelSelectionDropDelegate(
                    targetID: modelID,
                    draggedModelID: $draggedModelID,
                    onMove: onMove
                ))
            }
        }
    }

    private func updateSelection(modelID: String, selected: Bool) {
        var ids = effectiveSelectedIDs
        if selected {
            if !ids.contains(modelID) { ids.append(modelID) }
        } else {
            ids.removeAll { $0 == modelID }
        }
        let missingSavedIDs = isInitialized ? savedModelIDs.filter { !availableModelIDs.contains($0) } : []
        onSelectionChanged(missingSavedIDs + ids)
    }
}

private struct TrendModelDragHandle: NSViewRepresentable {
    let modelID: String
    let onBegin: () -> Void

    func makeNSView(context: Context) -> TrendModelDragHandleView {
        TrendModelDragHandleView(modelID: modelID, onBegin: onBegin)
    }

    func updateNSView(_ nsView: TrendModelDragHandleView, context: Context) {
        nsView.modelID = modelID
        nsView.onBegin = onBegin
    }
}

private final class TrendModelDragHandleView: NSView, NSDraggingSource {
    var modelID: String
    var onBegin: () -> Void

    init(modelID: String, onBegin: @escaping () -> Void) {
        self.modelID = modelID
        self.onBegin = onBegin
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")?
            .draw(in: bounds.insetBy(dx: 3, dy: 4))
    }

    override func mouseDragged(with event: NSEvent) {
        onBegin()
        let item = NSPasteboardItem()
        item.setString(modelID, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}

private struct TrendModelSelectionDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedModelID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedModelID, sourceID != targetID else { return }
        onMove(sourceID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggedModelID = nil; return true }
}
