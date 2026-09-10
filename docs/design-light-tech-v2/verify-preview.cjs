// Static structure and simulated DOM checks; this does not render a browser.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(`${__dirname}/index.html`, 'utf8');
const nodes = [];
class Element {
  constructor(attrs = {}) {
    this.attrs = attrs; this.id = attrs.id; this.dataset = {};
    for (const [key, value] of Object.entries(attrs)) if (key.startsWith('data-')) this.dataset[key.slice(5)] = value;
    this.hidden = 'hidden' in attrs; this.checked = 'checked' in attrs;
    this.value = attrs.value || ''; this.children = []; this.handlers = {};
    this.classes = new Set((attrs.class || '').split(' '));
    this.style = {values: {}, setProperty(key, value) {this.values[key] = value;}};
    this.classList = {contains: x => this.classes.has(x), add: x => this.classes.add(x), remove: x => this.classes.delete(x), toggle: x => {
      if (this.classes.has(x)) {this.classes.delete(x); return false;} this.classes.add(x); return true;
    }};
  }
  addEventListener(name, fn) {(this.handlers[name] ||= []).push(fn);}
  fire(name, props = {}) {(this.handlers[name] || []).forEach(fn => fn({preventDefault() {}, ...props}));}
  setAttribute(key, value) {this.attrs[key] = value;}
  focus() {} scrollIntoView() {} setPointerCapture() {}
  getBoundingClientRect() {return {left: 100, top: 100, width: 304, height: 64};}
  showModal() {this.open = true;} close() {this.open = false;}
  append(...children) {children.forEach(child => {child.parent = this; this.children.push(child);});}
  remove() {this.parent.children = this.parent.children.filter(child => child !== this);}
  reset() {byId('dict-source').value = ''; byId('dict-target').value = '';}
}
for (const tag of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*?)>/gi)) {
  const attrs = {};
  for (const attr of tag[2].matchAll(/([\w-]+)(?:="([^"]*)")?/g)) attrs[attr[1]] = attr[2] || '';
  const node = new Element(attrs); node.tag = tag[1]; nodes.push(node);
}
const ids = nodes.filter(n => n.id).map(n => n.id);
assert.equal(ids.length, new Set(ids).size, 'Unique element IDs');
const byId = id => {const node = nodes.find(n => n.id === id); assert.ok(node, `Missing ID ${id}`); return node;};
const select = selector => {
  if (selector === '[name=mode]') return nodes.filter(n => n.attrs.name === 'mode');
  if (selector === '.state-strip button') return nodes.filter(n => n.tag === 'button' && 'data-state' in n.attrs);
  if (selector === '.material-options button') return nodes.filter(n => n.tag === 'button' && 'data-material' in n.attrs);
  const attribute = selector.match(/^\[([^\]]+)\]$/);
  assert.ok(attribute, `Unhandled selector ${selector}`); return nodes.filter(n => attribute[1] in n.attrs);
};
const document = new Element();
document.getElementById = byId; document.querySelectorAll = select;
document.createElement = () => new Element(); document.body = nodes.find(n => n.tag === 'body');
document.documentElement = nodes.find(n => n.tag === 'html');
let now = 0, timerID = 0; const timers = new Map();
const previewWindow = new Element(), mediaQuery = new Element();
mediaQuery.matches = false;
previewWindow.matchMedia = () => mediaQuery;
const context = vm.createContext({document, window: previewWindow, setTimeout: (fn, delay) => {
  timers.set(++timerID, {fn, at: now + delay}); return timerID;
}, clearTimeout: id => timers.delete(id)});
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
assert.ok(!/\b(fetch|XMLHttpRequest|localStorage|navigator)\b/.test(script), 'No network or browser device APIs');
assert.ok(!html.includes('__LOGO_DATA__'), 'Embedded logo');
assert.ok(!/<(?:script|link)[^>]+(?:src|href)=/i.test(html), 'No external runtime');
new vm.Script(script).runInContext(context);
function advance(ms) {
  const end = now + ms;
  while (true) {
    const next = [...timers.entries()].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
    if (!next) break;
    timers.delete(next[0]); now = next[1].at; next[1].fn();
  }
  now = end;
}
const state = () => byId('hud').dataset.state;
const click = id => byId(id).fire('click');
click('play'); assert.equal(state(), 'recording'); advance(2200); assert.equal(state(), 'recognizing');
advance(1400); assert.equal(state(), 'pasting'); advance(750); assert.equal(state(), 'done');
advance(1500); assert.ok(byId('hud').classes.has('hud-off'));
click('play'); advance(2200); click('cancel'); advance(6000); assert.equal(state(), 'cancelled');
byId('fail-option').checked = true; click('play'); advance(5000); assert.equal(state(), 'failed');
advance(6000); assert.ok(!byId('hud').classes.has('hud-off')); click('recover'); advance(650); assert.equal(state(), 'done');
click('play'); click('copy-preview'); assert.match(byId('main-status').textContent, /未读取或修改剪贴板/);
select('[name=mode]')[1].fire('change'); assert.equal(state(), 'ready');
byId('hold-demo').fire('click'); assert.equal(state(), 'recording'); byId('hold-demo').fire('click'); assert.equal(state(), 'recognizing');
select('[name=mode]')[0].fire('change'); byId('hold-demo').fire('pointerdown', {button: 0, pointerId: 1});
assert.equal(state(), 'recording'); byId('hold-demo').fire('pointerup'); assert.equal(state(), 'recognizing');
byId('hold-demo').fire('pointerdown', {button: 0, pointerId: 2}); byId('hold-demo').fire('pointercancel');
advance(6000); assert.equal(state(), 'cancelled');
click('tab-dictionary'); assert.equal(byId('panel-dictionary').hidden, false); assert.equal(byId('panel-general').hidden, true);
byId('dict-source').value = '<example>'; byId('dict-target').value = '语落'; byId('dictionary-form').fire('submit');
assert.equal(byId('dictionary-list').children[0].children[0].textContent, '<example> → 语落');
byId('dictionary-list').children[0].children[1].fire('click'); assert.equal(byId('dictionary-empty').hidden, false);
click('theme'); assert.equal(document.body.dataset.theme, 'dark'); click('motion'); assert.ok(document.documentElement.classes.has('reduce'));
select('.material-options button')[2].fire('click'); assert.equal(document.body.dataset.material, 'glow');
click('open-guide'); assert.equal(byId('guide').open, true); click('guide-done'); assert.equal(byId('guide').open, false);
// New controls must update both the visual parameter and its visible label.
byId('voice-level').value = '90'; byId('voice-level').fire('input');
assert.equal(byId('hud').style.values['--level'], '0.9');
assert.equal(byId('voice-level-value').textContent, '90%');
byId('glass-opacity').value = '36'; byId('glass-opacity').fire('input');
assert.equal(byId('hud').style.values['--glass-alpha'], '0.64');
assert.equal(byId('glass-opacity-value').textContent, '36%');
byId('backdrop').value = 'night'; byId('backdrop').fire('change');
assert.equal(byId('hud-stage').dataset.backdrop, 'night');
// Respect both the page preference and system preference; clamp edge movement.
byId('hud').fire('pointermove', {clientX:404,clientY:132,pointerType:'mouse'});
assert.equal(byId('hud').style.values['--pointer-x'], '50%');
click('motion'); byId('hud').fire('pointermove', {clientX:404,clientY:132,pointerType:'mouse'});
assert.equal(byId('hud').style.values['--pointer-x'], '100.0%');
assert.equal(byId('hud').style.values['--pointer-y'], '50.0%');
byId('hud').fire('pointerleave'); assert.equal(byId('hud').style.values['--pointer-x'], '50%');
mediaQuery.matches = true; byId('hud').fire('pointermove', {clientX:404,clientY:132,pointerType:'mouse'});
assert.equal(byId('hud').style.values['--pointer-x'], '50%');
mediaQuery.matches = false; byId('hud').fire('pointermove', {clientX:999,clientY:-20,pointerType:'mouse'});
assert.equal(byId('hud').style.values['--pointer-x'], '100.0%');
assert.equal(byId('hud').style.values['--pointer-y'], '0.0%');
console.log('PASS: level, transparency, desktop background, pointer light, reduced motion, bounds.');
console.log('PASS: structure, offline assets, flow, cancellation, recovery, hold/toggle, tabs, dictionary, theme, motion, materials, guide.');
console.log('Scope: simulated DOM logic only; browser rendering, real focus, and actual pointer behavior remain unverified.');
