# 0.1.1 侧栏与就绪状态修复

目标：接通已存在的五个侧栏入口，修正录音准备状态，保留紧凑浮层并提供失败指引。

方案：保留当前 SwiftUI 风格；主窗口和偏好设置共用输入、模型、润色与文字规则控件，调用现有 AppStore 方法。页面枚举采用穷举分支。录音就绪要求空闲、麦克风已允许、模型已加载；自动写入准备仍要求辅助功能和快捷键可用。失败浮层显示进入主窗口查看详情的提示，详细恢复操作沿用仪表板。

范围：macOS 15+，不新增依赖、联网行为或自动润色写入。用户本轮已确认继续上述修复；保留此前未提交的界面修改。

- [x] 在 SetupStateTests 中覆盖模型未就绪、忙碌、权限撤销及无需自动写入权限的录音就绪判断，运行失败验证。
- [x] AppStore 增加 canRecord，ContentView 使用该属性；准备操作在忙碌时禁用。
- [x] WorkspaceSettingsView 增加枚举及五个实际页面；PreferencesView 复用输入、模型与润色控件，保留登录项和词典。
- [x] 失败浮层添加可见详情提示，测试其可读高度和固定宽度。
- [x] 运行定向测试、完整 App 测试和界面检查，更新当前进度；记录尚未完成的实体录音与跨设备验收。

验证命令：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta --disable-automatic-resolution --filter SetupStateTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta --disable-automatic-resolution
bash script/run_interface_check.sh
git diff --check
```

验证结果：2026-09-12 完整 App 180 项测试通过，界面与浮层检查器构建并检查通过；本批没有替换正式 App，实体录音和跨设备验收仍待完成。
