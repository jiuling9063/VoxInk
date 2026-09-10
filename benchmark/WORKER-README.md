# 阶段 0 独立进程 Worker 验证

`script/asr_worker.py` 是控制进程；每次识别启动一个独立模型子进程。三个候选均复用已锁定版本的 Release 入口。它验证模型加载、JSON 序列化、进程级取消、断连和重启，不是产品常驻 XPC Worker。

## 命令

先按 BATCH-README 构建两个 Release 二进制，然后从仓库根目录运行：

```bash
python3 -m unittest discover -s script/tests
python3 script/check_asr_worker_live.py --qwen-binary /tmp/voxink-qwen-xcode-beta/out/Products/Release/voxink-qwen-smoke --whisper-binary /tmp/voxink-whisper-smoke/out/Products/Release/voxink-whisper-smoke --output benchmark/results/worker-NEW
```

必须使用新输出目录。原文和进程日志保留在被 Git 忽略的 results 下，默认权限仅当前用户可读。

手动启动控制入口：

```bash
python3 script/asr_worker.py --candidate qwen3-asr-0.6b-mlx-4bit --binary /tmp/voxink-qwen-xcode-beta/out/Products/Release/voxink-qwen-smoke --log-dir benchmark/results/manual-worker-NEW
```

stdin 每行一个 JSON 对象：

```json
{"type":"transcribe","request_id":"r1","sample_id":"SMOKE-001"}
{"type":"cancel","request_id":"r1"}
{"type":"shutdown"}
```

`control_ready` 只表示控制层可接收请求，**不表示模型已加载**。`started` 表示子进程创建；`transcribing` 来自模型入口即将调用推理函数时的诊断标记。只有 `result` 才表示本次识别成功且缓存复核通过。

单次只接受一个活动请求，忙碌时返回 busy，同一控制会话不允许复用已接受的 request_id。取消先终止整个进程组，等待退出，再返回 cancelled；被取消请求不再发布 result。模型进程异常返回 failed，之后可以发送新 request_id 重新加载。读取 stdin EOF 或 shutdown 后清理活动模型进程。默认每次识别超时 600 秒。

## 网络与模型边界

每个模型命令均由 `/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)'` 启动，子进程继承禁止网络策略。实测脚本用“无沙盒可绑定本地端口、沙盒内被拒绝”作为策略生效对照。不改变系统 Wi-Fi、代理或防火墙。

只证明这些本地缓存及本机条件下，三个候选能在网络被禁止时加载和转录。上游源代码中的联网回退仍存在；缓存缺失时不会因此自动成为可下载的离线实现。当前允许其他系统能力，Core ML / ANE 系统服务仍工作；这不是产品最小权限沙盒配置。

模型和分词器在开始前、成功结果发布前校验；原始音频从已授权 corpus 样本 ID 解析，检查 SHA-256。控制协议不允许传入任意音频路径。取消使用进程级终止，清空模型内存，下次识别重新加载，不是引擎内部协作式取消。

## 未完成的产品验证

- 常驻模型、Swift/XPC 协议、App 主进程连接和 UI 状态。
- 控制 Worker 自身被 SIGKILL 后的孤儿进程回收；本次父端断连测试覆盖 stdin EOF，不能泛化为所有异常退出。
- 资源权限收紧、安装包签名、100 次连续稳定性、正式准确率和性能验收。
- 取消与结果完成同时发生时，以控制层处理顺序决定最终事件；没有宣布设备上的计算可瞬时停止。
