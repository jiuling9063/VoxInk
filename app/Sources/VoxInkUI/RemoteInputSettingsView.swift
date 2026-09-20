import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct RemoteInputSettingsView: View {
    @ObservedObject var store: AppStore
    @State private var choosingApplication = false
    @State private var errorMessage: String?

    var body: some View {
        DisclosureGroup("远程输入") {
            VStack(alignment: .leading, spacing: 16) {
                Text("为远程应用选择粘贴方式，并在该工具中开启剪贴板同步。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.remoteApplications) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        WorkspacePicker(profile.name, selection: Binding(get: { profile.usesControl }, set: {
                            store.setRemoteApplication(.init(bundleID: profile.bundleID, name: profile.name, usesControl: $0))
                        })) {
                            Text("⌘ V · Mac").tag(false)
                            Text("Ctrl V · Windows / Linux").tag(true)
                        }
                        Button("移除此配置", role: .destructive) { store.removeRemoteApplication(profile.bundleID) }
                            .font(.caption)
                    }
                    Divider()
                }
                Button("添加远程应用…", systemImage: "plus") { choosingApplication = true }
                WorkspacePicker("剪贴板同步等待", selection: Binding(get: { store.remotePasteTiming }, set: { store.setRemotePasteTiming($0) })) {
                    ForEach(RemotePasteTiming.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("适用于已添加的应用及 UU。先用稳定档；出现旧文字或未写入时，检查远程工具的剪贴板与快捷键设置。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("UU 设备识别（已有配置）") {
                    VStack(alignment: .leading, spacing: 12) {
                        deviceField("Mac 设备", value: Binding(get: { store.uuMacDevices }, set: { store.setUUDevices(mac: $0, windows: store.uuWindowsDevices) }))
                        deviceField("Windows 设备", value: Binding(get: { store.uuWindowsDevices }, set: { store.setUUDevices(mac: store.uuMacDevices, windows: $0) }))
                        WorkspacePicker("未识别设备时", selection: Binding(get: { store.uuWindowsPaste }, set: { store.setUUWindowsPaste($0) })) {
                            Text("⌘ V · Mac").tag(false)
                            Text("Ctrl V · Windows / Linux").tag(true)
                        }
                        Text("填写窗口中的完整设备名，多个名称用逗号分隔。全屏或名称不明确时使用上方手动选择。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }
                DisclosureGroup("兼容性与使用说明") {
                    Text("应用配置决定发送的粘贴键，不代表远端系统已自动识别。一个工具连接不同系统时，请切换相应配置；录音期间保持同一远程会话。若快捷键被远程工具占用，可更换语落快捷键，或在工作台录音后手动复制。网页远程桌面请手动复制，避免影响同一浏览器的其他页面。")
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
                    errorMessage = "请选择已安装的远程应用。"; return
                }
                if id == "com.netease.uuremote" {
                    errorMessage = "UU 已有配置，请展开“UU 设备识别”。"; return
                }
                if store.remoteApplications.contains(where: { $0.bundleID == id }) {
                    errorMessage = "这个应用已添加，可直接修改其粘贴方式。"; return
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                store.setRemoteApplication(.init(bundleID: id, name: name))
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("远程应用", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private func deviceField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("完整设备名", text: value).textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
    }
}
