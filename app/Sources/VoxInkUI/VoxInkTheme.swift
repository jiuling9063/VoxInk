import SwiftUI

struct VoxInkTheme {
    let scheme: ColorScheme

    var background: Color {
        scheme == .dark ? Color(red: 0.125, green: 0.149, blue: 0.153)
            : Color(red: 0.945, green: 0.957, blue: 0.953)
    }
    var chrome: Color {
        scheme == .dark ? Color(red: 0.106, green: 0.133, blue: 0.137)
            : Color(red: 0.91, green: 0.937, blue: 0.929)
    }
    var paper: Color {
        scheme == .dark ? Color(red: 0.161, green: 0.192, blue: 0.196) : .white
    }
    var ink: Color { Color(nsColor: .labelColor) }
    var accent: Color {
        scheme == .dark ? Color(red: 0.522, green: 0.808, blue: 0.780)
            : Color(red: 0.12, green: 0.40, blue: 0.42)
    }
    var accentForeground: Color {
        scheme == .dark ? Color(red: 0.06, green: 0.18, blue: 0.19) : .white
    }
    var ceramicGradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(scheme == .dark ? 0.09 : 0.05), .clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WritingSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let theme = VoxInkTheme(scheme: scheme)
        content
            .background(theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.ink.opacity(contrast == .increased ? 0.55 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.06 : 0.025), radius: 8, y: 3)
    }
}

struct VoxInkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = VoxInkTheme(scheme: scheme)
        let foreground = configuration.role == .destructive ? Color.red : theme.ink
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(prominent ? theme.accentForeground : foreground)
            .background(prominent ? theme.accent : theme.ink.opacity(hovered && enabled ? 0.10 : 0.055),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(theme.ink.opacity(contrast == .increased ? 0.55 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .brightness(configuration.isPressed && enabled ? -0.06 : 0)
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}

/// Solid chrome keeps navigation and reading contrast stable over other windows.
private struct WorkspaceChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background(VoxInkTheme(scheme: scheme).chrome)
    }
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Settings share the page's content edges, without Form's additional macOS gutters.
struct WorkspaceForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections: content) { section in
                VStack(alignment: .leading, spacing: 9) {
                    section.header.font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 3).accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(section.content) { row in
                            row.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18).writingSurface()
                    section.footer.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .toggleStyle(WorkspaceToggleStyle())
            .labeledContentStyle(WorkspaceLabeledContentStyle())
    }
}

struct WorkspaceSectionHeader: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String
    var number: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(VoxInkTheme(scheme: scheme).accent)
                .frame(width: 36, height: 36)
                .background(VoxInkTheme(scheme: scheme).accent.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            if let number {
                Text(number).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct WorkspaceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch)
        }
    }
}

private struct WorkspaceLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content.foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WorkspacePageMargins: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    func workspacePageMargins() -> some View { modifier(WorkspacePageMargins()) }
    func writingSurface() -> some View { modifier(WritingSurface()) }
    func ceramicSurface() -> some View { modifier(WritingSurface()) }
    func workspaceChrome() -> some View { modifier(WorkspaceChrome()) }
}

/// Keep short settings choices compact; wrap the label only when space is scarce.
struct WorkspacePicker<Selection: Hashable>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    let options: [(String, Selection)]

    init(_ title: String, value: String, selection: Binding<Selection>, options: [(String, Selection)]) {
        self.title = title; self.value = value; self._selection = selection; self.options = options
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 12)
                choice
            }
            VStack(alignment: .leading, spacing: 8) { Text(title); choice }
        }
    }
    private var choice: some View {
        WorkspaceMenu(title: title, value: value) {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    if selection == options[index].1 {
                        Label(options[index].0, systemImage: "checkmark")
                    } else { Text(options[index].0) }
                }
            }
        }
    }
}
