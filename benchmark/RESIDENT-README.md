# 常驻模型进程

阶段 0 的 resident 模式用于验证加载复用与 Swift 进程客户端，尚不是签名 XPC 服务。模型必须先按已有模型清单准备。

## 模型入口

```bash
# Qwen，环境 QWEN3_CACHE_DIR 指向现有 VoxInkBenchmark 缓存根
voxink-qwen-smoke --resident --manifest /absolute/path/benchmark/model-manifest.json
# Whisper，必须指定已验证的模型与分词器目录
voxink-whisper-smoke /absolute/model-folder /absolute/tokenizer-folder --resident
```

加载完毕后 stdout 输出一次 `{type:ready,protocol_version:1,pid,load_ms}`。保持 stdin 管道打开，每行写入一个 `{request_id,sample_id,audio_path}` 请求；成功或请求级音频错误均返回 `{request_id,result,error_code}`。result 包含 raw_text、success、load_ms、transcribe_ms、peak_rss_bytes，允许候选附加原有元数据。诊断仅写 stderr。

每个进程只创建一次模型，串行处理请求。同一连接内 request_id 不得重复。非法 JSON、无效 ID、相对或含 .. 的路径、超过 64KiB 的帧、超过 16 条等待请求会使连接失效。请求 ID 去重集合目前随会话增长，不适合作为无限期不重启的产品服务。

父端关闭 stdin 表示放弃此连接及所有待处理请求。独立输入线程立即结束进程，覆盖模型加载与同步推理期间；父端应一直保持管道打开直到收到所需结果。取消由主进程结束 worker、丢弃旧代次结果并按需重启；模型将重新加载，没有声称保留引擎内部状态的协作式取消。

## 验证

从仓库根目录执行，二进制须已使用当前源码重新构建：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path benchmark/worker-protocol --scratch-path /tmp/voxink-worker-protocol
python3 -m unittest discover -s script/tests
python3 script/check_resident_worker.py --qwen-binary /tmp/voxink-qwen-xcode-beta/out/Products/Release/voxink-qwen-smoke --whisper-binary /tmp/voxink-whisper-smoke/out/Products/Release/voxink-whisper-smoke --output benchmark/results/resident-NEW
```

真实验证以 sandbox-exec 禁止模型进程网络，加载前与整组结束后复核模型/分词器；每份 WAV 核对清单哈希。验证同 PID 连续识别、坏音频请求后恢复、重复 ID 拒绝、推理中的 EOF 终止且不返回迟到结果。完整原文只存入忽略的本地证据目录。

原来的单条、batch 和一次性 Worker 控制脚本继续保留，作为回归和隔离对照。直接调用底层 Whisper 可执行文件不自动代表模型清单已核验，当前实测由外层验证脚本承担这一步。

## Swift 主进程客户端

`app/Sources/VoxInkCore/ResidentWorkerClient.swift` 提供 actor 客户端：启动等待 ready、单个识别请求、取消、关闭及显式重启。进程代次与每次操作标识分别隔离旧结果、旧取消和旧超时；畸形响应会关闭连接。取消会结束进程，重新启动才可继续识别。

客户端显式继承环境变量（或使用调用者提供的字典）。`voxink-worker-host` 默认丢弃子进程 stderr，也可用 `--worker-stderr /new/path` 独占创建 0600 诊断文件。CLI 本身输出完整转录 JSON，保存时应使用私人目录。

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta
python3 script/check_swift_host.py --host /tmp/voxink-app-xcode-beta/out/Products/Debug/voxink-worker-host --qwen-binary /tmp/voxink-qwen-xcode-beta/out/Products/Release/voxink-qwen-smoke --whisper-binary /tmp/voxink-whisper-smoke/out/Products/Release/voxink-whisper-smoke --output benchmark/results/swift-host-NEW
```

该脚本在启动前后校验模型文件，复核音频哈希，再让 Swift CLI 完成连续识别和进程回收。当前 host 为 Debug、模型进程为 Release，此联调用于行为验证，不作为性能基准。

Swift 客户端的任务取消、超时与重启已用真实子进程 fixture 测试；三个真实 ASR 候选的 Swift 联调覆盖连续识别与关闭。没有将 fixture 测试冒充为三个 ASR 引擎均完成 Swift 取消专项测试。产品菜单栏、录音闭环、签名 XPC、最小权限封装和长期压力测试仍需后续实现。
