import AppKit
import SwiftUI

public struct ModelFamilyIconView: View {
    private let family: ModelFamily
    private let color: Color

    public init(modelName: String, color: Color) {
        family = ModelFamilyResolver.resolve(modelName)
        self.color = color
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(color)
                    .scaledToFit()
            } else {
                Image(systemName: "cpu")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        Bundle.main.url(
            forResource: family.iconResourceName,
            withExtension: "svg",
            subdirectory: "ProviderIcons"
        ).flatMap(NSImage.init(contentsOf:))
    }
}

public struct ToolIconView: View {
    private let toolName: String
    private let color: Color

    public init(toolName: String, color: Color) {
        self.toolName = toolName
        self.color = color
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(color)
                    .scaledToFit()
            } else {
                Image(systemName: "hammer")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        Bundle.main.url(
            forResource: ToolIconResolver.resourceName(for: toolName),
            withExtension: "svg",
            subdirectory: "ProviderIcons"
        ).flatMap(NSImage.init(contentsOf:))
    }
}
