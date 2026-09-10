# 同进程 Release 开发基准

在项目根目录执行。先按两个 smoke README 准备固定版本模型和分词器缓存。

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --package-path benchmark/qwen-smoke --scratch-path /tmp/voxink-qwen-xcode-beta --disable-automatic-resolution
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --package-path benchmark/whisper-smoke --scratch-path /tmp/voxink-whisper-smoke --disable-automatic-resolution
python3 -m unittest discover -s script/tests
python3 script/run_asr_batch.py --qwen-binary /tmp/voxink-qwen-xcode-beta/out/Products/Release/voxink-qwen-smoke --whisper-binary /tmp/voxink-whisper-smoke/out/Products/Release/voxink-whisper-smoke --output benchmark/results/release-batch-NEW
```

每次指定未存在的输出目录，不覆盖历史证据。脚本不下载模型，也不上传音频。所有输出默认权限仅当前用户可读。

同一个 seed（默认 20260908）产生同一个请求计划，三个候选复用同一计划：

1. 一个新进程加载模型，随机抽一条做首次转录（cold）。
2. 同一条再做一次 warmup，不计分。
3. 同一进程中进行 3 轮 warm，每轮将所有录音打乱。

这只测一条 cold，不是全部语料的冷轮分布。模型按固定顺序串行运行。系统编译缓存不清理；不同候选开始时缓存和温度可能不同。热测只有开发小样，不用于正式选型。

音频读取在转录计时外；输入必须是 16kHz 单声道 16-bit WAV，重采样为 0。每条请求返回后才能发出下一条，模型只加载一次。load_ms 在每条结果重复记录同一次加载，不应相加。RSS 为整个进程累积峰值，不能解释为单条音频增量内存。

- `plan.json`：音频哈希、样本 ID、请求 ID、阶段、轮次和顺序。
- `metadata.json`：seed、设备、电源、二进制 SHA-256、模型清单哈希；温度未测、其他后台负载未控制会明确记录。
- `*.raw.jsonl`：Swift 原始输出；`*.stderr.log` 为私人诊断日志。
- `*.jsonl`：按完整计划对齐的结果，缺失、重复 ID、非法响应、进程异常及校验失败不能静默通过。批次异常时保留已产生文字但整批标记无效。cold/warmup 未成功时热轮不计有效分数。
- `summary.json`：只对成功 warm 计算 nearest-rank P50/P95，失败另报；按时长分组及样本报告 min/max，重复轮不计为独立样本。

二进制参数应来自上述 Release 构建；脚本记录二进制哈希，但不具备从任意二进制反向证明构建配置的能力。严格离线、Worker 取消/重启、100 条正式验收和准确率评测仍是独立任务。
