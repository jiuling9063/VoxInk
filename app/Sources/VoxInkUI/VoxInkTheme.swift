import SwiftUI

struct VoxInkTheme {
    let scheme: ColorScheme

    var background: Color { Color(nsColor: .windowBackgroundColor) }
    var paper: Color {
        scheme == .dark ? Color(red: 0.20, green: 0.21, blue: 0.22) : Color(nsColor: .controlBackgroundColor)
    }
    var ink: Color { Color(nsColor: .labelColor) }
    var accent: Color {
        scheme == .dark ? Color(red: 0.43, green: 0.78, blue: 0.77)
            : Color(red: 0.12, green: 0.40, blue: 0.42)
    }
    var accentForeground: Color {
        scheme == .dark ? Color(red: 0.06, green: 0.18, blue: 0.19) : .white
    }
    var ceramicGradient: LinearGradient {
        LinearGradient(colors: [paper, paper], startPoint: .top, endPoint: .bottom)
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
            .shadow(color: .black.opacity(scheme == .dark ? 0.08 : 0.025), radius: 8, y: 3)
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

/// Material belongs to navigation chrome; reading surfaces remain solid.
private struct WorkspaceChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency || contrast == .increased {
                VoxInkTheme(scheme: scheme).background
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings share the page's content edges, without Form's additional macOS gutters.
struct WorkspaceForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections: content) { section in
                VStack(alignment: .leading, spacing: 10) {
                    section.header.font(.headline).accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(section.content) { row in
                            if row.id != section.content.first?.id { Divider() }
                            row.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).writingSurface()
                    section.footer.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .toggleStyle(WorkspaceToggleStyle())
            .labeledContentStyle(WorkspaceLabeledContentStyle())
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
            .padding(24).frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    func workspacePageMargins() -> some View { modifier(WorkspacePageMargins()) }
    func writingSurface() -> some View { modifier(WritingSurface()) }
    func ceramicSurface() -> some View { modifier(WritingSurface()) }
    func workspaceChrome() -> some View { modifier(WorkspaceChrome()) }
}

/// Keep short settings choices compact; wrap the label only when space is scarce.
struct WorkspacePicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let options: Options

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Options) {
        self.title = title; self._selection = selection; self.options = content()
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
        Picker(title, selection: $selection) { options }
            .labelsHidden().pickerStyle(.menu).fixedSize()
    }
}
