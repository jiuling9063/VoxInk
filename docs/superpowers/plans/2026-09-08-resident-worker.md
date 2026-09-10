# 常驻 Worker 与 Swift 主进程接入

范围：阶段 0 进程协议验证，不包含 GUI、产品 XPC、默认模型选型或提交推送。

- [x] Task 1：共用请求协议，限制帧大小/队列，校验请求标识和路径，EOF 终止。
- [x] Task 2：Qwen / Whisper 增加 resident 模式，单次加载，ready 后处理多次请求，保留原单条和 batch 行为。
- [x] Task 3：app Swift 进程客户端，ready/结果超时、串行请求、取消、清理和显式重启；CLI 联调入口。
- [x] Task 4：测试、独立评审、三个候选禁网连续实测和证据报告。

协议：stdin JSONL {request_id,sample_id,audio_path}；stdout 初始 {type:ready,protocol_version:1,pid,load_ms}，请求完成 {request_id,result,error_code}。诊断到 stderr。退出视为连接失效，取消采用结束 worker 并重新加载；不宣称引擎协作式取消或签名 XPC 就绪。

验证：纯协议测试、真实子进程 fixture、三个真实模型单 PID 连续识别、EOF 退出；主进程采用代次隔离，旧连接结果不能完成新请求。对每个真实模型测试前后复核固定缓存与音频哈希。
