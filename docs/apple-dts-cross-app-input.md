# Apple 技术支持咨询草稿：沙盒内的跨应用语音输入

状态：**未发送**。此文档是待审阅的咨询内容，不是 Apple 的答复，也不表示审核已获批准。

提交入口：[Apple Code-level Support](https://developer.apple.com/support/technical/)。技术支持用于确认 API 和架构可行性；商店政策及最终审核结论仍由 App Review 决定。

## Subject

Supported architecture for user-initiated dictation insertion into another app from an App Sandbox macOS app

## Message

We are developing VoxInk, an offline dictation app for Apple silicon Macs, targeting macOS 15 and later. The user focuses a text field in another app, holds a global shortcut to dictate, then releases the shortcut. Speech recognition and optional text cleanup run locally. We want to insert the resulting text into the field the user selected.

Our directly distributed Developer ID build currently uses:

- Carbon RegisterEventHotKey for global shortcut activation.
- AXIsProcessTrusted and limited AXUIElement queries for target validation.
- NSPasteboard to stage the user's dictated text, followed by CGEvent keyboard events to invoke the target app's paste command.
- A separate optional CGEvent tap for a remote-client shortcut compatibility issue. We are decoupling this from ordinary shortcut registration; it is not a proposed sandbox workaround.

We understand that Mac App Store apps must use App Sandbox, and that Apple's “Protecting user data with App Sandbox” documentation lists assistive apps' use of Accessibility APIs as incompatible. We are not looking to use private entitlements, bypass the sandbox, or require a separately downloaded unsandboxed helper.

A local, Developer ID-signed sandbox probe on an Apple M5 running macOS 27.0 (26A428) established that microphone capture and our bundled native and Python/MLX inference helpers run inside App Sandbox. The helpers use com.apple.security.app-sandbox and com.apple.security.inherit. We have not yet repeated these tests on stable macOS versions or distributed the probe through TestFlight.

RegisterEventHotKey returned success, but physical-keyboard event delivery is not yet verified. AXIsProcessTrusted and CGPreflightPostEventAccess returned false without Accessibility authorization. We did not post events into another app; these preflight results are not presented as proof of a specific sandbox denial.

Our questions are:

1. Is there a public, supported API or architecture for this user-initiated insertion into an arbitrary foreground app's text input while the dictation app remains sandboxed?
2. If AX/CGEvent insertion is not supported, could an InputMethodKit input source, an NSServices workflow, or another public extension mechanism support this interaction? What installation, sandboxing and target-app limitations should we account for?
3. If no supported mechanism preserves this interaction, should we design the sandboxed edition around explicit copy/paste or an in-app editor?
4. Is there a specific Apple sample or documentation describing the recommended approach? We understand that technical feasibility does not guarantee App Review acceptance.

The app does not upload recorded audio or dictated text. Microphone use is explicitly initiated by the user. We can provide a small, non-confidential reproduction project for a specific API question if requested.

## 附件建议

首次咨询只提交上述说明。不要上传整个产品仓库、用户录音、真实识别文字、开发证书、凭据或模型权重。独立探针用于内部实验，并非跨应用写入的最小复现：它没有实现或测试 AX/CGEvent 写入；如 Apple 要求复现，应按指定 API 准备单独样例。

## 我们需要得到的结论

- 有公开支持的技术路线：再做针对性原型和正式系统验证。
- 仅支持特定目标应用或需要额外用户步骤：评估是否符合产品体验。
- 没有适合商店沙盒的路线：由产品负责人决定商店版功能范围，保留直装版完整体验。
