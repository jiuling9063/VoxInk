// Pointer light is a preview interaction. A native HUD must retain nonactivation.
const lightHud = $('hud');
const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
function resetLightPosition() {
 lightHud.style.setProperty('--pointer-x','50%');
 lightHud.style.setProperty('--pointer-y','0%');
}
lightHud.addEventListener('pointermove',event=>{
 if(document.documentElement.classList.contains('reduce') || reducedMotionQuery.matches || event.pointerType==='touch') return;
 const bounds=lightHud.getBoundingClientRect();
 if(!bounds.width || !bounds.height) return;
 const x=Math.max(0,Math.min(100,(event.clientX-bounds.left)/bounds.width*100));
 const y=Math.max(0,Math.min(100,(event.clientY-bounds.top)/bounds.height*100));
 lightHud.style.setProperty('--pointer-x',x.toFixed(1)+'%');
 lightHud.style.setProperty('--pointer-y',y.toFixed(1)+'%');
});
lightHud.addEventListener('pointerleave',resetLightPosition);
$('motion').addEventListener('click',resetLightPosition);
reducedMotionQuery.addEventListener('change',resetLightPosition);
$('voice-level').addEventListener('input',()=>{
 const value=Number($('voice-level').value);
 lightHud.style.setProperty('--level',String(value/100));
 $('voice-level-value').textContent=value+'%';
});
$('glass-opacity').addEventListener('input',()=>{
 const value=Number($('glass-opacity').value);
 lightHud.style.setProperty('--glass-alpha',String((100-value)/100));
 $('glass-opacity-value').textContent=value+'%';
});
$('backdrop').addEventListener('change',()=>{
 $('hud-stage').dataset.backdrop=$('backdrop').value;
});
