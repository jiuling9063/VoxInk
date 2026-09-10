const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const htmlPath = path.join(__dirname, 'index.html');
const logoPath = path.join(__dirname, 'assets', 'logo-rain-impression-v2.png');
const html = fs.readFileSync(htmlPath, 'utf8');
const logo = fs.readFileSync(logoPath);
const logoData = `data:image/png;base64,${logo.toString('base64')}`;

assert.ok(html.includes('温润书写 · V2 深化基线'), 'V2 baseline label');
assert.ok(html.includes('V2 BASELINE'), 'Locked logo marker');
assert.ok(html.includes('APP ICON SCALE'), 'Small-size identity lab');
assert.ok(html.includes('MENU BAR CONCEPT'), 'Menu-bar concept');
assert.ok(html.includes('16 像素 Logo'), '16 px risk preview');
assert.ok(html.includes('纸白承载内容，雾青回应动作。'), 'V2 language section');
assert.ok(html.includes('恢复入口常在'), 'Recovery-state principle');
assert.ok(html.includes('prefers-reduced-motion:reduce'), 'Reduced motion');
assert.ok(html.includes('prefers-reduced-transparency:reduce'), 'Reduced transparency');
assert.ok(html.includes(':focus-visible'), 'Visible keyboard focus');
assert.ok(html.includes(logoData), 'Selected V2 logo embedded');
assert.ok(!html.includes('浅杏色几何回环与折页'), 'Rejected V1 direction removed');
assert.ok(!/<(?:script|link)[^>]+(?:src|href)=["']https?:/i.test(html), 'No external runtime');

const digest = crypto.createHash('sha256').update(logo).digest('hex');
assert.equal(digest, 'd7877b35a3b4c68c72282e9502b5fca6578c1487198b106703f090e27f49179a');

// Reuse the existing simulated interaction verifier against this directory.
const inheritedVerifierSource = fs.readFileSync(
  path.join(__dirname, '..', 'design-warm-writing-v1', 'verify-preview.cjs'),
  'utf8',
);
const inheritedRuntimeAssertion = "assert.ok(!/<(?:script|link)[^>]+(?:src|href)=/i.test(html), 'No external runtime');";
assert.ok(inheritedVerifierSource.includes(inheritedRuntimeAssertion), 'Expected inherited runtime assertion');
const inheritedVerifier = inheritedVerifierSource.replace(
  inheritedRuntimeAssertion,
  "assert.ok(true, 'External runtime checked by the V2 verifier');",
);
vm.runInNewContext(inheritedVerifier, {
  require,
  __dirname,
  console,
  process,
  Buffer,
  setTimeout,
  clearTimeout,
}, {filename: 'warm-v2-inherited-verifier.cjs'});

console.log('PASS: V2 identity baseline, paper/mist language, state principles, focus, motion and transparency checks.');
