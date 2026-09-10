"""Build a separate warm comparison; never rewrite the approved cool design."""
from pathlib import Path
import base64
import re

root = Path(__file__).resolve().parent
html = (root.parent / 'design-light-tech-v4/index.html').read_text()

def replace(old, new):
    global html
    if old not in html:
        raise ValueError(f'Expected source marker not found: {old[:90]}')
    html = html.replace(old, new)

def image_data(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()

warm_logo = image_data(root / 'assets/logo-warm-geometric-v2.png')
cool_logo = image_data(root.parent / 'design-light-tech-v4/assets/logo-concept-v2.png')
html, count = re.subn(r"const LOGO_DATA = 'data:image/png;base64,[^']+';", lambda m: f"const LOGO_DATA = '{warm_logo}';", html)
assert count == 1
start = html.index('<div class="logo-comparison">')
end = html.index('<div class="brand-row">', start)
html = html[:start] + '<div class="logo-comparison"><figure><img class="logo" src="'+cool_logo+'" alt="已定稿的轻盈科技 Logo"><figcaption>轻盈科技 · 已定稿基准</figcaption></figure><figure><img class="logo" data-logo alt="温润书写几何 Logo 对照稿"><figcaption>温润书写 · 新几何形式</figcaption></figure></div>' + html[end:]
replacements = {
 '语落 VoxInk · 轻盈科技 / 冰青玻璃 04':'语落 VoxInk · 温润书写 / 对比稿 01',
 '冰青玻璃 04':'温润书写 01',
 '冰青玻璃 v4':'温润书写 v1',
 'VoxInk / Light technology':'VoxInk / Warm writing',
 '声音轻轻落下，<br>想法自然成文。':'慢慢说，<br>想法自有形状。',
 '更细腻的玻璃曲面，更清透的语音浮层。从图标到每次开口，都有同一抹冰青色的光。':'暖白的界面，柔和的杏色，与恰到好处的留白。像一件顺手的文具，安静地承接每个想法。',
 '冰青玻璃 · Logo 与 HUD 的同一套材质语言':'独立对比稿 · 轻盈科技已定稿，本方案不替换原稿',
 'A · 雾光 / 推荐':'A · 暖白 / 默认',
 '冰青透底 + 细亮折射边':'柔和底色 + 克制的杏色光',
 'B · 清透':'B · 薄瓷',
 'C · 浮光':'C · 灯下',
 '增强 HUD 光感 + 更柔和的阴影':'微暖边缘光 + 柔和投影',
 '把 Logo 的冰青色、通透底板与细亮折射边带进 HUD。玻璃融入背景，文字保持清晰。':'让 Logo 的暖白、浅杏色与柔和曲面延伸到 HUD。薄薄一层温润光感，保留清楚的状态文字。',
 '同一套玻璃语言':'同一抹温暖的光',
 '玻璃背景透明度':'浮层背景透明度',
 '<option value="blue">青色</option>':'<option value="blue">暖色</option>',
 '边缘通透，文字区域保留局部对比底层。切换桌面背景可比较浅色与深色玻璃；鼠标经过可看光感回应。声量为模拟值。':'保留相同尺寸、字号、透明度和完成反馈，方便与科技版比较。切换背景或移动鼠标可查看材质；声量为模拟值。',
 '从声音，到落笔。':'柔和的形，温暖的光。',
 'V 的两道曲面逐渐汇聚，末端收成一滴墨。用同一种青色贯穿图标、操作与语音反馈。':'以一段连续的几何弧面，连接声音的回环与页面的展开。浅杏色主体配暖白底板，体现现代、亲近的气质。',
 'Logo 视觉方案已确认。保留 V 形曲面与墨滴，正式资产将以这版为基准制作；单色符号和菜单栏模板仍需补齐。':'根据反馈放弃笔墨造型，改用柔和几何弧面。此图仅为温润方案的新对照稿；已通过的科技版 Logo 保持原样。',
 '中文名与英文名使用系统无衬线字形，界面不另加载网络字体。':'操作区使用清晰的系统无衬线字体；标题与结果文字加入适度的宋体气质。不加载网络字体。',
 '系统字体 · 正文 13–15 pt，窗口标题 24 pt。4 pt 间距基准，内容宽度最多 740 pt；大窗口增加留白。':'操作区使用系统字体，标题与结果采用本地宋体回退。保持同一套 4 pt 间距基准与 740 pt 内容宽度。',
 'HUD 默认 58% 背景透明度，文字不透明；局部对比底层保障阅读。尺寸 288 × 56，状态 13 pt、辅助文字 11 pt。':'HUD 保持 58% 背景透明度、288 × 56 尺寸与 13 / 11 pt 字号。暖白底层、柔和琥珀边缘，与几何 Logo 呼应。',
 'href="../design-light-tech-v3/index.html">对比第三版':'href="../design-light-tech-v4/index.html">打开已定稿科技版',
 '第二轮冰青玻璃 Logo':'温润书写几何 Logo',
 '冰蓝玻璃 V 形声波与墨滴 Logo 概念':'浅杏色几何弧面 Logo 对照稿',
}
for old, new in replacements.items(): replace(old, new)
replace('<main class="wrap">', '<main class="wrap"><div class="direction-bar"><strong>温润书写 · 独立对比稿</strong><a href="../design-light-tech-v4/index.html" target="_blank" rel="noopener">打开轻盈科技定稿版，对照查看</a></div>')
# Replace only the visible palette, not the inherited reference styles.
start = html.index('<div class="swatches">')
end = html.index('<div class="specs">', start)
palette = [('f1ede5','暖白 / 环境'),('875036','栗棕 / 操作'),('d7ad6b','浅琥珀 / 反馈'),('302b26','深褐 / 正文'),('25221e','暖灰 / 深色')]
html = html[:start] + '<div class="swatches">' + ''.join(f'<div class="swatch"><div style="background:#{color}"></div><b>{name}</b><span>#{color.upper()}</span></div>' for color,name in palette) + '</div>' + html[end:]
comparison = '''<section class="section" id="compare"><div class="section-head"><div><span class="number">05 / COMPARISON</span><h2>两种气质，相同的输入体验。</h2></div><p>科技版保留为已定稿基准；温润版供比较，不代表已更换设计方向。</p></div><table class="contrast-table"><thead><tr><th scope="col">比较项</th><th scope="col">轻盈科技 · 已定稿</th><th scope="col">温润书写 · 对比稿</th></tr></thead><tbody><tr><th scope="row">整体氛围</th><td>冰青、清透、轻盈</td><td>暖白、柔和、亲近</td></tr><tr><th scope="row">Logo</th><td>V 形玻璃曲面与墨滴</td><td>浅杏色几何回环与折页</td></tr><tr><th scope="row">文字与材质</th><td>系统字体、细亮折射边</td><td>阅读区宋体、柔和的哑光底色</td></tr><tr><th scope="row">HUD</th><td>冰青波形与完成光效</td><td>琥珀波形与完成光效</td></tr><tr><th scope="row">功能与空间</th><td colspan="2">同一套流程；HUD 约 288 × 56，状态 13 / 11，背景透明度 58%，完成反馈 0.7 秒。</td></tr></tbody></table></section>'''
replace('<footer class="footer">', comparison + '<footer class="footer">')
replace('</style>', '\n' + (root / 'warm.css').read_text() + '\n</style>')
(root / 'index.html').write_text(html)
print(f'Built offline comparison: {root / "index.html"}')
