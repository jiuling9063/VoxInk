import SwiftUI
import VoxInkCore

struct LanguageSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        WorkspacePicker(L("界面语言"), selection: Binding(get: { store.interfaceLanguage }, set: { store.setInterfaceLanguage($0) })) {
            ForEach(InterfaceLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
        }.disabled(!store.canStart)
        Text(L("界面语言在重新打开语落后生效。")).font(.caption).foregroundStyle(.secondary)
        WorkspacePicker(L("语音语言"), selection: Binding(get: { store.speechLanguage }, set: { store.setSpeechLanguage($0) })) {
            ForEach(SpeechLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canStart)
        WorkspacePicker(L("中文输出"), selection: Binding(get: { store.chineseOutput }, set: { store.setChineseOutput($0) })) {
            ForEach(ChineseOutput.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canStart)
        Text(L("共用本地模型，无需分别下载语言包。短句识别不准时可指定语言；润色不会翻译原文。"))
            .font(.caption).foregroundStyle(.secondary)
    }
}
