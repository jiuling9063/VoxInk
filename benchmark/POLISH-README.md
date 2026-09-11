# 本地润色实验

## 本机 App 预览接入

完成下载校验后执行 `python3 script/setup_polish_runtime.py`，将 Python 虚拟环境和 Worker 安装到 `~/Library/Application Support/VoxInk/Polish/`，生成 `runtime.json`。App 读取该配置，通过独立进程调用模型；操作系统沙箱禁止 Worker 网络访问。模型仍引用本仓库的 `benchmark/models/polish/`，移动仓库后需重新运行安装脚本。这是开发接入，不是完整的终端用户模型下载管理器。

设置中开启轻度润色预览，识别后手动点击预览。最多 2000 字、30 秒；取消会结束进程，结果不覆盖原文或自动写入。进程按次启动/退出，因此实际等待包括文件校验和加载，不能沿用模型常驻热测延迟。启发式保真检查通过后也须人工核对。

独立 Python/MLX 实验，不是 App 的运行依赖，也尚未接入自动写入。
测试只使用脚本内的人工文本，模型按固定 revision 下载到 Git 忽略的 `benchmark/models/polish/`。

```sh
uv venv /tmp/voxink-polish-venv --python 3.12
uv pip install --python /tmp/voxink-polish-venv/bin/python -r benchmark/polish-requirements.txt
/tmp/voxink-polish-venv/bin/python script/check_polish_model.py --download
/tmp/voxink-polish-venv/bin/python script/check_polish_model.py
```

如网络需要代理，使用本机有效的 HTTP_PROXY/HTTPS_PROXY 环境变量；不修改系统设置。下载验证 LFS SHA-256 和普通文件 Git blob SHA-1，随后保存本地 SHA-256 清单；推理前复核清单。推理设置 HF_HUB_OFFLINE，不代表操作系统层面禁网验收。

初轮结果在 `benchmark/results/polish-4b.json`，当前隔离与校验版保存至 `benchmark/results/polish-4b-guarded.json`，不会覆盖初轮证据。首组包含首次推理开销，后续组复用同一模型；加载耗时不包括下载和哈希验证。peak_mlx_bytes 仅代表 MLX 峰值内存，不代表总进程或 ASR 同时运行的内存。

`polish_guard.py` 将原文编码为 JSON 数据，要求模型输出唯一 text 字段；拒绝格式异常、重复字段、空输出、截断、数字/英文标记/网址/代码数量变化、部分否定与不确定词变化及相似度低于 0.72 的结果。拒绝后返回原文。它是保守的启发式检查，不是语义验证器：中文姓名、同义变换、实体关系变化不能全面识别，也可能拦截合理编辑。不能据此开启自动写入。

运行保护规则测试：`python3 -m unittest discover -s script/tests -p test_polish_guard.py`。

missing_protected 仅为指定字符串的保守精确匹配检查；措辞变化可能误报，字符串存在也不证明语义正确。所有输出仍需人工核对。输出限制 256 token，正式接入需要取消、超时、截断拒绝、受保护片段检查和模型卸载机制。
