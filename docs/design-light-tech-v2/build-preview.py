"""Build the offline v2 preview from the preserved v1 and focused refinements."""
from pathlib import Path

root = Path(__file__).resolve().parent
html = (root.parent / 'design-light-tech-v1/index.html').read_text()

def replace(old, new):
    global html
    if old not in html:
        raise ValueError(f'Expected v1 marker not found: {old[:80]}')
    html = html.replace(old, new)

replace('设计提案 01', '雾光细化 02')
replace('轻盈科技 v1', '雾光细化 v2')
replace('视觉方向初稿 · 所有文字和状态均为演示数据', '雾光细化 · 更小的 HUD，更轻的玻璃，更有回应的光')
replace('轻磨砂 + 克制青色光感', '细腻磨砂 + 通透边缘光')
replace('一条深色玻璃浮层，让状态、声波与取消入口聚在一起。成功短暂停留，失败保留恢复操作。', '更小的一枚玻璃浮层，让光跟随声波轻轻起伏。内容清晰，边缘通透，表达时不打扰。')
replace('<div class="hud-stage">', '<div class="hud-stage" id="hud-stage" data-backdrop="paper">')
replace('设计尺寸约 370 × 80 pt', '紧凑尺寸约 304 × 64 pt')
replace('录音显示动态声波，识别转为柔和呼吸。减少动态时保留静态状态和文字。', '示例声量同时影响声波与边缘光。识别缓慢呼吸，完成轻亮收拢；减少动态时保持静态。')
replace('22 pt 大圆角，10 pt 控件圆角。主窗口保留实底阅读区；HUD 使用高不透明度深色玻璃。', '20 pt 窗口圆角，19 pt HUD 圆角。主窗口增强细腻边缘光；HUD 默认 28% 透明度，保持文字清晰。')
replace('出现 / 消失 180 ms，完成提示约 1.5 s。颜色配合文案传达状态；支持深色和减少动态预览。', '出现 / 消失 180 ms，完成提示约 1.5 s。光效随状态回应，支持悬停光感及减少动态预览。')
controls = '''<div class="light-controls" aria-label="HUD 光感调节">
<label for="voice-level">示例声量 <input id="voice-level" type="range" min="0" max="100" value="65"><output id="voice-level-value" for="voice-level">65%</output></label>
<label for="glass-opacity">透明度 <input id="glass-opacity" type="range" min="12" max="36" value="28"><output id="glass-opacity-value" for="glass-opacity">28%</output></label>
<label for="backdrop">桌面背景 <select id="backdrop"><option value="paper">浅色</option><option value="blue">青色</option><option value="night">深色</option></select></label>
</div><p class="helper">移动鼠标经过 HUD，可看边缘光回应；调节示例声量，可比较光效强弱。声量为模拟值。</p>'''
replace('<div class="hud-controls">', controls + '\n<div class="hud-controls">')
replace('<span>本页是独立视觉提案，尚未应用到可运行 App。</span>', '<span>独立视觉提案 · 尚未应用到 App · <a class="version-link" href="../design-light-tech-v1/index.html#hud-section">对比第一版</a></span>')
replace('</style>', '\n' + (root / 'refinement.css').read_text() + '\n</style>')
replace('</script>', '\n' + (root / 'refinement.js').read_text() + '\n</script>')
(root / 'index.html').write_text(html)
print(f'Built offline preview: {root / "index.html"}')
