# -*- coding: utf-8 -*-
"""Build the V2 warm-writing review page from the verified interaction shell."""

from pathlib import Path
import base64
import re


root = Path(__file__).resolve().parent
source = (root.parent / "design-warm-writing-v1" / "index.html").read_text()
html = source


def image_data(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def replace(old: str, new: str) -> None:
    global html
    if old not in html:
        raise ValueError(f"Expected source marker not found: {old[:100]}")
    html = html.replace(old, new)


def replace_section(section_id: str, next_marker: str, replacement: str) -> None:
    global html
    start = html.index(f'<section class="section" id="{section_id}">')
    end = html.index(next_marker, start)
    html = html[:start] + replacement + html[end:]


logo_path = root / "assets" / "logo-rain-impression-v2.png"
logo = image_data(logo_path)
html, count = re.subn(
    r"const LOGO_DATA = 'data:image/png;base64,[^']+';",
    lambda _: f"const LOGO_DATA = '{logo}';",
    html,
)
if count != 1:
    raise ValueError(f"Expected one embedded logo assignment, found {count}")

html = re.sub(
    r"<title>.*?</title>",
    "<title>语落 VoxInk · 温润书写 V2 深化基线</title>\n<link rel=\"icon\" href=\"data:,\">",
    html,
    count=1,
)
replace(
    '<body data-theme="light" data-material="mist">',
    '<body data-theme="light" data-material="mist" data-version="warm-v2">',
)
replace(
    '<main class="wrap"><div class="direction-bar"><strong>温润书写 · 独立对比稿</strong><a href="../design-light-tech-v4/index.html" target="_blank" rel="noopener">打开轻盈科技定稿版，对照查看</a></div>',
    '<main class="wrap"><div class="direction-bar"><strong><span class="baseline-dot" aria-hidden="true"></span>温润书写 · V2 深化基线</strong><a href="../design-light-tech-v4/index.html" target="_blank" rel="noopener">保留查看轻盈科技 v4</a></div>',
)

hero_start = html.index('<section class="hero">')
hero_end = html.index('<section class="section" id="interface">', hero_start)
hero = '''<section class="hero"><div><div class="eyebrow">VoxInk / Warm writing · V2</div><h1>声音落下，<br>文字慢慢展开。</h1><p>以纸白、雾青与墨灰构成安静的书写环境。界面不模拟古典笔墨，而像一件现代、顺手、愿意长期放在桌面的文具。</p><div class="baseline-note"><b>深化基线</b><span>锁定 V2 Logo 的双形相连与柔软纸感；本轮只深化系统，不再改换符号。</span></div></div><div class="brand-art"><span class="hero-orbit" aria-hidden="true"></span><img class="logo" data-logo alt="温润书写 V2 基线 Logo"></div></section>'''
html = html[:hero_start] + hero + html[hero_end:]

replacements = {
    "温润书写 01": "温润书写 02",
    "温润书写 v1": "温润书写 v2",
    "轻一点，清楚一点。": "像纸一样安静，像工具一样清楚。",
    "统一对齐，收紧分组。快捷键与录音操作放在一起，文字结果与后续操作放在一起。": "操作层保持系统感，阅读层增加纸张般的呼吸。快捷键、录音、结果和恢复仍沿用已验证的分组。",
    "A · 暖白 / 默认": "A · 纸白 / 默认",
    "柔和底色 + 克制的杏色光": "纸白底色 + 雾青边缘",
    "B · 薄瓷": "B · 素纸",
    "更实的底色 + 更少的装饰": "更实的底色 + 最少装饰",
    "C · 灯下": "C · 暮光",
    "微暖边缘光 + 柔和投影": "更深层次 + 柔和漫反射",
    "让想法自然流动，让文字轻轻落下。": "把刚才的想法留下来，再慢慢整理成自己的文字。",
    "讓想法自然流動，讓文字輕輕落下。": "把剛才的想法留下來，再慢慢整理成自己的文字。",
    "在需要时，轻轻浮现。": "开口时出现，写完后退场。",
    "让 Logo 的暖白、浅杏色与柔和曲面延伸到 HUD。薄薄一层温润光感，保留清楚的状态文字。": "HUD 像一张悬浮的小纸签：纸白阅读区稳定承载状态，雾青只负责聆听与完成反馈。",
    "温润书写几何 Logo": "温润书写 V2 Logo",
    "同一抹温暖的光": "同一层纸白与雾青",
    '<option value="blue">暖色</option>': '<option value="blue">雾青</option>',
    "保留相同尺寸、字号、透明度和完成反馈，方便与科技版比较。切换背景或移动鼠标可查看材质；声量为模拟值。": "保持 288 × 56 pt 与 13 / 11 pt 字号。切换浅色、雾青、深色桌面，检查纸白阅读区是否始终稳定；声量为模拟值。",
    "示例声量同时影响声波与边缘光。识别缓慢呼吸，完成时四周柔光亮起一次；减少动态时保持静态。": "声量只改变短线节奏和底部雾青细线。识别采用低频呼吸，完成仅亮起一次；减少动态时改为静态边线。",
}
for old, new in replacements.items():
    replace(old, new)

brand = '''<section class="section" id="brand"><div class="section-head"><div><span class="number">03 / IDENTITY</span><h2>两片相连的纸，也是一滴落下的声音。</h2></div><p>V2 保留一大一小两片柔软曲面：可以读作声音与文字、这台电脑与另一台电脑，也可以只作为安静而有记忆点的符号。</p></div><div class="brand-baseline"><figure><div class="baseline-frame"><img class="logo" data-logo alt="V2 基线 Logo 大尺寸预览"><span>V2 BASELINE</span></div><figcaption>本轮锁定资产 · 不再换形</figcaption></figure><div class="brand-manifesto"><span class="eyebrow">语落 VoxInk</span><h3>不做古风书法，也不做冰冷设备感。</h3><p>形体保留纸张的柔软和内卷结构，配色从偏冷的科技蓝收敛为低饱和雾青。品牌表达落在“温和、可靠、长期陪伴书写”上。</p><dl><div><dt>大形</dt><dd>声音落下，形成输入的起点</dd></div><div><dt>小形</dt><dd>文字抵达另一端，保持连接</dd></div><div><dt>留白</dt><dd>给阅读和思考留出呼吸</dd></div></dl></div></div><div class="identity-lab"><div><span class="lab-label">APP ICON SCALE</span><div class="logo-sizes refined-sizes"><figure><img class="logo" data-logo width="128" height="128" alt="128 像素 Logo"><figcaption>128</figcaption></figure><figure><img class="logo" data-logo width="64" height="64" alt="64 像素 Logo"><figcaption>64</figcaption></figure><figure><img class="logo" data-logo width="32" height="32" alt="32 像素 Logo"><figcaption>32</figcaption></figure><figure><img class="logo" data-logo width="16" height="16" alt="16 像素 Logo"><figcaption>16</figcaption></figure></div><p>32 px 仍可区分一大一小；16 px 仅作识别风险检查，不等同于正式菜单栏资产。</p></div><div><span class="lab-label">MENU BAR CONCEPT</span><div class="menubar-sample"><span class="menu-rail"></span><span class="menu-glyph" aria-hidden="true"><i></i><i></i></span><b>语落</b><kbd>⌥ Space</kbd></div><p>菜单栏采用单色双形轮廓，不直接缩放彩色位图；正式模板图仍需矢量重绘。</p></div></div></section>
'''
replace_section("brand", '<section class="section" id="language">', brand)

language = '''<section class="section" id="language"><div class="section-head"><div><span class="number">04 / DESIGN LANGUAGE</span><h2>纸白承载内容，雾青回应动作。</h2></div><p>颜色、字体和材质均围绕长时间阅读与低干扰输入。操作控件保持系统无衬线，只有标题与识别结果使用本地宋体回退。</p></div><div class="swatches"><div class="swatch"><div style="background:#F2F0EA"></div><b>纸白 / 环境</b><span>#F2F0EA</span></div><div class="swatch"><div style="background:#547E86"></div><b>雾青 / 操作</b><span>#547E86</span></div><div class="swatch"><div style="background:#A9CDD0"></div><b>浅青 / 反馈</b><span>#A9CDD0</span></div><div class="swatch"><div style="background:#243037"></div><b>墨灰 / 正文</b><span>#243037</span></div><div class="swatch"><div style="background:#202729"></div><b>夜墨 / 深色</b><span>#202729</span></div></div><div class="specs"><div><h3>字体与阅读</h3><p>操作与设置使用系统无衬线；大标题、识别结果使用 Songti SC 回退。正文 13–15 pt，行高 1.75–1.9，结果区最大宽度 680 pt。</p></div><div><h3>间距与形状</h3><p>4 pt 基准，24 pt 主窗口内边距；控件圆角 8–12 pt，容器 18 pt。大窗口内容上限 920 pt，避免全屏横向铺满。</p></div><div><h3>状态与无障碍</h3><p>完成、取消、失败不只依赖颜色；键盘焦点使用 3 px 雾青外环。支持深色、减少动态与减少透明度。</p></div></div></section>
'''
replace_section("language", '<section class="section" id="compare">', language)

deepening = '''<section class="section" id="compare"><div class="section-head"><div><span class="number">05 / DEEPENING</span><h2>V2 的深化，不靠堆装饰。</h2></div><p>这轮把 Logo 的纸感翻译成界面规则，并把仍需原生验证的内容明确留在下一道门槛。</p></div><div class="principle-grid"><article><span>01</span><h3>阅读先于材质</h3><p>识别结果使用稳定纸白底和墨灰文字；透明度只出现在外围，不穿过正文。</p></article><article><span>02</span><h3>反馈短而准确</h3><p>录音有节奏，识别低频呼吸，完成只亮一次；“已发出粘贴”不暗示目标端已收到。</p></article><article><span>03</span><h3>恢复入口常在</h3><p>失败状态保留文字与重试、复制入口，不自动二次粘贴，也不以成功色掩盖不确定性。</p></article><article><span>04</span><h3>品牌克制出现</h3><p>Logo 只在 App、引导与材质说明中完整出现；日常窗口让内容和快捷键处于主位。</p></article></div><div class="next-gate"><b>下一门槛</b><span>先由用户评审本页的整体气质、主窗口与 HUD；确认后再制作原生 SwiftUI 主题和正式矢量图标资产。</span></div></section>'''
replace_section("compare", '<footer class="footer">', deepening)

html = re.sub(
    r'<footer class="footer">.*?</footer>',
    '<footer class="footer"><span>语落 VoxInk · 温润书写 v2 · 2026.09.10</span><span>独立深化稿 · 尚未应用到 App · <a class="version-link" href="../design-light-tech-v4/index.html">查看轻盈科技 v4</a></span></footer>',
    html,
    count=1,
    flags=re.S,
)
replace('</style>', '\n' + (root / "warm-v2.css").read_text() + '\n</style>')

(root / "index.html").write_text(html)
print(f"Built V2 warm-writing review: {root / 'index.html'}")
