(() => {
  'use strict';
  document.documentElement.classList.add('js-docs');
  const sidebar = document.querySelector('.sidebar');
  if (sidebar) {
    const nav = sidebar.querySelector('nav');
    if (nav) {
      nav.id ||= 'doc-navigation';
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'mobile-menu';
      button.textContent = document.documentElement.lang === 'cs' ? 'Obsah' : 'Contents';
      button.setAttribute('aria-expanded', 'false');button.setAttribute('aria-controls', nav.id);
      button.addEventListener('click', () => button.setAttribute('aria-expanded', String(sidebar.classList.toggle('nav-open'))));
      sidebar.insertBefore(button, nav);
      nav.addEventListener('click', e => {if(e.target.closest('a')){sidebar.classList.remove('nav-open');button.setAttribute('aria-expanded','false');}});
    }
  }
  const sections = [...document.querySelectorAll('main section')];
  const chapters = [...document.querySelectorAll('details.chapter')];
  const search = document.querySelector('[data-doc-search]');
  let previousOpen = null;
  function filter() {
    const q = search.value.trim().toLowerCase();
    if(q && !previousOpen) previousOpen = new Map([...document.querySelectorAll('details')].map(d=>[d,d.open]));
    let count=0;
    sections.forEach(s=>{s.hidden=Boolean(q&&!s.textContent.toLowerCase().includes(q));if(!s.hidden){count++;if(q)s.querySelectorAll('details').forEach(d=>d.open=true);}});
    if(!q && previousOpen){previousOpen.forEach((open,d)=>d.open=open);previousOpen=null;}
    const status=document.querySelector('#search-status');
    if(status)status.textContent=q ? (count ? `${count} matching sections` : 'No matching sections. Try a market, input name or status code.') : '';
  }
  if(search){search.addEventListener('input',filter);document.querySelector('#print')?.addEventListener('click',()=>window.print());}
  function revealHash() {
    let id;try{id=decodeURIComponent(location.hash.slice(1));}catch{return;}
    if(!id)return;
    const target=document.getElementById(id);if(!target)return;
    if(search&&search.value){search.value='';filter();}
    target.hidden=false;
    let parent=target.closest('details');while(parent){parent.open=true;parent=parent.parentElement.closest('details');}
    target.querySelector(':scope > details.chapter')?.setAttribute('open','');
  }
  document.addEventListener('click',e=>{
    const link=e.target.closest('a[href^="#"]');if(!link)return;
    const id=link.getAttribute('href').slice(1);const target=document.getElementById(id);if(!target)return;
    if(search&&search.value){search.value='';filter();}
    target.hidden=false;target.querySelector(':scope > details.chapter')?.setAttribute('open','');
    let parent=target.closest('details');while(parent){parent.open=true;parent=parent.parentElement.closest('details');}
  });
  window.addEventListener('hashchange',revealHash);revealHash();
  document.querySelectorAll('[data-chapters]').forEach(b=>b.addEventListener('click',()=>chapters.forEach(d=>d.open=b.dataset.chapters==='expand')));
  document.querySelectorAll('pre').forEach((pre,i)=>{
    if(pre.previousElementSibling?.classList.contains('code-head'))return;
    const head=document.createElement('div');head.className='code-head';
    const label=document.createElement('span');label.textContent=pre.textContent.includes(';')?'Reference / code':'Reference';head.append(label);
    const copy=document.createElement('button');copy.type='button';copy.className='copy-code';copy.textContent='Copy';copy.setAttribute('aria-label',`Copy code example ${i+1}`);
    copy.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(pre.textContent);copy.textContent='Copied';}catch{copy.textContent='Select and copy';const range=document.createRange();range.selectNodeContents(pre);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);}setTimeout(()=>copy.textContent='Copy',2200);});
    head.append(copy);pre.before(head);
  });
  let printState=[];
  window.addEventListener('beforeprint',()=>{printState=[...document.querySelectorAll('details')].map(d=>[d,d.open]);printState.forEach(([d])=>d.open=true);});
  window.addEventListener('afterprint',()=>printState.forEach(([d,open])=>d.open=open));
  const links=[...document.querySelectorAll('.sidebar nav a[href^="#"]')];
  if('IntersectionObserver' in window){
    const observer=new IntersectionObserver(entries=>{const entry=entries.find(e=>e.isIntersecting);if(!entry)return;links.forEach(a=>{const active=a.getAttribute('href')==='#'+entry.target.id;a.classList.toggle('active',active);if(active)a.setAttribute('aria-current','location');else a.removeAttribute('aria-current');});},{rootMargin:'-5% 0px -60% 0px'});
    sections.forEach(s=>observer.observe(s));
  }
})();
