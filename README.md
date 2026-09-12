# 语落 VoxInk

语落 VoxInk 是一个 macOS 原生语音输入工具：录音在本机处理，识别结果可复制或写入当前输入目标。

## 当前状态

项目进入邀请制试用准备阶段。0.1.0 试用包已完成 Developer ID 签名和 Apple 公证，并修复正式签名下的麦克风权限遗漏。模型权重不随仓库或 App 打包，首次使用需要下载；跨设备安装与日常稳定性仍待小范围试用验证。

安装步骤与已知限制见 [试用版说明](docs/试用版说明-0.1.0.md)，问题反馈使用 [试用反馈模板](docs/试用反馈模板.md)。旧开发文档记录历史阶段，不作为当前安装指南。

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
