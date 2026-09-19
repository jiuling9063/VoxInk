# 自适应润色与常驻加载 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 多机型硬件推荐、已安装模型内自动调节、预热复用和内存释放，减少自动输入等待。
**Architecture:** 复用 ResidentWorkerClient 的行协议与取消；Python 每进程校验加载一次。独立性能策略处理设备信息与非文本统计，AppStore 只管理用户选择与生命周期。
**Tech Stack:** Swift 6 / SwiftUI / Foundation / Dispatch memory pressure / Python MLX。

## Global Constraints
- 用户已确认前述自动推荐方案，继续实施，无需重复审批。保持润色默认关闭、手动模型选择、原文回退和单次写入。
- 不新增云端推理、不静默下载、不记录原文或上传性能统计。下载按钮展示目标与大小，点击即确认。
- 低资源模式不为追求效果提高档位。闲置 120 秒释放；内存警告释放空闲模型，严重压力立即停止润色并回退。
- 不把一次冷启动计入稳态性能降级。实际生成至少 3 次偏慢才调整；手动选择只提示。

## Task 1: 可复用的润色进程
- [x] 为 ResidentWorkerClient 增加通用 JSON 交换接口，保留原识别 API 与 4096 字节限制，润色允许 32 KB 请求。
- [x] Python 支持 --resident：先校验/加载，发 ready；逐行请求带 request_id/text/max_tokens，输出 result +生成耗时。旧 CLI 保留。
- [x] LocalPolishingService 共用加载任务，支持 prepare/release/超时/取消/闲置释放；使用 -B、禁网沙箱。
- [x] 真实子进程测试覆盖复用、切换、超时、取消、EOF、字节码与现有识别回归。

## Task 2: 设备与性能策略
- [x] 新增 PolishPerformancePolicy.swift：设备快照、偏好枚举、非文本采样、推荐与已安装选择纯函数。
- [x] 测试 8/16/32/64 GB、CPU限制、磁盘不足、压力、3次慢请求、长短句归一化与手动模式。
- [x] 本机统计仅 UserDefaults 存耗时/计数，按设备签名隔离。

## Task 3: 设置与生命周期接入
- [x] 自动（推荐）和响应速度偏好，显示实际使用/推荐模型、原因、下载量与性能提示。
- [x] 旧手动选择保留，新用户默认自动；开关仍默认关。启动/开启/切换/录音准备时预热，关闭/退出/安装修复前释放。
- [x] 内存与热状态变化在下一次请求前选择，严重压力中止并保留原文。设置忙碌保护。
- [x] 检查下载可用磁盘；下载不改变开关、不自动切云端。

## Task 4: 验证与交付
- [x] swift test 全套、Python润色测试，固定非隐私样例测冷/热耗时和进程PID。
- [x] Release 0.1.3 build5：App与DMG公证、备份安装、连续UI调用、同进程复用与调用后验签完成。
- [x] 更新试用说明/进度，报告已证实的速度改善及未实测机型边界。

## 交付状态

代码与测试完成，App已公证安装。解锁后DMG公证、第二次GUI重试、同进程复用及退出清理均验证完成，详见当前进度。

## 本轮主要改动文件

- app/Sources/VoxInkCore/ResidentWorkerClient.swift
- app/Sources/VoxInkUI/PolishingService.swift
- app/Sources/VoxInkUI/PolishPerformancePolicy.swift（新增）
- app/Sources/VoxInkUI/AppStore.swift
- app/Sources/VoxInkUI/PolishModel.swift
- app/Sources/VoxInkUI/WorkspaceSettingsView.swift
- app/Sources/VoxInkUI/ContentView.swift（版本）
- script/polish_worker.py、script/build_and_run.sh
- app/Tests/VoxInkUITests/ResidentPolishingTests.swift（新增）
- app/Tests/VoxInkUITests/PolishPerformanceTests.swift（新增）
- app/Tests/VoxInkUITests/AutomaticPolishingTests.swift、PolishModelTests.swift
- script/tests/test_polish_resident.py（新增）
- docs/试用版说明-0.1.3.md、docs/当前进度.md
