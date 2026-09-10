# 常驻模型 Worker 与 Swift 主进程联调（2026-09-08）

状态：阶段 0 常驻进程与 Swift 客户端联调通过；未实现产品 GUI 或签名 XPC 服务，正式默认模型仍未选定。

## 真实模型证据

| 模型 | Swift 驱动的同 PID 连续识别 | 单次加载 ms | 关闭后回收 |
| --- | --- | ---: | --- |
| qwen3-asr-0.6b-mlx-4bit | 3 次，PID 65406 | 622 | 通过 |
| whisperkit-large-v3-turbo | 3 次，PID 65431 | 1252 | 通过 |
| whisperkit-medium | 3 次，PID 65450 | 979 | 通过 |

模型进程 Release、Swift host Debug。上述加载耗时是本轮单次观察，不与前期正式性能口径混算。三个候选共 9 次识别成功；同一候选只加载一次，所有请求共享同一 PID。模型/分词器与音频哈希已校验，模型在禁止网络的进程沙盒中运行。

另以 resident 专项脚本验证三个候选的坏音频请求后恢复、重复 ID 拒绝、推理中父端 EOF 退出且无迟到结果；Qwen EOF 19ms、Turbo 4ms、Medium 4ms，均为单次观察。Swift 客户端取消、超时及重启使用真实子进程 fixture 验证，不等同于三个真实 ASR 经 Swift 取消的全量专项。

## 实现与回归

- 共用 `VoxInkWorkerProtocol`，64KiB 帧限制、16 条等待队列、路径和标识校验；模型 ready 后串行识别。
- Qwen 与 Whisper 保留原单条/batch 入口，新增 resident 模式。
- app 增加 `ResidentWorkerClient` actor 与 `voxink-worker-host` CLI；按进程代次和操作标识隔离结果、取消与超时，异常响应关闭连接，进程回收失败时不允许启动第二个。
- 测试：App Core 15 项、Qwen Core 6 项、共用协议 3 项、Python 28 项，合计 52 项通过。适配器审查及客户端复审均通过。

## 本轮发现并修复的问题

1. Foundation 管道读取等待缓冲区，短请求在 ready 后停住；改为 POSIX read，新增短帧和分段 UTF-8 回归。
2. 普通 exit 的清理过程可能允许 Qwen 返回迟到结果；用 atexit 延迟 fixture 复现，断连路径改为 _exit。
3. Swift 子进程未继承预期环境配置；显式传递调用者环境快照后，真实 Qwen 联调通过。
4. 匹配 ID 的畸形响应曾只返回错误但保留连接；现在验证互斥响应分支，错误关闭并回收 Worker。
5. 取消和异步写入失败回调只绑定连接代次，可能影响后续请求；增加每次操作标识检查。
6. waitUntilExit 在 Swift 任务环境出现阻塞；改为有界回收，失败保留进程引用并拒绝重复启动。

临时文件描述符诊断已撤掉。早期失败证据保留，未覆盖成成功结果。

## 证据与边界

- 有效模型协议证据：`benchmark/results/resident-eof-fixed-20260908`。
- 有效 Swift 联调证据：`benchmark/results/swift-host-verified-20260908`，含二进制/源码哈希与私人转录。
- 复现命令见 [RESIDENT-README](../benchmark/RESIDENT-README.md)。
- 当前 resident 的请求 ID 去重集合随会话增长，长期运行需会话上限或可控重启策略。
- 仍未验收：常驻客户端长期压力、产品 XPC/签名权限、100 条正式集、准确率、UU 粘贴与菜单栏录音闭环。下一步可用临时候选接入录音和结果展示，不将临时候选描述为正式模型选型。
