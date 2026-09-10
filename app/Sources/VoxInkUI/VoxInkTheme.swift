import SwiftUI

struct VoxInkTheme {
    let scheme: ColorScheme

    var background: Color {
        scheme == .dark ? Color(red: 32 / 255, green: 39 / 255, blue: 41 / 255)
            : Color(red: 242 / 255, green: 240 / 255, blue: 234 / 255)
    }

    var paper: Color {
        scheme == .dark ? Color(red: 43 / 255, green: 51 / 255, blue: 54 / 255)
            : Color(red: 250 / 255, green: 249 / 255, blue: 245 / 255)
    }

    var ink: Color {
        scheme == .dark ? Color(red: 237 / 255, green: 239 / 255, blue: 235 / 255)
            : Color(red: 36 / 255, green: 48 / 255, blue: 55 / 255)
    }

    var accent: Color {
        scheme == .dark ? Color(red: 169 / 255, green: 205 / 255, blue: 208 / 255)
            : Color(red: 84 / 255, green: 126 / 255, blue: 134 / 255)
    }
}

private struct WritingSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let theme = VoxInkTheme(scheme: scheme)
        content
            .background(theme.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(theme.ink.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func writingSurface() -> some View { modifier(WritingSurface()) }
}
