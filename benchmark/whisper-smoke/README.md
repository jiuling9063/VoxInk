# WhisperKit 本地冒烟

入口为仓库根目录的 `script/whisper_smoke.py`。Swift 可执行程序只负责推理；不要绕过 Python 校验入口作为版本已验证的结果。

锁定 WhisperKit 0.18.0 的源码 revision 和 swift-transformers 1.1.6；传递依赖见 Package.resolved。模型清单为 `benchmark/model-manifest.json`，补充分词器清单为 `benchmark/whisper-tokenizers.json`。分词器来自官方 OpenAI 模型仓库，在固定 revision URL 下载后计算 SHA-256。所有音频处理在本地。

## 构建和准备

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path benchmark/whisper-smoke --scratch-path /tmp/voxink-whisper-smoke --disable-automatic-resolution
# 下载使用机器已有代理；其他机器按需设置 https_proxy。
https_proxy=http://127.0.0.1:1082 python3 script/whisper_smoke.py whisperkit-large-v3-turbo --prepare
https_proxy=http://127.0.0.1:1082 python3 script/whisper_smoke.py whisperkit-medium --prepare
```

默认缓存：`~/Library/Caches/VoxInkBenchmark/whisper-models/<revision>` 和 `tokenizers/<revision>`。准备操作只在文件大小、SHA-256 均匹配后替换目标文件，保留可重试的已通过文件。

## 执行

本机 Xcode 构建产物路径如下；其他构建系统请用 `swift build --show-bin-path` 查询。

```bash
python3 script/whisper_smoke.py whisperkit-large-v3-turbo --binary /tmp/voxink-whisper-smoke/out/Products/Debug/voxink-whisper-smoke --sample SMOKE-001
python3 -m unittest discover -s script/tests
```

stdout 为一行 JSON，诊断进入 stderr。推理异常、超时、加载前后文件校验失败保留失败行并返回非零。参数错误及音频清单读取错误属于准备失败，返回非零且不生成推理行。

中文任务显式指定 `zh`、temperature 0，不自动识别语言。模型加载与音频读取分开计时，转录使用预读的 Float 音频数组。每次新进程仅一条音频，无进程内热身。RSS 是整个进程峰值，模型加载耗时包含本地分词器预解析，不包含 Python 哈希校验。

本地分词器先验证可解析，再调用公开加载接口；该上游接口仍存在异常时联网回退，尚未做断网验收。脚本也不防止校验与读取之间并发修改缓存。清单是受信任的项目配置，不是外部输入格式。Debug 数据不是正式基准，不报告 P50/P95 或模型选型结论。

## 已修复的接入陷阱

不要在 `loadModels()` 前设置 `model.tokenizer`。0.18.0 的 `loadTokenizerIfNeeded()` 在 tokenizer 非空时直接返回，同时跳过 `isModelMultilingual` 与模型变体初始化，中文参数不会正确进入提示词。当前通过 `WhisperKitConfig.tokenizerFolder` 提供缓存目录，走标准初始化，并检查多语言状态与中文 token。早期 `turbo-three-*` 和 `medium-three-*` 输出只保留为错误接入证据；有效对照使用 `*-verified-*`。
