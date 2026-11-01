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
                    .foregroundStyle(.secondary).opacity(hovering || focused ? 1 : 0)
                    .accessibilityHidden(true)
            }.padding(.horizontal, 8).padding(.vertical, 6)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(.primary)
        .modifier(WorkspaceChoiceSurface(active: enabled && (hovering || focused), focused: focused))
        .onHover { hovering = $0 }.focused($focused)
        .accessibilityLabel(title).accessibilityValue(value).help(value)
    }
}

private struct WorkspaceChoiceSurface: ViewModifier {
    let active: Bool
    let focused: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = VoxInkTheme(scheme: scheme)
        content
            .background(active ? theme.ink.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(active ? (focused ? theme.accent : theme.ink.opacity(0.16)) : .clear, lineWidth: 1)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                Text(L("模型")).padding(.top, 6)
                Spacer(minLength: 12)
                field
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("模型"))
                field.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var field: some View {
        WorkspaceModelInput(title: title, text: $text, commit: commit, cancel: cancel, accessory: accessory)
    }
}

private struct WorkspaceModelInput<Accessory: View>: View {
    let title: String
    @Binding var text: String
    let commit: () -> Void
    let cancel: () -> Void
    let accessory: Accessory
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            TextField(title, text: $text)
                .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: min(320, max(180, (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width + 4)))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .modifier(WorkspaceChoiceSurface(active: hovering || focused, focused: focused))
                .onHover { hovering = $0 }.focused($focused)
                .contentShape(Rectangle()).onTapGesture { focused = true }
                .onSubmit { commit(); focused = false }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { cancel(); focused = false }
                .accessibilityLabel(title).accessibilityHint(L("可输入自定义 ID"))
                .help(text)
            HStack(spacing: 12) {
                Text(L("可输入自定义 ID")).foregroundStyle(.secondary)
                accessory
            }.font(.caption).padding(.horizontal, 8)
        }
    }
}
