# VoxInk 界面与动效复盘 · 2026-09-20

基线 b3049ee（0.1.7），本轮修复随 0.1.9。原生 SwiftUI/AppKit，最低 macOS 15。

## 技能与方法

使用 Emil 套件适用于本产品的四个审查视角：emil-design-eng、improve-animations（含 AUDIT.md）、review-animations（含 STANDARDS.md）、find-animation-opportunities。animate 的频率门槛用于判断是否需要新增动效。本轮不新增装饰动画。Web/React Native 专属工具、CSS/WAAPI、Sonner、Expo 不用于原生 SwiftUI 实现；不把“整套复盘”解释为强行使用所有不相关框架。

两路只读审查分别覆盖交互页面和动效，再由主任务核对代码与实际界面。审查技能仅用于分析；实现修改按用户已授权的界面优化和通用远程适配请求完成。

## 已处理发现

| 优先级 | Before | After | Why |
| --- | --- | --- | --- |
| P2 | 自定义 Toggle 内部标签为空，读屏名称依赖容器推断 | 内部原生 Toggle 保留标签，视觉副本不重复读出 | 保留明确的读屏名称 |
| P2 | Picker 拉满整行 | 共享 WorkspacePicker，标签靠左、内容宽度靠右；空间不足上下排列 | 短选项不需要长输入框，保留系统菜单与键盘支持 |
| P2 | 远程策略绑定特定品牌 | 用户选择应用后保存独立粘贴键，普通应用不变；已有设备设置迁移保留 | 通用能力不依赖品牌列表 |
| P2 | 导航对整个页面使用 0.3s spring，偏好内容淡入 | 页面与分类立即切换 | 高频及键盘导航不应等待整页运动 |
| P2 | 减少动态效果时音量恒定 | 固定几何，实时亮度与读屏百分比 | 减少运动不等于丢失输入反馈 |
| P2 | 识别、加载、写入只显示静态点 | 增加准备中、识别中、写入中等短标签 | 明确系统所处阶段，无需装饰性旋转 |
| P2 | 历史复制结果只显示在列表顶部 | 反馈紧邻对应条目，并增加按钮读屏上下文 | 滚动后仍能确认操作结果 |
| P2 | 导入/保存只禁用按钮 | 明确显示正在导入/正在保存 | 避免慢存储时被误认为没有响应 |
| P3 | 忙碌时权限摘要变橙色“检查” | 处理中保持中性“权限与模型” | 避免把忙碌误报为准备失败 |

主要位置：VoxInkTheme.swift（共享控件）、WorkspaceSettingsView.swift、RemoteInputSettingsView.swift、ContentView.swift、PreferencesView.swift、RecordingFeedbackView.swift、RecordingPulse.swift、SessionHistoryView.swift、DictionaryImportView.swift、DictionaryPreferencesView.swift；远程逻辑位于 AppStore.swift、PasteService.swift、VoxInkCore/PasteCoordinator.swift。

## 全界面覆盖

| 区域 | 代码复核 | 界面验证及结论 |
| --- | --- | --- |
| 标题栏、侧栏、页脚 | 完成 | 页脚固定底部、导航滚动；沿用原生窗口交互 |
| 语音工作台 | 完成 | 窄窗口就绪、录音、识别、目标失效状态检查；主要按钮文字完整 |
| 首次准备 | 完成 | 权限/模型状态与下一步操作相邻；开始使用禁用原因可见 |
| 转录历史、统计 | 完成 | 空状态、计数和保留范围清楚；复制反馈改为就地显示 |
| 转录引擎、权限 | 完成 | 窄窗口状态、按钮、折叠说明正常 |
| 快捷键、远程输入 | 完成 | 深色宽/窄窗口选择器正常；实际添加测试应用并切换 Control 粘贴 |
| 润色模型 | 完成 | 浅色窄窗口紧凑控件，主要信息与详情分层；开关 AX 名称保留 |
| 文字与词典、导入弹窗 | 完成 | 窄窗口入口未挤压；保存反馈完善；导入流程已有前版实测 |
| 使用方法 | 完成 | 窄窗口三步竖排、FAQ 折叠；宽窗口规则沿用 |
| 偏好设置 | 完成 | 删除分类内容动画，复用同一套紧凑控件与开关 |
| 录音浮层 | 完成 | 所有阶段文字与音量 AX 百分比实机检查；声音波形为状态反馈 |

## 动效判断

