import SwiftUI

/// Full input surfaces stay visible before focus, in both appearances.
struct WorkspaceInputSurface: ViewModifier {
    var focused = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor
                                  : Color.primary.opacity(contrast == .increased ? 0.65 : 0.25),
                                  lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? 1 : 0.5)
    }
}

struct WorkspaceTextField: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .focused($focused)
            .modifier(WorkspaceInputSurface(focused: focused))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(title)
    }
}
