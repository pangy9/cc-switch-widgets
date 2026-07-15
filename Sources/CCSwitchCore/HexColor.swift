import AppKit
import SwiftUI

public extension Color {
    /// 0xRRGGBB → Color（不透明）。
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    /// Color → 0xRRGGBB（丢弃 alpha）。用 NSColor 做 sRGB 桥接，避免 displayP3 等广色域下分量不准。
    var hexValue: UInt32 {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return (UInt32((ns.redComponent * 255).rounded()) << 16)
             | (UInt32((ns.greenComponent * 255).rounded()) << 8)
             |  UInt32((ns.blueComponent * 255).rounded())
    }
}

public extension UInt32 {
    /// WCAG 相对亮度（gamma 校正后 0.2126R + 0.7152G + 0.0722B）。
    var relativeLuminance: Double {
        func channel(_ shift: Int) -> Double {
            let v = Double((self >> shift) & 0xFF) / 255.0
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// 是否为亮色背景（相对亮度 ≥ 0.5），用于自定义主题自动判断深浅。
    var isLightBackground: Bool { relativeLuminance >= 0.5 }
}