| Location | Today / After | Purpose | Frequency | Decision |
| --- | --- | --- | --- | --- |
| RecordingFeedbackView | 录音期间 30 Hz Canvas，固定尺寸；减少动态时暂停时间轴并保留亮度信息 | 状态反馈 | 高频 | 保留，非装饰运动；未测 Instruments 帧率 |
| VoxInkTheme | 按压亮度与 0.98 缩放；减少动态时无缩放 | 按压反馈 | 高频 | 保留即时反馈，不加延时 |
| RecordingPanel | 浮层立即显隐；新状态取消旧关闭任务 | 输入状态 | 高频键盘操作 | 保留即时操作，不加入口动画 |

拒绝候选：主导航、录音浮层开关属于高频/键盘动作，不加弹跳；结果正文和统计数字是阅读内容，不加逐字或计数动画；词库导入使用明确进度文案，不增加庆祝。没有必须新增的装饰动效。

动效代码结论：**Approve（本轮已检查范围）**。减少动态效果的几何稳定/音量信息、阶段文字有测试；此结论不等同于跨设备帧率、VoiceOver 全流程或所有远程软件兼容认证。

## 未完成的产品增强与上架验证

- P2：词典单条删除仍无撤销。建议增加一次撤销恢复，并验证恢复冲突，不增加每次删除确认框。
- P3：导入 100 条后缺少词条搜索。建议添加按识别词/正确写法过滤，保留编辑入口。
- 通用远程配置未识别远端会话身份：录音期间必须保持同一连接。已配置且窗口标题精确匹配的设备保留切换保护。后续按实际客户端能力引入会话识别，不推测未知系统。
- 上架前建立远程测试矩阵：每个实际客户端 × Mac/Windows/Linux × 窗口/全屏 × 多设备切换 × 剪贴板同步开关 × 快捷键冲突。现阶段不可宣称全工具端到端兼容。
- 使用 VoiceOver、减少动态效果/提高对比度、Instruments 实测重负载帧率及连续录音取消；本轮以单元测试、AX 树和检查版窗口为证据。

## 验证证据

Swift 最终 260 项常规测试通过，1 项真实下载测试默认跳过。新增覆盖通用远程键选择、录音目标快照、普通应用隔离、取消/剪贴板变更阻止发送、配置持久化更新移除、减少动态音量反馈及阶段文字。测试日志 /tmp/voxink-hud-tests.log。

实际 UI 检查使用内存替身，不向真实远端发送输入，不改动用户的正式词库/远程配置。未修改全局辅助功能或动画偏好。

## 修复定位（当前版本）

- `app/Sources/VoxInkUI/VoxInkTheme.swift:128` 开关语义；`:165` 紧凑选择器。
- `app/Sources/VoxInkUI/ContentView.swift:118` 即时导航；`PreferencesView.swift:71` 即时分类内容。
- `app/Sources/VoxInkCore/PasteCoordinator.swift:25` 通用应用配置；`:299` 远程同步及粘贴策略。
- `app/Sources/VoxInkUI/RecordingFeedbackView.swift:23` 阶段文字；`:35` 父级音量读屏值。
- `app/Sources/VoxInkUI/RecordingPulse.swift:19` 减少动态效果的固定几何。
- `app/Sources/VoxInkUI/SessionHistoryView.swift:53` 条目旁复制反馈。
- `app/Sources/VoxInkUI/DictionaryImportView.swift:45` 导入反馈；`DictionaryPreferencesView.swift:144` 保存反馈。

## HUD 延迟补充复核

| Before | After | Why |
| --- | --- | --- |
| 本地按键发送后仍等待 1.2 秒剪贴板恢复才结束状态 | 按键发送成功即返回，后台恢复剪贴板；下次操作和退出等待清理 | 移除确定的完成反馈延迟，保留剪贴板安全时长 |
| 每个状态重新创建两份 NSHostingView 并测量 | 固定 44/60pt 高度，复用同一个 hosting view，合并状态通知 | 减少主线程重复布局，保留波形连续性 |
| 远程设备识别遍历窗口后代节点 | 仅查询窗口标题，并设置 AX 请求超时 | 避免快捷键入口扫描大量远端内容 |
| 页面固定出现某个远程品牌 | 统一称为远程工具，按用户选择的应用配置 | 产品适用于用户自己的工具 |

按键已发送不代表远端已确认插入。真实语音及不同远程传输链路的端到端延迟仍需实机验证，不宣称零延迟。

补充验证：260 项 Swift 测试通过、1 项真实下载测试跳过，覆盖后台剪贴板恢复、HUD 复用与同步隐藏、配置迁移及删除持久化。
