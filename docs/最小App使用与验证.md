# 最小 App 使用与验证

当前是本机开发预览：原生窗口与菜单栏共用一个会话，支持录音、导入短音频、离线识别、结果展示和手动复制。Qwen 为临时接入候选，未完成正式模型选型；默认显示经过保护处理的简体结果，原始转录保留在内存。

## 构建与启动

在项目根目录执行：

```bash
./script/build_and_run.sh --verify
```

也可使用 Codex 的 Run 按钮。脚本默认使用 `/Applications/Xcode-beta.app/Contents/Developer`，可通过 `DEVELOPER_DIR` 覆盖，不修改系统开发目录。`dist/VoxInk.app` 是可双击的符号链接，真实产物放在当前用户 `Library/Caches/VoxInkDevelopment/<项目路径哈希>/VoxInk.app`，避免同步目录附加扩展属性导致签名失败。通过 Launch Services 启动；`--build-only` 仅构建打包。

构建包含 Debug App、Release Qwen Worker、SwiftPM 资源及固定模型清单。模型权重不嵌入 App，继续使用当前用户 `Library/Caches/VoxInkBenchmark` 下已验证的缓存。运行时 Worker 禁止网络并在加载前后校验模型；缓存缺失时显示错误，不自动下载。这不是可直接向其他用户分发的安装包，当前为本机 ad-hoc 签名。

## 使用

1. 打开后等待本地模型加载。
2. 点击“开始录音”才请求麦克风权限并开始采集。点击“停止并识别”结束，单次最长 60 秒。
3. 也可“导入音频…”选择不超过 60 秒的 WAV、M4A 等系统可解码音频；原文件保留，工作副本转换为单声道 16kHz、16-bit WAV。
4. 结果显示后点击“复制”，再自行粘贴到目标输入框。取消会保留上一条结果并停止当前任务。

临时音频目录限制为当前用户访问；识别结束或取消后删除本次工作副本。主进程退出使 Worker 输入端关闭。结果仅保存在内存，退出后不保留；不写入转录或音频日志。

## 验证命令

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta
bash -n script/build_and_run.sh
```

自动化测试不采集麦克风。真实麦克风授权、录音电平与 60 秒硬件停止需要交互验证。全局快捷键、悬浮录音反馈、简繁转换、自动粘贴事务和 UU 远程输入仍属于后续工作。

2026-09-09 更新：快捷键默认按住录音、松开识别并写入，可在主窗口切换为按两次模式。简体输出由本地 OpenCC 保证；模型简体提示因静音时回显而停用，完全无信号的音频直接提示重新录音。最新操作和验证边界见 [快捷键与文字写入原型](快捷键与文字写入原型.md)。
