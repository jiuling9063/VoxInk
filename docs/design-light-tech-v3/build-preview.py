"""Build a self-contained v3, preserving both earlier review versions."""
from pathlib import Path

root = Path(__file__).resolve().parent
html = (root.parent / 'design-light-tech-v2/index.html').read_text()

def replace(old, new):
    global html
    if old not in html:
        raise ValueError(f'Expected v2 marker not found: {old[:80]}')
    html = html.replace(old, new)

start = html.index('<div class="workbench">')
end = html.index('<div><div class="caption"><span>设置', start)
html = html[:start] + (root / 'main-window.html').read_text() + html[end:]
replace('雾光细化 02', '雾光细化 03')
replace('雾光细化 v2', '雾光细化 v3')
replace('雾光细化 · 更小的 HUD，更轻的玻璃，更有回应的光', '雾光细化 · 更有秩序的主窗口，更轻盈的语音 HUD')
replace('主窗口承载准备与回看，设置收纳低频操作。把视觉重心留给正在表达的内容。', '统一对齐，收紧分组。快捷键与录音操作放在一起，文字结果与后续操作放在一起。')
replace('紧凑尺寸约 304 × 64 pt', '轻量尺寸约 288 × 56 pt')
replace('id="glass-opacity" type="range" min="12" max="36" value="28"', 'id="glass-opacity" type="range" min="12" max="36" value="32"')
replace('id="glass-opacity-value" for="glass-opacity">28%', 'id="glass-opacity-value" for="glass-opacity">32%')
replace('20 pt 窗口圆角，19 pt HUD 圆角。主窗口增强细腻边缘光；HUD 默认 28% 透明度，保持文字清晰。', '20 pt 窗口圆角，17 pt HUD 圆角。HUD 默认 32% 透明度，减薄轮廓与投影；状态 13 pt、辅助文字 11 pt。')
replace('href="../design-light-tech-v1/index.html#hud-section">对比第一版', 'href="../design-light-tech-v2/index.html">对比第二版')
replace('</style>', '\n' + (root / 'refinement.css').read_text() + '\n</style>')
(root / 'index.html').write_text(html)
print(f'Built offline preview: {root / "index.html"}')
