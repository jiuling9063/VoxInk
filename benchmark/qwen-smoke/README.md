# Qwen3-ASR 最小冒烟 CLI

该目录用于验证 Qwen3-ASR 0.6B MLX 4-bit 的已缓存模型、加载和单条 WAV 转录，不包含 App、录音、OpenCC 或正式 benchmark。

2026-09-08：入口改为先校验缓存，再加载，再复核。缺少缓存、文件大小或 SHA-256 不符时拒绝加载；不再用未核验的模型直接转录。

固定项：

- speech-swift：`d603472b11c21f5fb6492e9448a04ee669d0bf64`
- mlx-swift：`0.31.3`
- 模型：`aufklarer/Qwen3-ASR-0.6B-MLX-4bit`
- 固定模型 revision：`bc441bd1e4295c1f42d9879f056049a925b6e013`
- 语言提示：`zh`
- 输入采样率：16kHz（锁定 Qwen3ASR 源码的默认值）；音频转换发生在转录计时之前，本工具的时延不是完整 Adapter 时延。

## 构建与单元测试

```bash
swift test --package-path benchmark/qwen-smoke
```

只检查清单逻辑、不依赖 MLX 或 Swift Testing 插件：

```bash
bash script/check_model_contract.sh
```

此检查编译真实的 Core 源码并用临时文件验证身份、大小、哈希和拒绝行为，不证明模型加载或识别成功。

## 只加载并校验已有模型

先将清单固定 revision 的全部文件准备到上游缓存位置。指定 `QWEN3_CACHE_DIR` 时，新缓存位置为其下的 `qwen3-speech/models/aufklarer/Qwen3-ASR-0.6B-MLX-4bit/`；已有旧式缓存时上游优先选择旧目录。以 `HuggingFaceDownloader.getCacheDirectory` 的实际返回值为准。

当前锁定上游没有公开的 revision / 本地目录加载参数：本 CLI 不负责首次下载，`--prepare-only` 也要求已有完整缓存。上游仍可能因自身缓存元数据缺失而联网刷新；加载后复核不符则拒绝产出转录。因此尚不能声明离线加载验收通过。完整 Xcode/Metal 和固定模型缓存就绪后，必须验证此限制或替换加载入口。

```bash
QWEN3_CACHE_DIR="$HOME/Library/Caches/VoxInkBenchmark" \
swift run --package-path benchmark/qwen-smoke -c release voxink-qwen-smoke \
  --prepare-only --manifest benchmark/model-manifest.json
```

成功状态为 `model_loaded_manifest_verified`，输出 `model_revision`。加载前后均逐文件核对大小与 SHA-256；校验耗时不计入 `load_ms`，该字段仍可能包含上游缓存刷新时间，不能当作纯离线加载基准。

## 单条 WAV 转录

```bash
QWEN3_CACHE_DIR="$HOME/Library/Caches/VoxInkBenchmark" \
swift run --package-path benchmark/qwen-smoke -c release voxink-qwen-smoke \
  --audio /absolute/path/to/sample.wav \
  --sample-id S0001 \
  --device-profile m5-16gb-2026-09-08 \
  --manifest benchmark/model-manifest.json
```

成功路径标准输出一行 JSON；进度与错误写入标准错误。`raw_text` 是原始识别结果，不做简繁转换、词典或润色。未指定设备时标记 `unverified-device`，不能归入正式设备结果。

本工具每次启动只转录一次，属于冷转录冒烟，不提供热加载 P50/P95。异常目前写 stderr 并以非零状态退出；正式 Adapter 仍需补齐失败 JSONL、重复运行、音频哈希及分段计时，不能将本工具输出直接作为正式基准合同已完成的证据。


## 本机验证（2026-09-08）

Xcode 位于 `/Applications/Xcode-beta.app`（27.0 / 27A5252f），Metal Toolchain 已补齐。下面命令已完成 Debug 构建、4 项 Swift 测试和真实单条音频转录：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path benchmark/qwen-smoke --scratch-path /tmp/voxink-qwen-xcode-beta --disable-automatic-resolution

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
QWEN3_CACHE_DIR="$HOME/Library/Caches/VoxInkBenchmark" \
swift run --skip-build --package-path benchmark/qwen-smoke --scratch-path /tmp/voxink-qwen-xcode-beta \
  voxink-qwen-smoke --audio benchmark/corpus/audio/SMOKE-001.wav \
  --sample-id SMOKE-001 --device-profile m5-16gb-xcode27-debug-20260908 \
  --manifest benchmark/model-manifest.json
```

首次运行暴露上游诊断污染 stdout，现由 `JSONOutput` 在 CLI 入口将诊断转至 stderr，仅通过保存的原 stdout 写合同 JSON。输出隔离回归检查：`bash script/check_json_output.sh`。在 Xcode Beta 环境执行脚本时同样设置 `DEVELOPER_DIR`。

本次不是 Release 或热加载正式基准；完整结果位于 Git 忽略的 `benchmark/results/`，准确率仍待人工参考文本核对。
# 热词上下文实验状态（2026-09-09）

当前热词上下文未通过静音/噪声负样例门槛，**未接入产品**。仅批量基准模式可显式使用 `--experimental-hotwords`，计划条目可增加 `hotwords` 字符串数组；最多 32 条及 1024 UTF-8 字节，固定模型分词器预算 256 token。resident 模式拒绝该开关。空词表不创建上下文。

复现脚本：`script/check_hotword_context.py`；详细命令、噪声误识别与限制见 [ASR 热词提示对照](../../docs/ASR热词提示对照-2026-09-09.md)。实验完成不等于质量门通过，应读取回执 `negative_no_text_gate_passed`。
