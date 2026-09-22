# 语落 VoxInk

语落 VoxInk 是一个 macOS 原生语音输入工具：录音在本机处理，识别结果可复制或写入当前输入目标。

## 当前状态

当前版本为 0.1.10（构建 12），新增自定义快捷键和首批多语言：简体/繁体/英/日/韩界面，普通话/粤语/英/日/韩语音及自动检测。中文输出可独立选择字形。保留通用远程工具、紧凑选择器、CSV 词库导入导出，以及内置 Python/MLX 润色运行组件。模型权重按需下载，无需手动配置环境。多语种准确率、另一台 Mac 首次安装和日常稳定性仍需试用验证。

安装步骤与已知限制见 [试用版说明](docs/试用版说明-0.1.10.md)，问题反馈使用 [试用反馈模板](docs/试用反馈模板.md)。旧开发文档记录历史阶段，不作为当前安装指南。

试用版建议使用 `.dmg` 安装盘：双击后将 VoxInk 拖到“应用程序”即可完成安装。安装包与 SHA-256 校验和见 [GitHub 预发布](https://github.com/jiuling9063/VoxInk/releases)。

多语言范围与验证边界见 [多语言方案](plans/language-support.md) 和 [验证记录](docs/多语言验证-2026-09-22.md)。

## 构建与验证

```bash
./script/build_and_run.sh --build-only
VOXINK_UI_LANGUAGE=zh-Hans DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta
```

更完整的使用说明与验证边界见 [`docs/最小App使用与验证.md`](docs/最小App使用与验证.md)。

## 目录

- `app/`：SwiftPM 原生 macOS 应用与 UI
- `benchmark/`：本地模型和识别实验工具
- `script/`：构建、检查和回归脚本
- `docs/`：设计、架构和验证记录

## 隐私

录音与识别默认在本机执行。模型缓存、临时音频、构建产物和本地工具状态不会提交到仓库。
