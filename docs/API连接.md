# API 连接（0.1.22）

本页对应 0.1.22 的「识别与润色」界面。旧版用户升级后会保留已有服务与密钥。

语音识别和文字润色可以独立选择本地模型或 API 连接。默认仍为本地识别、关闭润色；升级不会自动上传音频或文字。

## 添加与使用

1. 打开侧栏「识别与润色」。语音识别和文字润色各有一个「处理方式」菜单。
2. 选择本地模型、已配置服务或“添加服务…”中的服务商。润色还可以选择「不润色」，已有配置仍会保留。
3. 首次配置普通服务商时粘贴 API Key；如另一项功能已使用同一家服务商，可勾选「复用已保存的密钥」。默认接口、名称和适用模型已填好。没有默认模型或选择自定义接口时，会直接显示必要的模型和地址输入项。
4. 点击「保存并使用」即可选用该服务。润色会同时启用，无需再找开关。保存本身不发送模型请求，配置失败不会改变原选择。
5. 需要验证时，点击连接编辑窗口或当前服务旁的「测试连接」或「选音频测试」。测试会发送固定示例文字或所选音频，可能产生费用，不会向其他应用写入。

点击「设置…」可修改当前服务。模型 ID 可直接编辑；「高级设置」提供名称、地址、超时、JSON 参数及删除入口；删除正在使用的连接前会提示切回本地模型。已保存的其他服务仍可从处理方式菜单选择。

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

选择尚未配置的服务商会打开设置表单，取消不会改变当前服务；保存后才选用。选择已配置服务会直接切换，但不会自动发请求。已有连接保留原地址、模型、参数和钥匙串记录。密钥复用仅允许同一家内置服务商的准确接口，修改为其他地址后需单独填写密钥。

模型 ID 平时显示为文字，移入或聚焦后显示浅底与边框，可直接输入。API Key 支持系统粘贴和「粘贴」按钮，保持掩码显示；编辑时留空保留已有密钥。超时、额外 JSON 参数和清除密钥放在「高级设置」。

## 获取模型

所有平台（包括自定义接口）的模型 ID 旁均提供“获取模型”，设置页与连接编辑窗口使用相同入口。点击后，按当前连接地址和密钥请求模型列表；无需认证的本机服务可以不填密钥。获取列表不发送音频或待润色文字。

- 通用接口请求同一地址前缀下的 `models`。硅基流动使用 `sub_type=speech-to-text/chat`，百炼使用原生模型目录的 `ASR/TG` 分类，OpenRouter 润色使用文本输入/输出筛选；支持分页的目录会继续获取后续页。
- 优先按官方能力、输入/输出类型区分转写和润色，过滤明确不相关的语音合成、向量、重排、图像和视频生成模型。未提供类型时，仅对明确的专用模型名称作辅助排除；无法确认用途的 ID 保留在“用途未标注”中，可搜索、展开和选择，不以预设模型白名单限制自定义部署。
- 获取列表本身不更换模型。设置页明确选择后保存；编辑窗口明确选择后更新草稿，点击“保存并使用”才保存。
- 失败、取消或关闭列表保留当前配置，可随时手动输入 ID。切换模型时，仅清除与旧模型绑定的默认参数；用户自行设置的参数保留。
- 获取使用当前连接已保存、刚输入或明确复用的密钥。改为其他服务地址时，不携带旧地址的已保存密钥。
- 服务端不提供兼容目录、认证不足或返回格式不兼容时，会显示错误并保留手动输入；内置平台提供官方文档入口。火山方舟普通 `/models` 已使用现有 API Key 实测获取成功；其另行提供的管理 API 使用独立 Access Key，本应用不会把推理密钥转发至管理接口。通用获取入口不代表每家服务端都提供兼容目录，也不代表返回模型的额度、调用权限、质量及推理协议均已实测兼容。

接口依据：[硅基流动 List Models](https://api-docs.siliconflow.cn/docs/api/models-get)、[百炼模型列表](https://help.aliyun.com/zh/model-studio/list-models)、[OpenRouter Models](https://openrouter.ai/docs/api/api-reference/models/get-models)、[火山方舟 ListFoundationModels](https://docs.volcengine.com/docs/ark/list-foundation-models-api?lang=zh)。

## 硅基流动与润色方式

新建硅基流动连接默认使用 `Qwen/Qwen3-ASR-1.7B` 识别、`Qwen/Qwen3.5-122B-A10B` 润色；润色关闭思考并使用 temperature=0.2。两项可复用同一个硅基流动账号的密钥，无需另申请千问官方账号。已有连接不会被默认值覆盖，可直接编辑模型 ID 或通过“获取模型”主动选择。

「原样整理」保留原句，只整理标点、停顿和少量重复；「自然润色」允许局部语序调整和口语整理，仍保留事实、数字、否定和不确定性。本地与云端共用这两个选项。未设置过模式的用户默认原样整理，已设置的模式升级后保持不变。保护规则是启发式检查，重要内容仍需核对。

## 当前支持的协议

| 用途 | 协议和要求 |
| --- | --- |
| 润色 | OpenAI Chat Completions：向 `chat/completions` 发送 JSON `model`、`messages`、`stream: false`；读取 `choices[0].message.content`，接受 `stop` 和 `length`，后者会提示结果可能被截断 |
| 文件转写 | OpenAI Audio Transcriptions：向 `audio/transcriptions` 发送 multipart 的 `file`、`model`、`response_format: json`；读取 JSON `text` |
| 认证 | 可选 `Authorization: Bearer <API Key>`；无需认证的本机服务可不填 |

兼容文本协议不代表兼容音频协议。专用签名、专有语音 JSON 格式和实时 WebSocket 协议需要另加适配器，本版尚不支持。音频沿用现有上限：单次最长 60 秒，上传前统一为单声道 16 kHz WAV，并检测有效语音。自动语言不发送 `language`；粤语在通用 ISO-639-1 参数中使用 `zh`，具体方言能力取决于服务商。

公网服务须使用 HTTPS。本机回环地址、`.local` 主机和 10/8、172.16/12、192.168/16、169.254/16 网段可使用 HTTP，仅在可信局域网内选用。接口重定向不会被自动跟随，请填写最终地址。

润色连接可以填写额外 JSON 请求参数，以适应不同服务商。是否关闭思考、输出上限及参数名称应查服务商文档；不要填写密钥。不能覆盖模型、消息、流式、工具或认证字段。所有服务商均支持手动输入模型 ID，并提供“获取模型”入口；列表可用性取决于服务端接口和认证权限。

协议参考：[Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[Audio Transcriptions](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create)。

## 等待、失败与原文保护

- 每个连接可设置 1–120 秒总等待上限，默认 30 秒。请求不自动重试，也不自动切换服务商。
- 润色整理标点、中文独立停顿词和相邻重复句段。数字、代码、网址、路径、引用文字、否定与不确定表达受到保守检查；长度受限时提示可能截断，仍会校验内容。校验失败时保留未润色文字。这是启发式检查，不是语义正确性的保证。
- 本地润色继续使用现有本地模型与校验流程。词典、字形处理、原始转写查看和写入安全检查对 API 模式继续生效。
- 转写失败显示认证、限流、超时或协议错误，沿用未完成录音恢复流程。可检查连接后重试，如已安装本地模型，也可点“改用本地识别重试”，本次重试不会更改默认连接。
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
