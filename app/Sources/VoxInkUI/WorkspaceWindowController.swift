import AppKit
import Combine
import SwiftUI

@MainActor final class WorkspaceNavigation: ObservableObject {
    @Published var page: WorkspacePage = .input
}

/// Shared by the application and the fixture gallery so window chrome is verified in context.
@MainActor public final class WorkspaceWindowController: NSWindowController, NSToolbarDelegate {
    private let store: AppStore
    let navigation = WorkspaceNavigation()
    private var selectionObservation: AnyCancellable?
    private let pageLabel = NSTextField(labelWithString: WorkspacePage.input.title)

    public init(store: AppStore, restoresFrame: Bool = true) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "语音工作台 — 语落 VoxInk"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier(restoresFrame ? "voxink-main" : "voxink-window-preview")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ContentView(store: store, navigation: navigation))
        window.contentMinSize = NSSize(width: 660, height: 540)
        window.setContentSize(NSSize(width: 760, height: 700))

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
        selectionObservation = navigation.$page.sink { [weak self] page in
            self?.pageLabel.stringValue = page.title
            self?.window?.title = "\(page.title) — 语落 VoxInk"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:restoresFrame:)") }

    public func present() {
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.voxinkBrand, .voxinkPage, .flexibleSpace, .voxinkModel]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case .voxinkBrand:
            item.label = "语落 VoxInk"
            item.view = NSHostingView(rootView: ToolbarBrand())
            item.view?.widthAnchor.constraint(equalToConstant: 102).isActive = true
        case .voxinkPage:
            item.label = "当前页面"
            pageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            pageLabel.textColor = .labelColor
            pageLabel.setAccessibilityLabel("当前页面")
            item.view = pageLabel
            pageLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true
        case .voxinkModel:
            item.label = "本地模型状态"
            item.visibilityPriority = .high
            item.view = NSHostingView(rootView: ToolbarModelStatus(store: store) { [weak self] in
                self?.navigation.page = .engine
            })
            item.view?.widthAnchor.constraint(equalToConstant: 142).isActive = true
        default:
            return nil
        }
        item.view?.heightAnchor.constraint(equalToConstant: identifier == .voxinkPage ? 18 : 28).isActive = true
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let voxinkBrand = Self("voxink-brand")
    static let voxinkPage = Self("voxink-page")
    static let voxinkModel = Self("voxink-model")
}

private struct ToolbarBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            if let url = Bundle.module.url(forResource: "logo-rain-impression-v2", withExtension: "png"),
               let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 20, height: 20)
            }
            Text("语落").font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("语落 VoxInk")
        .allowsHitTesting(false)
    }
}

private struct ToolbarModelStatus: View {
    @ObservedObject var store: AppStore
    let showModel: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: showModel) {
            HStack(spacing: 6) {
                if store.modelState == .loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: store.modelState == .ready ? "circle.fill" : "exclamationmark.circle")
                        .font(.system(size: store.modelState == .ready ? 6 : 12, weight: .medium))
                }
                Text(store.modelState == .ready ? "本机就绪" : store.modelState.title)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(store.modelState == .ready ? VoxInkTheme(scheme: scheme).accent : (store.modelState == .failed ? Color.orange : .secondary))
            .padding(.horizontal, 8).frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看转录引擎与模型状态")
        .accessibilityLabel("本地模型：\(store.modelState.title)")
        .accessibilityHint("打开转录引擎设置")
    }
}
