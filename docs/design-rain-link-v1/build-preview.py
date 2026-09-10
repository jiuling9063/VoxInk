"""Independent rain-and-connection concept, retaining the approved v4 baseline."""
from pathlib import Path
import base64,re
root=Path(__file__).resolve().parent
html=(root.parent/'design-light-tech-v4/index.html').read_text()
def data(p): return 'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
def replace(old,new):
    global html
    assert old in html,old[:80]
    html=html.replace(old,new)
logo=data(root/'assets/logo-rain-link-v1.png')
html,n=re.subn(r"const LOGO_DATA = 'data:image/png;base64,[^']+';",lambda m:f"const LOGO_DATA = '{logo}';",html)
assert n==1
start=html.index('<div class="logo-comparison">');end=html.index('<div class="brand-row">',start)
approved=data(root.parent/'design-light-tech-v4/assets/logo-concept-v2.png')
html=html[:start]+'<div class="logo-comparison"><figure><img class="logo" src="'+approved+'" alt="已定稿科技版 Logo"><figcaption>轻盈科技 · 已定稿基准</figcaption></figure><figure><img class="logo" data-logo alt="雨滴与相连涟漪 Logo"><figcaption>雨落·相连 · 新意象对照稿</figcaption></figure></div>'+html[end:]
for old,new in {
 '冰青玻璃 04':'雨落·相连 01',
 '冰青玻璃 v4':'雨落·相连 v1',
 'VoxInk / Light technology':'VoxInk / Rain and connection',
 '声音轻轻落下，<br>想法自然成文。':'声音如雨落，<br>文字在彼端。',
 '更细腻的玻璃曲面，更清透的语音浮层。从图标到每次开口，都有同一抹冰青色的光。':'一滴雨，落在相连的水面。用雨蓝与青色的立体折射，表达声音落成文字、从这一端传向另一端。',
 '冰青玻璃 · Logo 与 HUD 的同一套材质语言':'独立意象对照稿 · 沿用语落 VoxInk 名称，保留已定稿科技版',
 '把 Logo 的冰青色、通透底板与细亮折射边带进 HUD。玻璃融入背景，文字保持清晰。':'从雨滴的青蓝折射，到 HUD 的水光边缘。保持相同尺寸和清晰字号，让声音与文字的传递有连续的反馈。',
 '从声音，到落笔。':'雨落成纹，两端相连。',
 'V 的两道曲面逐渐汇聚，末端收成一滴墨。用同一种青色贯穿图标、操作与语音反馈。':'以立体雨滴为主体，两处相连的涟漪象征本机与另一台电脑。连接融入水纹之中，不额外叠加设备或箭头。',
 'Logo 视觉方案已确认。保留 V 形曲面与墨滴，正式资产将以这版为基准制作；单色符号和菜单栏模板仍需补齐。':'新意象尚待确认。雨滴直接表达雨落，双水纹含蓄表达两端连接；小尺寸时连接细节可能弱化，后续还需简化成单色符号。',
 '第二轮冰青玻璃 Logo':'雨滴与相连涟漪 Logo',
 '冰蓝玻璃 V 形声波与墨滴 Logo 概念':'雨蓝立体水滴与双涟漪 Logo 概念',
 'href="../design-light-tech-v3/index.html">对比第三版':'href="../design-light-tech-v4/index.html">对比已定稿科技版',
}.items(): replace(old,new)
replace('<main class="wrap">','<main class="wrap"><p style="padding-top:18px;font-size:12px;color:var(--muted)">雨落·相连 · 独立对照稿　<a class="version-link" href="../design-light-tech-v4/index.html" target="_blank" rel="noopener">打开已定稿科技版</a></p>')
(root/'index.html').write_text(html)
print('Built:',root/'index.html')
