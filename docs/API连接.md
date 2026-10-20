# API 连接（0.1.15）

语音识别和文字润色可以独立选择本地模型或 API 连接。默认仍为本地识别、关闭润色；升级不会自动上传音频或文字。

## 添加与使用

1. 在「转录引擎」或「润色模型」直接点击「添加服务商」。偏好设置中的「模型服务」可集中管理两种连接。
2. 选择服务商，界面自动填写官方接口和适用的模型示例；模型也可以自行修改。粘贴 API Key，检查名称、用途和地址后保存。每个连接对应一个用途和模型；同一家服务用于两项功能时，分别添加两个连接。
3. Base URL 包含服务商要求的 API 前缀，例如 `https://你的服务域名/v1`，也支持完整接口地址。语落不会擅自添加 `/v1`。
4. 保存后测试。润色测试发送固定示例文字；转写测试由你选择不超过 60 秒的音频。测试也可能产生服务商费用，不会自动写入其他应用。
5. 在对应页面的「处理服务」选择该连接。使用云端润色时还需开启「自动润色后写入」。

选择 API 转写后不要求下载本地识别模型。切换回「本地模型」时会重新准备本地模型。修改、删除或切换连接只能在当前任务结束后进行；删除正在选择的连接前，先切换服务。

## 服务商预设

预设按用途筛选，保留自定义接口。以下地址于 2026-10-20 按官方文档核对；这是接口配置预设，不代表所有账户、模型均已实测可用。需要使用各服务商自己的密钥和已开通的模型，地区或专属套餐地址可自行修改。

| 服务商 / 官方文档 | 基础接口地址 | 可选用途 |
| --- | --- | --- |
| [硅基流动](https://docs.siliconflow.cn/docs/api/chat-completions-post) | `https://api.siliconflow.cn/v1` | 润色、文件转写 |
| [OpenAI](https://developers.openai.com/api/docs) | `https://api.openai.com/v1` | 润色、文件转写 |
| [DeepSeek](https://api-docs.deepseek.com) | `https://api.deepseek.com` | 润色 |
| [阿里云百炼](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 润色 |
| [火山方舟](https://docs.volcengine.com/docs/ark/quick-start?lang=zh) | `https://ark.cn-beijing.volces.com/api/v3` | 润色 |
| [智谱](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction) | `https://open.bigmodel.cn/api/paas/v4` | 润色 |
| [Kimi](https://platform.kimi.com/docs/get-api-key) | `https://api.moonshot.cn/v1` | 润色 |
| [Google Gemini](https://ai.google.dev/gemini-api/docs/openai) | `https://generativelanguage.googleapis.com/v1beta/openai` | 润色 |
| [Groq](https://console.groq.com/docs/speech-to-text) | `https://api.groq.com/openai/v1` | 润色、文件转写 |
| [OpenRouter](https://openrouter.ai/docs/quickstart) | `https://openrouter.ai/api/v1` | 润色 |

选择预设不会自动更改当前使用的连接，也不会自动发请求。已有连接保留原地址、模型、参数和钥匙串记录；切换预设时清空尚未保存的密钥，更换地址后要求填写对应密钥。选择「自定义接口」可保留现有字段继续编辑。

所有输入项使用完整边框与焦点提示。API Key 支持系统粘贴和「粘贴密钥」按钮，保持掩码显示；编辑时留空保留已有密钥。超时、额外 JSON 参数和清除密钥放在「高级设置」。

## 当前支持的协议

| 用途 | 协议和要求 |
| --- | --- |
| 润色 | OpenAI Chat Completions：向 `chat/completions` 发送 JSON `model`、`messages`、`stream: false`；读取 `choices[0].message.content`，要求 `finish_reason: stop` |
| 文件转写 | OpenAI Audio Transcriptions：向 `audio/transcriptions` 发送 multipart 的 `file`、`model`、`response_format: json`；读取 JSON `text` |
| 认证 | 可选 `Authorization: Bearer <API Key>`；无需认证的本机服务可不填 |

兼容文本协议不代表兼容音频协议。专用签名、专有语音 JSON 格式和实时 WebSocket 协议需要另加适配器，本版尚不支持。音频沿用现有上限：单次最长 60 秒，上传前统一为单声道 16 kHz WAV，并检测有效语音。自动语言不发送 `language`；粤语在通用 ISO-639-1 参数中使用 `zh`，具体方言能力取决于服务商。

语落支持 HTTPS；本机 `localhost`、`127.0.0.1`、`::1` 可使用 HTTP。远程自建服务请提供 HTTPS。接口重定向不会被自动跟随，请填写最终地址。

润色连接可以填写额外 JSON 请求参数，以适应不同服务商。是否关闭思考、输出上限及参数名称应查服务商文档；不要填写密钥。不能覆盖模型、消息、流式、工具或认证字段。第一版使用手动模型 ID，不依赖服务商是否提供模型列表接口。

协议参考：[Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[Audio Transcriptions](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create)。

## 等待、失败与原文保护

- 每个连接可设置 1–120 秒总等待上限，默认 30 秒。请求不自动重试，也不自动切换服务商。
- 润色整理标点、中文独立停顿词和相邻重复句段。数字、代码、网址、路径、引用文字、否定与不确定表达受到保守检查；不支持的改写、截断或失败均保留转写原文。这是启发式检查，不是语义正确性的保证。
- 本地润色继续使用现有本地模型与校验流程。词典、字形处理、原始转写查看和写入安全检查对 API 模式继续生效。
- 转写失败显示认证、限流、超时或协议错误，沿用未完成录音恢复流程。可检查连接后重试，或主动选择本地模式。
- Esc 取消网络请求与本次写入，晚到结果不能进入历史或自动粘贴。

## 数据与密钥

密钥仅保存在 macOS 钥匙串，不写入偏好文件、日志或仓库。编辑时留空保留已有密钥；更改服务地址时需要重新填写密钥或明确清除，避免把原密钥误发给新地址。

启用 API 转写会发送音频；启用 API 润色会发送经本机词典和字形处理后的文字。本机录音清理不代表服务商端删除；服务商的数据保留规则由其政策决定。服务商错误正文不直接显示，避免其回显输入或认证信息。

## 验证命令

在本项目当前 macOS 开发环境中：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test \
  --package-path app --scratch-path /tmp/voxink-app-xcode-beta
python3 script/check_localizations.py
```

自动测试不需要真实 API Key，不会访问付费模型。接入实际服务商后，仍需用自己的连接执行一次测试，核对该模型的协议兼容性、费用和端到端速度。
