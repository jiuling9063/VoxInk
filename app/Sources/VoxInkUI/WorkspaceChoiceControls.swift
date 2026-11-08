import AppKit
import SwiftUI
import VoxInkCore

struct WorkspaceMenu<Options: View>: View {
    let title: String
    let value: String
    @ViewBuilder var options: Options
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Menu {
            options
        } label: {
            HStack(spacing: 6) {
                Text(value).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    .frame(width: min(300, (value as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 2))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(!enabled ? 0 : (hovering || focused ? 1 : 0.45))
                    .accessibilityHidden(true)
            }.padding(.horizontal, 8).padding(.vertical, 5)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(enabled ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        .modifier(WorkspaceChoiceSurface(hovering: hovering, focused: focused, enabled: enabled))
        .onHover { hovering = $0 }.focused($focused)
        .accessibilityLabel(title).accessibilityValue(value).help(value)
    }
}

/// Shared label for the two adjacent service and model selectors.
struct ServiceChoiceLabel: View {
    let value: String
    var modelID = false

    var body: some View {
        HStack(spacing: 10) {
            Text(value)
                .font(modelID ? .system(size: 12.5, design: .monospaced) : .body.weight(.medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 36)
        .contentShape(Rectangle())
    }
}

/// Choices keep a faint resting fill and a half-visible chevron so they read as clickable
/// without hovering; hover and focus strengthen the same surface instead of revealing it.
struct WorkspaceChoiceSurface: ViewModifier {
    let hovering: Bool
    let focused: Bool
    let enabled: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let theme = VoxInkTheme(scheme: scheme)
        let active = enabled && (hovering || focused)
        let fill: Color = !enabled ? .clear : (active ? theme.ink.opacity(0.08) : theme.fieldFill)
        let stroke: Color = active ? (focused ? theme.accent : theme.ink.opacity(0.16))
            : (enabled && contrast == .increased ? theme.ink.opacity(0.35) : .clear)
        content
            .background(fill, in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}
