import AppKit
import SwiftUI
import Testing
@testable import VoxInkUI

@MainActor struct WorkspaceThemeTests {
    @Test func readingAndPrimaryActionsRemainLegibleInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
            let theme = VoxInkTheme(scheme: scheme)
            var ratios: [Double] = []
            appearance.performAsCurrentDrawingAppearance {
                ratios = [
                    contrast(theme.ink, theme.paper),
                    contrast(theme.ink, theme.background),
                    contrast(theme.accent, theme.paper),
                    contrast(theme.accentForeground, theme.accent)
                ]
            }
            // WCAG AA for normal text, including the primary button's label.
            for ratio in ratios { #expect(ratio >= 4.5) }
        }
    }

    private func contrast(_ first: Color, _ second: Color) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: Color) -> Double {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .nan }
        func linear(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }
}
