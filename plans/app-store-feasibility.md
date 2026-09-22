# Mac App Store 可行性验证 · 2026-09-22

基线：9611ac6，已安装 VoxInk 0.1.9（11）。本轮仅新增独立探针和证据，不修改正式 App，不改变产品功能，也不提交审核。

## 结论

**当前完整产品上架：Block。沙盒内本地模型路线：有实测支持。**

录音、Metal、Python/MLX 和两个模型可以在真实 App Sandbox 中运行；当前 sandbox-exec 子进程包装层不能直接沿用。核心“在任意应用自动写入”的商店兼容路线仍未成立，不能把本轮结果称为已经可提交商店。

## 实测结果

环境：Apple M5；macOS 27.0 (26A428)；独立 bundle ID `local.voxink.sandbox-probe`。测试 App 使用 Developer ID 本地签名及 Hardened Runtime，未使用商店分发证书或 TestFlight。运行时 sandbox entitlement 为 true，home 指向独立容器。父 App 没有网络 entitlement。

| 检查 | 结果 | 解释 |
| --- | --- | --- |
| 主 App 沙盒及容器 | 通过 | 沙盒键为 1，路径在 Library/Containers 下 |
| Python/MLX GPU | 通过 | GPU Device(gpu, 0)，数组求和为 6 |
| 识别模型加载及推理 | 通过运行验证 | 模型加载 650ms，1 秒静音推理 2875ms，返回 empty_transcript；不代表语音准确率通过 |
| 轻量润色模型加载及推理 | 通过运行验证 | 子进程退出 0，生成约 1.455 秒；固定重复句被 guard 以 unsupported_content_edit 拒绝，保留原文；质量仍待改善 |
| 现有 sandbox-exec 包装 | 失败 | exit 71：sandbox_apply: Operation not permitted |
| 直接启动继承沙盒的已签名 helper | 通过 | Python 和原生 ASR helper 均完成测试；无需关闭库验证或申请临时例外 |
| 麦克风 | 通过采集验证 | 录得 16549 帧，临时文件删除；没有保存、识别或上传录音 |
| Carbon 全局快捷键注册 | 通过注册验证 | InstallEventHandler 和 RegisterEventHotKey 都返回 0 |
| 快捷键真实触发 | 待验证 | 自动化向前台/后台发送组合键后没有接收日志；需实体键盘复测，不能据此归因为沙盒拒绝 |
| 跨应用自动写入 | 未验证通过 | AX trusted/event-post preflight 为 false，未授权、未向其他 App 投递按键；这两个值本身不能区分 TCC 未授权和沙盒限制 |
| 在线模型下载、重启后的文件授权 | 未覆盖 | 本轮用系统选择器临时授权访问离线模型副本，没有网络权限，也未测试持久 bookmark |

证据：`benchmark/app-store-probe/evidence/2026-09-22-macos27-m5.txt`。原始完整日志在探针容器的 `Library/Application Support/VoxInkSandboxProbe/results.txt`。

## 确认的产品迁移点

1. `TranscriptionService.swift`、`PolishingService.swift` 当前通过 `/usr/bin/sandbox-exec` 启动。商店架构应将推理隔离为单独的受限服务或继承沙盒 helper，不能简单删除网络禁令后让推理进程获得下载器网络权限。本轮离线探针的父 App 无网络权限；生产主 App 将需要下载权限，应单独设计下载/推理权限边界。
2. 原生 worker 和 Python 可执行文件需要 app-sandbox + inherit 签名。依赖库仍需有效签名。本轮没有开启 disable-library-validation/JIT 例外；实际所有模型和系统版本仍需覆盖。
3. 模型存储改为容器内位置，老用户迁移需用户授权。探针使用临时文件选择授权只证明基本访问可行，不是完整迁移方案。
4. `GlobalShortcutController` 的默认 Option+Space 注册会先启动 `RemoteOptionSpaceMonitor`，后者要求 AXIsProcessTrusted 并创建可修改事件的全局 tap。普通快捷键注册和这项远程兼容补丁需要分离；本轮没有把探针注册成功等同于产品默认快捷键可用。
5. `PasteCoordinator` 的跨应用 AX 查询和模拟粘贴仍是关键阻塞。Apple 明确将辅助工具调用 Accessibility APIs 列为不兼容 App Sandbox 的功能。不能把正常用户授予辅助功能权限、私有 entitlement 或站外 helper 当成已获商店认可的解决方案。
6. 模型下载需限定数据文件类型；现有 snapshot_download 下载整个固定 revision，固定哈希并不等于只有数据文件。代码随包提交、模型许可及下载告知另行复核。

## 下一步决策门槛

优先向 Apple Developer Technical Support 咨询：在 App Sandbox 中，是否存在公开且适合商店分发的方式，将用户主动口述的文本写入任意前台应用？需要提供使用的 AX/CGEvent API、权限说明和最小示例。咨询尚未发送。

若没有符合要求且保持体验的路线：

- 公证直装版继续保留全局自动输入及远程工具支持。
- 商店版可考虑在 App 内识别/润色、复制结果或系统支持的服务入口；这是产品体验变化，需要用户决定，不能默默降级。
- InputMethodKit 等替代方案只能作为待调研候选，未验证分发与审核可行性，不计入通过项。

在这个门槛解决之前，不值得先完成整套商店迁移。隐私政策、PrivacyInfo.xcprivacy、依赖许可、App Store Connect 元数据、正式 SDK 构建和多机型稳定性仍是后续必要工作。

## 官方依据（2026-09-22 核对）

- [App Sandbox 不兼容功能](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [子进程继承 App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [App 审核指南 2.4.5 / 4.2.3 / 5.1.1](https://developer.apple.com/cn/app-store/review/guidelines/)
- [沙盒麦克风 entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.microphone)

## 本轮新增文件与验证

- benchmark/app-store-probe/Probe.swift：独立沙盒运行检查器。
- benchmark/app-store-probe/App.entitlements、Child.entitlements：主进程及 helper 权限。
- benchmark/app-store-probe/README.md、evidence/2026-09-22-macos27-m5.txt：复现与结果。
- script/run_app_store_probe.sh：隔离构建、签名和模型副本准备。
- plans/app-store-feasibility.md：本报告。

通过 swiftc typecheck、bash -n、codesign --verify --deep --strict；从真实 GUI 启动探针执行上述检查。正式产品代码未修改，因此没有将原有 260 项测试的历史结果记为本轮新跑测试。
