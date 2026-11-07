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

/// Choices keep a faint resting fill and a half-visible chevron so they read as clickable
/// without hovering; hover and focus strengthen the same surface instead of revealing it.
private struct WorkspaceChoiceSurface: ViewModifier {
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

struct WorkspaceModelField<Accessory: View>: View {
    let title: String
    @Binding var text: String
    var commit: () -> Void = {}
    var cancel: () -> Void = {}
    let accessory: Accessory

    init(title: String, text: Binding<String>, commit: @escaping () -> Void = {},
         cancel: @escaping () -> Void = {}, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title; _text = text; self.commit = commit; self.cancel = cancel
        self.accessory = accessory()
    }

    var body: some View {
        WorkspaceRow(L("模型")) { field }
    }

    private var field: some View {
        WorkspaceModelInput(title: title, text: $text, commit: commit, cancel: cancel, accessory: accessory)
    }
}

/// Model IDs are free text: a resting underline marks the field, the hint is a placeholder,
/// and the catalogue button sits inline at the trailing end.
private struct WorkspaceModelInput<Accessory: View>: View {
    let title: String
    @Binding var text: String
    let commit: () -> Void
    let cancel: () -> Void
    let accessory: Accessory
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let theme = VoxInkTheme(scheme: scheme)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TextField(title, text: $text, prompt: Text(L("可输入自定义 ID")))
                .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.leading)
                .focused($focused)
                .onTapGesture { focused = true }
                .onSubmit { commit(); focused = false }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { cancel(); focused = false }
                .accessibilityLabel(title).accessibilityHint(L("可输入自定义 ID"))
                .help(text)
            accessory.font(.caption)
        }
        .padding(.vertical, 5)
        .frame(minWidth: 200, maxWidth: 360, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused ? theme.accent : theme.ink.opacity(!enabled ? 0.08 : (hovering ? 0.32 : 0.18)))
                .frame(height: focused ? 2 : 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .onHover { hovering = $0 }
    }
}
