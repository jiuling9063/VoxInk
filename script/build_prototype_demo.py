#!/usr/bin/env python3
"""Build an offline gallery from reviewed, checker-exported PNG captures."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import struct


def build(directory: Path) -> None:
    annotations = json.loads((directory / "captures.json").read_text())
    items = []
    for capture in annotations:
        filename = capture["file"]
        if Path(filename).name != filename or not filename.endswith(".png"):
            raise ValueError("Capture must name one PNG directly inside assets")
        path = directory / "assets" / filename
        if path.is_symlink():
            raise ValueError("Capture must be a regular exported file")
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise ValueError("Invalid PNG header")
        width, height = struct.unpack(">II", data[16:24])
        metadata = json.loads(path.with_suffix(".json").read_text())
        if metadata["image"] != filename or metadata["simulation"] is not True:
            raise ValueError("Missing matching simulation metadata")
        if [width, height] != [metadata["width_pixels"], metadata["height_pixels"]]:
            raise ValueError("PNG dimensions differ from export receipt")
        items.append({**capture, "src": "assets/" + filename,
                      "metadata": metadata, "sha256": hashlib.sha256(data).hexdigest()})
    if not items:
        raise ValueError("At least one reviewed capture is required")
    payload = json.dumps(items, ensure_ascii=False).replace("<", "\\u003c")
    first = items[0]
    page = TEMPLATE.replace("__CAPTURES__", payload)
    page = page.replace("__COUNT__", str(len(items)))
    page = page.replace("__FIRST_SRC__", html.escape(first["src"], quote=True))
    page = page.replace("__FIRST_TITLE__", html.escape(first["title"]))
    page = page.replace("__FIRST_DESCRIPTION__", html.escape(first["description"]))
    page = page.replace("__FIRST_APPEARANCE__", html.escape(first["metadata"]["appearance"], quote=True))
    (directory / "index.html").write_text(page)
    (directory / "manifest.json").write_text(json.dumps({
        "date": "2026-09-09", "simulation": True, "captures": items,
        "status": "Partial visual demonstration; physical acceptance remains separate"
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"Built {directory / 'index.html'} with {len(items)} verified capture(s)")


TEMPLATE = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>语落 VoxInk · 原型演示</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#18304c;background:#f3f6fa;line-height:1.65}
*{box-sizing:border-box}body{margin:0}a{color:#175baf}button{font:inherit;cursor:pointer}button:disabled{cursor:default;opacity:.4}
header,main,footer{max-width:1180px;margin:auto;padding:30px 32px}header{display:flex;justify-content:space-between;gap:24px;align-items:center}
.brand{font-weight:700;font-size:20px}.badge{font-size:12px;background:#e5eefb;color:#245589;padding:6px 12px;border-radius:30px}
.intro{max-width:740px;margin:12px 0 30px}h1{font-size:clamp(28px,4vw,42px);letter-spacing:-1px;line-height:1.25;margin:10px 0 18px}p{margin:8px 0;color:#506176}
.eyebrow{font-size:12px;letter-spacing:2px;color:#3570aa;font-weight:600}.viewer{background:#fff;border:1px solid #dce3ed;border-radius:20px;overflow:hidden;box-shadow:0 15px 45px #2036510a}
.viewer-head{padding:20px 24px;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #e5eaf0;gap:12px}
h2{font-size:19px;margin:0}.counter{font-size:13px;color:#68788c}.stage{padding:24px;min-height:240px;background:#e9edf3;display:grid;place-items:center}
.stage img{display:block;max-width:100%;max-height:690px;height:auto;box-shadow:0 5px 24px #15264020;border-radius:8px;background:#ededed}.stage img[data-appearance=dark]{background:#303030}
.caption{padding:18px 24px;display:flex;gap:20px;align-items:start;justify-content:space-between}.caption p{margin:0;max-width:750px}.caption a{white-space:nowrap;font-size:14px}
.controls{display:flex;gap:8px}.controls button{border:1px solid #cad5e3;background:white;color:#264969;border-radius:8px;padding:5px 13px}
.thumbnails{display:flex;gap:10px;overflow:auto;margin:16px 0 34px;padding:2px}.thumbnails button{border:1px solid #d4deeb;background:#fff;border-radius:10px;padding:10px 15px;text-align:left;white-space:nowrap;color:#506176}.thumbnails button[aria-current=true]{border-color:#357bce;color:#145ca9;background:#edf5ff}
section.notes{display:grid;grid-template-columns:1fr 1fr;gap:24px}.note{background:white;border:1px solid #dce3ed;border-radius:14px;padding:24px}.note h2{font-size:17px;margin-bottom:12px}.note ul{padding-left:20px;margin:0;color:#506176}.note li{margin:7px 0}footer{font-size:12px;color:#68788c;border-top:1px solid #dce3ed;display:flex;justify-content:space-between;gap:20px}
:focus-visible{outline:3px solid #2a79cc;outline-offset:4px}@media(max-width:650px){header,main,footer{padding:20px}.stage{padding:12px}.caption{display:block}.caption a{display:inline-block;margin-top:12px}section.notes{grid-template-columns:1fr}.viewer-head{padding:16px}footer{display:block}}
</style></head><body>
<header><div class="brand">语落 <span style="font-weight:400;color:#61768e">VoxInk</span></div><div class="badge">开发预览 · 模拟演示</div></header>
<main><div class="intro"><div class="eyebrow">原生 macOS 原型 · 2026.09.09</div><h1>按住说话，松开写入。</h1><p>从首次准备，到录音、识别、写入与异常恢复，再查看快捷键设置和用户词典。这里使用真实组件和状态机，录音、识别与写入由模拟服务驱动。</p><p>已收录 <strong>__COUNT__ 张</strong>实际导出画面。点击下方画面名称，或按左右方向键浏览。图片不代表真实语音或远程输入已验收。</p></div>
<div class="viewer"><div class="viewer-head"><div><h2 id="title">__FIRST_TITLE__</h2><span id="counter" class="counter">1 / __COUNT__</span></div><div class="controls"><button id="previous" aria-label="上一张">←</button><button id="next" aria-label="下一张">→</button></div></div>
<div class="stage"><img id="capture" src="__FIRST_SRC__" alt="__FIRST_TITLE__" data-appearance="__FIRST_APPEARANCE__"></div><div class="caption"><p id="description">__FIRST_DESCRIPTION__</p><a id="original" href="__FIRST_SRC__" download>下载原始 PNG ↓</a></div></div>
<nav class="thumbnails" id="thumbnails" aria-label="演示画面"></nav>
<section class="notes"><div class="note"><h2>如何体验可运行原型</h2><ul><li>正式 App：先点选输入框，按住 ⌥ Space 说话，松开后识别并写入；Esc 取消。</li><li>窗口内试录或导入仅展示结果；快捷键录音才自动写入目标应用。</li><li>独立检查程序可切换状态、深浅色与尺寸；所有输入均为模拟数据。</li></ul></div>
<div class="note"><h2>仍待实机验收</h2><ul><li>当前构建实体快捷键、真实轻声与环境噪声。</li><li>完整键盘与 VoiceOver、多屏、睡眠及远程重连。</li><li>正式语料与延迟、剪贴板分类型重复测试、首次安装和签名分发。</li></ul></div></section>
</main><footer><span>本地静态页面 · 无外部字体、脚本或网络请求</span><span><a href="manifest.json">导出元数据与 SHA-256</a> · <a href="../完整原型验收清单.md">完整验收清单</a></span></footer>
<script>
const captures=__CAPTURES__;let current=0;
const $=id=>document.getElementById(id),nav=$('thumbnails');
captures.forEach((item,index)=>{const button=document.createElement('button');button.textContent=item.title;button.onclick=()=>show(index);nav.append(button)});
function show(index){current=(index+captures.length)%captures.length;const item=captures[current];$('title').textContent=item.title;$('counter').textContent=`${current+1} / ${captures.length}`;$('capture').src=item.src;$('capture').alt=item.title;$('capture').dataset.appearance=item.metadata.appearance;$('description').textContent=item.description;$('original').href=item.src;[...nav.children].forEach((button,i)=>button.setAttribute('aria-current',String(i===current)));$('previous').disabled=captures.length<2;$('next').disabled=captures.length<2}
$('previous').onclick=()=>show(current-1);$('next').onclick=()=>show(current+1);
document.addEventListener('keydown',event=>{if(event.target.matches('input,textarea,select'))return;if(event.key==='ArrowLeft'){event.preventDefault();show(current-1)}if(event.key==='ArrowRight'){event.preventDefault();show(current+1)}});show(0);
</script></body></html>'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    build(parser.parse_args().directory)
