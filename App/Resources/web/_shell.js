const post = (action, payload) => fetch('/api/command', {
  method:'POST', headers:{'Content-Type':'application/json'},
  body: JSON.stringify({action, payload: payload||{}})
}).catch(()=>{});
const getState = () => fetch('/api/state',{cache:'no-store'}).then(r=>r.json()).catch(()=>({}));
const esc = s => String(s==null?'':s).replace(/[&<>"']/g, c => (
  {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const host = u => { try { return new URL(u).host } catch(e) { return u } };
const fmtBytes = n => { if(!n) return '0 B'; const u=['B','KB','MB','GB']; let i=0,v=n;
  while(v>=1024&&i<u.length-1){v/=1024;i++} return v.toFixed(v<10&&i>0?1:0)+' '+u[i]; };
function shell(title){
  document.body.insertAdjacentHTML('afterbegin',
    '<div class="page"><div class="top"><a class="home" href="/index.html">&#8592; Forge</a><h1>'+esc(title)+'</h1></div><div id="body"></div></div>');
  return document.getElementById('body');
}

function toolShell(title, note){
  document.body.classList.add('tool');
  document.body.insertAdjacentHTML('afterbegin',
    '<div class="page"><div class="top"><a class="home" href="/index.html">&#8592; Forge</a>'
    + '<h1>'+esc(title)+'</h1></div>'
    + (note ? '<p style="color:var(--muted);font-size:12.5px;margin:-22px 0 22px">'+note+'</p>' : '')
    + '<div id="body"></div></div>');
  return document.getElementById('body');
}
function copyBtn(getText){
  const b = document.createElement('button');
  b.className = 'btn'; b.textContent = 'Copy';
  b.onclick = () => navigator.clipboard.writeText(getText()).then(
    ()=>{ b.textContent='Copied'; setTimeout(()=>b.textContent='Copy',1200); },
    ()=>{ b.textContent='Blocked'; setTimeout(()=>b.textContent='Copy',1200); });
  return b;
}
