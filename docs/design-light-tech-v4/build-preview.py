"""Embed the refined logo and optical HUD into an offline v4 review page."""
from pathlib import Path
import base64
import re

root = Path(__file__).resolve().parent
html = (root.parent / 'design-light-tech-v3/index.html').read_text()

def replace(old, new):
    global html
    if old not in html:
        raise ValueError(f'Expected v3 marker not found: {old[:80]}')
    html = html.replace(old, new)

def image_data(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()

new_logo = image_data(root / 'assets/logo-concept-v2.png')
old_logo = image_data(root.parent / 'design-light-tech-v1/assets/logo-concept-v1.png')
html, count = re.subn(r"const LOGO_DATA = 'data:image/png;base64,[^']+';", lambda m: f"const LOGO_DATA = '{new_logo}';", html)
assert count == 1
replace('雾光细化 03', '冰青玻璃 04')
replace('雾光细化 v3', '冰青玻璃 v4')
replace('完成轻亮收拢', '完成时四周柔光亮起一次')
replace('雾光细化 · 更有秩序的主窗口，更轻盈的语音 HUD', '冰青玻璃 · Logo 与 HUD 的同一套材质语言')
replace('用清透的冰蓝、柔和的磨砂材质，和一枚安静浮现的语音 HUD，让表达保持连贯。', '更细腻的玻璃曲面，更清透的语音浮层。从图标到每次开口，都有同一抹冰青色的光。')
replace('细腻磨砂 + 通透边缘光', '冰青透底 + 细亮折射边')
replace('更小的一枚玻璃浮层，让光跟随声波轻轻起伏。内容清晰，边缘通透，表达时不打扰。', '把 Logo 的冰青色、通透底板与细亮折射边带进 HUD。玻璃融入背景，文字保持清晰。')
replace('HUD 外观与状态演示', '材质对照 · Logo 与 HUD')
replace('<div class="hud" id="hud"', '<div class="material-pair"><figure class="pair-logo"><img class="logo" data-logo alt="第二轮冰青玻璃 Logo"><figcaption>同一套玻璃语言</figcaption></figure><span class="pair-divider" aria-hidden="true"></span><div class="hud" id="hud"')
replace('</div></div><div class="stage-bottom">', '</div></div></div><div class="stage-bottom">')
replace('id="glass-opacity" type="range" min="12" max="36" value="32"', 'id="glass-opacity" type="range" min="40" max="68" value="58"')
replace('id="glass-opacity-value" for="glass-opacity">32%', 'id="glass-opacity-value" for="glass-opacity">58%')
replace('<label for="glass-opacity">透明度 ', '<label for="glass-opacity">玻璃背景透明度 ')
replace('移动鼠标经过 HUD，可看边缘光回应；调节示例声量，可比较光效强弱。声量为模拟值。', '边缘通透，文字区域保留局部对比底层。切换桌面背景可比较浅色与深色玻璃；鼠标经过可看光感回应。声量为模拟值。')
replace('<div class="brand-row">', '<div class="logo-comparison"><figure><img class="logo" src="'+old_logo+'" alt="上一轮 Logo"><figcaption>上一轮 · 较厚的磨砂底板</figcaption></figure><figure><img class="logo" data-logo alt="本轮精修 Logo"><figcaption>本轮 · 更薄的折射边与墨滴</figcaption></figure></div><div class="brand-row">')
replace('这是第一版位图概念，先评估轮廓和材质。玻璃细节在小尺寸会弱化，正式资产需另做纯色符号和菜单栏模板。', 'Logo 视觉方案已确认。保留 V 形曲面与墨滴，正式资产将以这版为基准制作；单色符号和菜单栏模板仍需补齐。')
replace('20 pt 窗口圆角，17 pt HUD 圆角。HUD 默认 32% 透明度，减薄轮廓与投影；状态 13 pt、辅助文字 11 pt。', 'HUD 默认 58% 背景透明度，文字不透明；局部对比底层保障阅读。尺寸 288 × 56，状态 13 pt、辅助文字 11 pt。')
replace('<b>夜玻璃 / HUD</b>', '<b>深青 / 暗背景适配</b>')
replace('href="../design-light-tech-v2/index.html">对比第二版', 'href="../design-light-tech-v3/index.html">对比第三版')
replace('</style>', '\n' + (root / 'refinement.css').read_text() + '\n</style>')
(root / 'index.html').write_text(html)
print(f'Built offline preview: {root / "index.html"}')
