import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct RemoteInputSettingsView: View {
    @ObservedObject var store: AppStore
    @State private var choosingApplication = false
    @State private var errorMessage: String?
    @State private var expanded: Bool

    init(store: AppStore, initiallyExpanded: Bool = false) {
        self.store = store
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(L("远程工具"), isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("为远程工具选择粘贴方式，并在该工具中开启剪贴板同步。"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.remoteApplications) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        WorkspacePicker(profile.name, value: profile.usesControl ? "Ctrl V · Windows / Linux" : "⌘ V · Mac", selection: Binding(get: { profile.usesControl }, set: {
                            store.setRemoteApplication(.init(bundleID: profile.bundleID, name: profile.name, usesControl: $0))
                        }), options: [("⌘ V · Mac", false), ("Ctrl V · Windows / Linux", true)])
                        Button(L("移除此配置"), role: .destructive) { store.removeRemoteApplication(profile.bundleID) }
                            .font(.caption)
                        if profile.bundleID == "com.netease.uuremote" {
                            uuShortcutGuide
                        }
                    }
                    Divider()
                }
                Button(L("添加远程工具…"), systemImage: "plus") { choosingApplication = true }
                WorkspacePicker(L("剪贴板同步等待"), value: store.remotePasteTiming.title, selection: Binding(get: { store.remotePasteTiming }, set: { store.setRemotePasteTiming($0) }), options: RemotePasteTiming.allCases.map { ($0.title, $0) })
                Text(L("适用于已添加的远程工具。先用稳定档；出现旧文字或未写入时，检查远程工具的剪贴板与快捷键设置。"))
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(L("按设备覆盖粘贴方式")) {
                    VStack(alignment: .leading, spacing: 12) {
                        deviceField(L("Mac 设备"), value: Binding(get: { store.uuMacDevices }, set: { store.setUUDevices(mac: $0, windows: store.uuWindowsDevices) }))
                        deviceField(L("Windows 设备"), value: Binding(get: { store.uuWindowsDevices }, set: { store.setUUDevices(mac: store.uuMacDevices, windows: $0) }))
                        Text(L("可选：填写窗口标题中的完整设备名，多个名称用逗号分隔。仅在名称明确匹配时覆盖工具的默认粘贴方式。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }
                DisclosureGroup(L("兼容性与使用说明")) {
                    Text(L("应用配置决定发送的粘贴键，不代表远端系统已自动识别。一个工具连接不同系统时，请切换相应配置；录音期间保持同一远程会话。若快捷键被远程工具占用，可更换语落快捷键，或在工作台录音后手动复制。网页远程桌面请手动复制，避免影响同一浏览器的其他页面。"))
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                if !store.clipboardCleanupWarning.isEmpty { Text(store.clipboardCleanupWarning).font(.caption).foregroundStyle(.orange) }
            }.padding(.top, 12).disabled(!store.canStart)
        }
        .fileImporter(isPresented: $choosingApplication, allowedContentTypes: [.applicationBundle]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier else {
                    errorMessage = L("请选择已安装的远程工具。"); return
                }
                if store.remoteApplications.contains(where: { $0.bundleID == id }) {
                    errorMessage = L("这个应用已添加，可直接修改其粘贴方式。"); return
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                store.setRemoteApplication(.init(bundleID: id, name: name))
            } catch { errorMessage = error.localizedDescription }
        }
        .alert(L("远程工具"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("好"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private var uuShortcutGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("UU 远程：先设置本机快捷键")).font(.subheadline.bold())
            Text(L("在运行语落的这台 Mac 上配置 UU；语落在本机录音，再把文字写入远端。"))
            Text(L("1. 打开 UU 远程的“设置 → 键盘 → 仅控制端响应的快捷键”。"))
            Text(L("2. 点击“添加控制端快捷键”，录入 \(store.shortcutCombination.title)，点击“创建”。已有相同组合可直接保留。"))
            Text(L("3. 确认剪贴板可同步，再到远端输入框用 \(store.shortcutCombination.title) 连续试用 3 次，检查每次都能录音并写入。"))
            Text(L("语落不会自动修改 UU 设置。更换语落快捷键后，请同步更新 UU 中的组合；若设置时触发录音，先退出语落，保存后再打开。"))
                .foregroundStyle(.secondary)
        }
        .font(.callout).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).writingSurface()
    }

    private func deviceField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            WorkspaceTextField(title: title, text: value, prompt: L("完整设备名"))
                .accessibilityLabel(title)
        }
    }
}
