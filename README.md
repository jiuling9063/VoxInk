# 语落 VoxInk

语落 VoxInk 是一个 macOS 原生语音输入工具：录音在本机处理，识别结果可复制或写入当前输入目标。

## 当前状态

项目处于本机开发预览阶段。模型权重不随仓库提交，应用运行时使用当前用户缓存中的已验证模型；首次安装和跨设备分发仍需进一步整理。

## 构建与验证

```bash
./script/build_and_run.sh --build-only
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path app --scratch-path /tmp/voxink-app-xcode-beta
```

更完整的使用说明与验证边界见 [`docs/最小App使用与验证.md`](docs/最小App使用与验证.md)。

## 目录

- `app/`：SwiftPM 原生 macOS 应用与 UI
- `benchmark/`：本地模型和识别实验工具
- `script/`：构建、检查和回归脚本
- `docs/`：设计、架构和验证记录

## 隐私

录音与识别默认在本机执行。模型缓存、临时音频、构建产物和本地工具状态不会提交到仓库。
