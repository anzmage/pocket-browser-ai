(() => {
  'use strict';
  // Fixed app code. No native bridge, eval, cookie/storage access or model code.
  if (window.__pocketPageV1) return true;
  let revision = 0, current = null;
  const observer = new MutationObserver(() => { revision++; });
  observer.observe(document, {subtree:true, childList:true, attributes:true, characterData:true});
  document.addEventListener('input', () => { revision++; }, true);
  document.addEventListener('change', () => { revision++; }, true);
  const flush = () => { if (observer.takeRecords().length) revision++; };
  const visible = el => {
    if (!el || !el.isConnected || el.closest('[hidden],[aria-hidden="true"],[inert]')) return false;
    const s = getComputedStyle(el), r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0' &&
      r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth;
  };
  const secretPattern = /password|passwd|passcode|otp|one.?time|token|secret|api.?key|authorization|cookie|credit|card|cvv|cvc|captcha|pin\b|sandi|kartu|verification|auth|login|username|sign.?in|masuk/i;
  const sensitive = el => {
    const type = (el.type || '').toLowerCase();
    return ['password','hidden','file'].includes(type) ||
      (!!el.form && !!el.form.querySelector('input[type="password"],input[autocomplete="one-time-code"]')) || secretPattern.test([
      el.name, el.id, el.autocomplete, el.getAttribute('aria-label'), el.getAttribute('placeholder'),
      ['BUTTON','A'].includes(el.tagName) ? el.textContent : '',
      ...(el.labels ? Array.from(el.labels).map(l => l.textContent) : []),
      el.form && [el.form.id, el.form.name, el.form.getAttribute('action')].join(' ')
    ].join(' '));
  };
  const secrets = () => Array.from(document.querySelectorAll('input,textarea,select'))
    .map(e => e.value).filter(v => typeof v === 'string' && v.length > 0).sort((a,b) => b.length-a.length);
  const clean = (v, values) => {
    let s = String(v || '');
    for (const value of values) s = s.split(value).join('[field]');
    return s.replace(/\bBearer\s+\S+/gi,'[REDACTED]')
      .replace(/(?:password|passwd|token|secret|api[_ -]?key|otp|cookie|authorization)\s*[:=]\s*[^\s,;]+/gi,'[REDACTED]')
      .replace(/\b(?:sk-[\w-]+|eyJ[\w-]+\.[\w-]+\.[\w-]+|[\w-]{40,})\b/g,'[REDACTED]')
      .replace(/\s+/g,' ').trim();
  };
  const safeUrl = (raw, values) => {
    try { const u = new URL(raw); return ['http:','https:'].includes(u.protocol) ? clean(u.origin + u.pathname, values) : 'local fixture'; }
    catch (_) { return 'local fixture'; }
  };
  const label = el => el.getAttribute('aria-label') ||
    (el.labels ? Array.from(el.labels).map(l => l.textContent).join(' ') : '') ||
    el.getAttribute('placeholder') ||
    (['INPUT','TEXTAREA','SELECT'].includes(el.tagName) ? el.name || el.type : el.textContent) || el.tagName;
  const signature = el => JSON.stringify([el.tagName, el.type, label(el), el.getAttribute('href'),
    el.disabled, el.readOnly, sensitive(el), el.tagName === 'SELECT' ? Array.from(el.options).map(o => [o.value,o.disabled]) : []]);
  const hash = str => { let n = 2166136261; for (let i=0;i<str.length;i++) n = Math.imul(n ^ str.charCodeAt(i),16777619); return (n>>>0).toString(16); };
  const observe = id => {
    flush();
    const values = secrets(), map = new Map(), elements = [];
    for (const el of document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"]')) {
      if (!visible(el) || el.type === 'hidden') continue;
      if (elements.length >= 70) break;
      const eid = 'e' + elements.length, isSecret = sensitive(el);
      map.set(eid, {el, signature:signature(el)});
      elements.push({id:eid, role:el.tagName.toLowerCase(), type:el.type || el.getAttribute('role') || '',
        label:isSecret ? '[manual only]' : clean(label(el), values).slice(0,180),
        enabled:!el.disabled && !el.readOnly && el.getAttribute('aria-disabled') !== 'true',
        sensitive:isSecret,
        options:el.tagName === 'SELECT' && !isSecret ? Array.from(el.options).filter(o=>!o.disabled).slice(0,60).map(o=>clean(o.value, [])) : []});
    }
    // Text nodes only: no script, hidden DOM, form values, contenteditable or markup.
    const root = document.querySelector('main,[role="main"]') || document.body;
    let text = '';
    if (root) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let node, count=0;
      while ((node = walker.nextNode()) && count++ < 15000 && text.length < 6000) {
        const parent = node.parentElement;
        if (!parent || parent.closest('script,style,noscript,template,input,textarea,select,[contenteditable], [data-private]') || !visible(parent)) continue;
        // Exclude labelled sensitive regions as well as field values echoed in text.
        if (secretPattern.test(parent.id + ' ' + parent.className)) continue;
        text += clean(node.textContent, values) + ' ';
      }
    }
    const snapshot = {id, url:safeUrl(location.href, values), title:clean(document.title, values).slice(0,200),
      text:clean(text, values).slice(0,6000), elements};
    const inputState = Array.from(map.values()).filter(x=>!sensitive(x.el)).map(x=>[x.el.value || '',x.el.checked || false]);
    snapshot.fingerprint = hash(JSON.stringify([snapshot.url,snapshot.title,snapshot.text,elements,inputState,scrollX,scrollY]));
    current = {id, revision, href:location.href, map};
    return snapshot;
  };
  const execute = action => {
    flush();
    if (!current || current.id !== action.snapshotId || current.revision !== revision || current.href !== location.href) return {ok:false,error:'stale'};
    let el;
    if (action.elementId) {
      const entry = current.map.get(action.elementId);
      if (!entry || !visible(entry.el) || entry.signature !== signature(entry.el)) return {ok:false,error:'stale'};
      el = entry.el;
      if (sensitive(el) || el.disabled || el.readOnly || el.getAttribute('aria-disabled') === 'true') return {ok:false,error:'manual'};
    }
    // Consume snapshot before any action. A second call cannot reuse it.
    current = null;
    switch(action.action) {
      case 'observe': return {ok:true};
      case 'click': {
        if (!el) return {ok:false,error:'element'};
        const a = el.closest('a[href]');
        if (a) {
          const u = new URL(a.href, location.href);
          if (!['https:','http:'].includes(u.protocol) || u.username || u.password) return {ok:false,error:'scheme'};
          if (a.target && a.target !== '_self') return {ok:false,error:'popup'};
        }
        el.click(); break;
      }
      case 'type': {
        if (!el || !['INPUT','TEXTAREA'].includes(el.tagName) || !['text','search','url','email','tel','number','textarea'].includes(el.type) || typeof action.text !== 'string' || action.text.length > 4000) return {ok:false,error:'type'};
        const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto,'value').set;
        el.focus(); setter.call(el,action.text);
        el.dispatchEvent(new Event('input',{bubbles:true,composed:true}));
        el.dispatchEvent(new Event('change',{bubbles:true,composed:true}));
        break;
      }
      case 'select':
        if (!el || el.tagName !== 'SELECT' || !Array.from(el.options).some(o=>o.value === action.value && !o.disabled)) return {ok:false,error:'select'};
        Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,'value').set.call(el,action.value);
        el.dispatchEvent(new Event('input',{bubbles:true,composed:true}));
        el.dispatchEvent(new Event('change',{bubbles:true,composed:true}));
        break;
      case 'scroll':
        if (!['up','down'].includes(action.direction) || !Number.isInteger(action.amount) || action.amount<1 || action.amount>1200) return {ok:false,error:'scroll'};
        window.scrollBy(0,action.amount*(action.direction==='up'?-1:1)); break;
      // Native executor handles validated navigation/wait/back.
      case 'navigate': case 'back': case 'wait': return {ok:true};
      default: return {ok:false,error:'unknown'};
    }
    return {ok:true};
  };
  Object.defineProperty(window,'__pocketPageV1',{value:Object.freeze({observe,execute}),configurable:false,writable:false});
  return true;
})()
