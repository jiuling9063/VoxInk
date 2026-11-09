import VoxInkCore
import AppKit
import Combine
import SwiftUI

@MainActor final class WorkspaceNavigation: ObservableObject {
    @Published var statistics = false

    func open(_ route: String) {
        if route == "statistics" || route == "history" {
            statistics = route == "statistics"
            page = .history
        } else if let destination = WorkspacePage(rawValue: route) {
            page = destination
        }
    }
    @Published var page: WorkspacePage = .input
}

/// Shared by the application and the fixture gallery so window chrome is verified in context.
@MainActor public final class WorkspaceWindowController: NSWindowController, NSToolbarDelegate {
    private let store: AppStore
    let navigation = WorkspaceNavigation()
    private var selectionObservation: AnyCancellable?
    private var remoteSystemObservation: AnyCancellable?

    public init(store: AppStore, restoresFrame: Bool = true) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L("语音工作台 — 语落 VoxInk")
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier(restoresFrame ? "voxink-main" : "voxink-window-preview")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ContentView(store: store, navigation: navigation))
        window.contentMinSize = NSSize(width: 660, height: 540)
        window.setContentSize(NSSize(width: 1000, height: 750))

        let toolbar = NSToolbar(identifier: "voxink-workspace-toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.titlebarSeparatorStyle = .none
        window.toolbar = toolbar
        if restoresFrame {
            if !window.setFrameUsingName("voxink-main") { window.center() }
            window.setFrameAutosaveName("voxink-main")
        } else {
            window.center()
        }
        remoteSystemObservation = store.$remoteSystemRequest.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] tool in
            self?.presentRemoteSystemChoice(tool)
        }
        selectionObservation = navigation.$page.sink { [weak self] page in
            self?.window?.title = L("\(page.title) — 语落 VoxInk")
        }
    }

    private func presentRemoteSystemChoice(_ tool: RemoteToolChoice) {
        guard let window, store.remoteSystemRequest?.id == tool.id else { return }
        present()
        let panel = NSPanel()
        let view = RemoteSystemChoiceView(store: store, tool: tool) { [weak window, weak panel] in
            if let panel { window?.endSheet(panel) }
        }
        panel.contentViewController = NSHostingController(rootView: view)
        window.beginSheet(panel) { [weak self] _ in
            self?.store.remoteSystemRequest = nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:restoresFrame:)") }

    public override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(navigation.page == .history && navigation.statistics ? "statistics" : navigation.page.rawValue, forKey: "page")
    }

    public override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        if let route = coder.decodeObject(of: NSString.self, forKey: "page") as String? { navigation.open(route) }
    }

    public func openRoute(_ route: String) { navigation.open(route) }

    public func present() {
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.voxinkBrand, .flexibleSpace, .voxinkModel]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case .voxinkBrand:
            item.label = L("语落 VoxInk")
            item.view = NSHostingView(rootView: ToolbarBrand())
            item.view?.widthAnchor.constraint(equalToConstant: 102).isActive = true
        case .voxinkModel:
            item.label = L("语音识别")
            item.visibilityPriority = .high
            item.view = NSHostingView(rootView: ToolbarModelStatus(store: store) { [weak self, store] in
                self?.navigation.page = store.readinessDestination
            })
            item.view?.widthAnchor.constraint(equalToConstant: 150).isActive = true
        default:
            return nil
        }
        item.view?.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let voxinkBrand = Self("voxink-brand")
    static let voxinkModel = Self("voxink-model")
}

private struct ToolbarBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            if let url = Bundle.module.url(forResource: "logo-rain-impression-v2", withExtension: "png"),
               let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 20, height: 20)
            }
            Text(L("语落")).font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("语落 VoxInk"))
        .allowsHitTesting(false)
    }
}

/// A short readiness chip; the full status lives in the tooltip and the workbench pipeline.
private struct ToolbarModelStatus: View {
    @ObservedObject var store: AppStore
    let showModel: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var loading: Bool { store.modelServices.transcriptionID == nil && store.modelState == .loading }
    private var issues: Int { store.readinessIssueCount }

    private var title: String {
        if loading { return L("正在加载") }
        if issues > 0 { return L("需处理 \(issues) 项") }
        return store.modelServices.transcriptionID == nil ? L("本地 · 就绪") : L("API · 就绪")
    }

    var body: some View {
        let theme = VoxInkTheme(scheme: scheme)
        let tint: Color = loading ? .secondary : (issues > 0 ? theme.caution : theme.accent)
        Button(action: showModel) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(tint).frame(width: 6, height: 6)
                }
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).frame(height: 24)
            .background(tint.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.readinessSummary)
        .accessibilityLabel(store.readinessSummary)
        .accessibilityHint(store.readinessDestination.title)
    }
}

extension AppStore {
    var readinessDestination: WorkspacePage {
        if !transcriptionReady && modelState != .loading { return .engine }
        return microphoneAuthorization != .authorized || !pastePermissionGranted || !shortcutAvailable ? .shortcut : .engine
    }

    /// Items the user has to act on before dictation works end to end.
    var readinessIssueCount: Int {
        var count = 0
        if microphoneAuthorization != .authorized { count += 1 }
        if !transcriptionReady && !(modelServices.transcriptionID == nil && modelState == .loading) { count += 1 }
        if !pastePermissionGranted { count += 1 }
        if !shortcutAvailable { count += 1 }
        return count
    }

    /// Full, single-line readiness status for tooltips and VoiceOver.
    var readinessSummary: String {
        var parts = [transcriptionStatus]
        if microphoneAuthorization != .authorized { parts.append(L("需要麦克风权限")) }
        if !pastePermissionGranted { parts.append(L("需要辅助功能权限")) }
        if !shortcutAvailable { parts.append(shortcutStatus) }
        return parts.joined(separator: " · ")
    }
}
