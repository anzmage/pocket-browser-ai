const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { JSDOM } = require('jsdom');
const fixture = readFileSync('assets/fixture.html', 'utf8');
const observer = readFileSync('assets/observer.js', 'utf8');
function setup() {
  const dom = new JSDOM(fixture, { url:'https://fixture.test/?token=private-query#private-fragment', runScripts:'dangerously', pretendToBeVisual:true });
  const w = dom.window;
  // jsdom does not implement layout; this is a DOM contract test, NOT a real
  // Android WebView/visibility test. Device fixture testing is still required.
  w.Element.prototype.getBoundingClientRect = function() {
    return {x:0,y:0,top:0,left:0,right:200,bottom:40,width:200,height:40};
  };
  w.scrollBy = (_, y) => { Object.defineProperty(w,'scrollY',{value:w.scrollY+y,configurable:true}); };
  w.eval(observer);
  const api = w.__pocketPageV1;
  let id=0;
  const snap=()=>api.observe('s'+(++id));
  const find=(s,label)=>s.elements.find(e=>e.label.includes(label)).id;
  const exec=(s,action,fields={})=>api.execute({action,snapshotId:s.id,...fields});
  return {dom,w,api,snap,find,exec};
}
test('redacts password, OTP, hidden, echoed values, URL query and fragment', () => {
  const {dom,w,snap} = setup();
  w.document.getElementById('result').textContent = 'echo fixture-password-not-for-model 765432 fixture-hidden-token-not-for-model';
  const s=snap(), raw=JSON.stringify(s);
  for(const secret of ['fixture-password-not-for-model','765432','fixture-hidden-token-not-for-model','private-query','private-fragment','hidden-private-content']) {
    assert.ok(!raw.includes(secret),secret);
  }
  assert.equal(s.elements.filter(e=>e.sensitive).length,2);
  assert.ok(!s.elements.some(e=>e.type==='hidden'));
  dom.window.close();
});
test('type with safely encoded hostile-looking text, input/change events', () => {
  const {dom,w,snap,find,exec}=setup(); const s=snap();
  const text='Pocket "); window.pwned=true; // <script>';
  const result=exec(s,'type',{elementId:find(s,'Nama tampilan'),text});
  assert.equal(result.ok,true);
  assert.equal(w.document.getElementById('display-name').value,text);
  assert.equal(w.pwned,undefined);
  assert.equal(w.document.getElementById('event-status').textContent,'Input/change: 2');
  assert.ok(!JSON.stringify(snap()).includes(text));
  dom.window.close();
});
test('select, click and asynchronous dynamic content verified after observation', async () => {
  const {dom,w,snap,find,exec}=setup(); let s=snap();
  assert.ok(exec(s,'type',{elementId:find(s,'Nama tampilan'),text:'Pocket'}).ok);
  s=snap(); assert.ok(exec(s,'select',{elementId:find(s,'Warna'),value:'biru'}).ok);
  const before=snap(); assert.ok(exec(before,'click',{elementId:find(before,'Tampilkan hasil')}).ok);
  await new Promise(r=>setTimeout(r,250));
  assert.equal(w.document.getElementById('result').textContent,'Hasil: Pocket / biru');
  assert.notEqual(before.fingerprint,snap().fingerprint);
  dom.window.close();
});
test('unknown action, wrong snapshot, disabled, sensitive and reused references rejected', () => {
  const {dom,snap,exec,find,api}=setup(); let s=snap();
  assert.equal(api.execute({action:'click',snapshotId:'old',elementId:'e0'}).error,'stale');
  const secret=s.elements.find(e=>e.sensitive);
  assert.equal(exec(s,'type',{elementId:secret.id,text:'no'}).error,'manual');
  assert.equal(exec(s,'click',{elementId:find(s,'Nonaktif')}).error,'manual');
  assert.equal(exec(s,'execute_javascript',{text:'bad'}).error,'unknown');
  s=snap(); assert.ok(exec(s,'observe').ok); assert.equal(exec(s,'observe').error,'stale');
  dom.window.close();
});
test('DOM replacement, attribute mutation, user input and SPA navigation invalidate snapshot', () => {
  for (const change of [
    w=>w.document.getElementById('preview').replaceWith(w.document.createElement('button')),
    w=>w.document.getElementById('preview').setAttribute('disabled',''),
    w=>w.document.getElementById('display-name').dispatchEvent(new w.Event('input',{bubbles:true})),
    w=>w.history.pushState({},'', '/changed'),
  ]) {
    const {dom,w,snap,exec,find}=setup(); const s=snap(), id=find(s,'Tampilkan hasil');
    change(w); assert.equal(exec(s,'click',{elementId:id}).error,'stale'); dom.window.close();
  }
});
test('external schemes rejected and bounds enforced', () => {
  const {dom,snap,exec,find}=setup(); let s=snap();
  assert.equal(exec(s,'click',{elementId:find(s,'Skema eksternal')}).error,'scheme');
  s=snap(); assert.equal(exec(s,'scroll',{direction:'down',amount:1201}).error,'scroll');
  s=snap(); assert.equal(exec(s,'select',{elementId:find(s,'Warna'),value:'not-a-choice'}).error,'select');
  dom.window.close();
});
test('login forms and username inputs manual-only, no native bridge or dynamic eval', () => {
  const {dom,w,snap}=setup();
  const form=w.document.createElement('form');
  form.innerHTML='<label>Email<input type="email"></label><input type="password"><button>Sign in</button>';
  w.document.body.appendChild(form);
  const s=snap();
  assert.ok(s.elements.filter(e=>e.label==='[manual only]').length>=5);
  assert.ok(!/document\.cookie|localStorage|sessionStorage|\beval\s*\(|new Function|addJavaScriptChannel/.test(observer));
  dom.window.close();
});
