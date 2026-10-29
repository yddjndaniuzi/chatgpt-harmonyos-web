// DOM-only adapter. Never reads cookies, tokens, or private network endpoints.
// When the website changes, the user can always return to its original view.
export const ADAPT: string = `(() => {
  if (location.origin !== 'https://chatgpt.com' || /^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname)) return 'external';
  let style = document.getElementById('harmony-chat-style');
  if (!style) {
    style = document.createElement('style'); style.id = 'harmony-chat-style';
    style.textContent = '[data-harmony-header]{display:none!important}' +
      '[data-harmony-sidebar]{visibility:hidden!important;pointer-events:none!important}' +
      '[data-harmony-composer]{position:fixed!important;top:0!important;left:0!important;opacity:0!important;pointer-events:none!important;max-height:1px!important;overflow:hidden!important;z-index:-1!important}' +
      'html,body{overscroll-behavior:none!important}' +
      'body,textarea,button{font-family:HarmonyOS Sans,system-ui,sans-serif!important}';
    document.head.appendChild(style);
  }
  style.disabled = false;
  const visible = e => e && e.getBoundingClientRect().width > 0 && e.getBoundingClientRect().height > 0;
  for (const h of document.querySelectorAll('header')) {
    const r=h.getBoundingClientRect();
    if(r.top>=0 && r.top<100 && r.height<120 && r.width>innerWidth*.6) h.setAttribute('data-harmony-header','');
  }
  for (const b of document.querySelectorAll('button[aria-label="显示侧边栏"],button[aria-label="Show sidebar"],button[aria-label="打开边栏"],button[aria-label="Open sidebar"],button[data-testid="open-sidebar-button"]')) {
    if(!visible(b)) continue;
    let p=b;
    for(let i=0;p&&i<5;i++,p=p.parentElement){
      const r=p.getBoundingClientRect();
      if(r.width>innerWidth*.75 && r.height>30 && r.height<120 && r.top<100){p.setAttribute('data-harmony-header','');break;}
    }
  }
  const editors=Array.from(document.querySelectorAll('textarea,[contenteditable="true"][role="textbox"],#prompt-textarea'));
  const editor=editors.find(visible) || editors.find(e=>e.closest('[data-harmony-composer]'));
  if(editor){
    editor.setAttribute('data-harmony-editor','');
    if(!editor.hasAttribute('data-harmony-surface'))editor.setAttribute('data-harmony-surface',Date.now().toString(36)+Math.random().toString(36).slice(2));
    let form=editor.closest('form');
    if(!form){
      let p=editor.parentElement;
      for(let i=0;p&&i<9;i++,p=p.parentElement){
        const send=p.querySelector('button[aria-label="发送"],button[aria-label="Send"],button[aria-label="发送消息"],button[aria-label="Send message"],button[data-testid="send-button"]');
        // An empty history composer shows voice instead of send and may have no form tag.
        const idle=p.querySelector('button[aria-label="开始语音"],button[aria-label="Start voice mode"],button[aria-label="Start voice"]')&&
          p.querySelector('button[aria-label="添加文件等内容"],button[aria-label="添加文件等"],button[aria-label="Add files and more"],button[data-testid="composer-plus-btn"]')&&
          p.querySelector('button[aria-label="选择 ChatGPT 模型"],button[aria-label="Choose ChatGPT model"],button[aria-label="Select ChatGPT model"],[data-testid="model-switcher-dropdown-button"]')&&
          !p.querySelector('[data-message-author-role],[data-testid^="conversation-turn-"]');
        if(send||idle){form=p;break;}
      }
    }
    if(form)form.setAttribute('data-harmony-composer','');
  }
  for(const nav of document.querySelectorAll('#ds-sidebar,#stage-slideover-sidebar,[data-testid="sidebar"],nav[aria-label="Sidebar shortcuts"]')) nav.setAttribute('data-harmony-sidebar','');
  return editor&&editor.closest('[data-harmony-composer]') ? 'ready' : 'waiting';
})()`;

export const ORIGINAL: string = `(() => {
  const s=document.getElementById('harmony-chat-style');if(s)s.disabled=true;return 'ok';
})()`;

// Structural metadata only: no body text, field values, URLs, cookies or account data.
export const DOCUMENT_HEALTH: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'auth-skip';
  const b=document.body,r=document.querySelector('main')||document.getElementById('root');
  const s=b?getComputedStyle(b):null,a=document.getElementById('harmony-chat-style');
  return JSON.stringify({state:document.readyState,elements:document.getElementsByTagName('*').length,
    textLength:b?(b.innerText||'').length:0,scripts:document.scripts.length,
    editors:document.querySelectorAll('textarea,#prompt-textarea,[contenteditable="true"][role="textbox"]').length,
    composers:document.querySelectorAll('[data-harmony-composer]').length,
    messages:document.querySelectorAll('[data-message-author-role],[data-testid^="conversation-turn-"]').length,
    mainHeight:r?Math.round(r.getBoundingClientRect().height):-1,
    display:s?s.display:'none',visibility:s?s.visibility:'unknown',opacity:s?s.opacity:'unknown',
    adapted:!!a&&!a.disabled,challenge:/just a moment|attention required|verify/i.test(document.title)});
})()`;

const SIDEBAR_DOM: string = `
  const controls=Array.from(document.querySelectorAll('button,[role="button"]'));
  const label=e=>(e.getAttribute('aria-label')||e.getAttribute('title')||'').trim();
  const isOpen=e=>e.getAttribute('data-testid')==='open-sidebar-button'||/^(open sidebar|show sidebar|toggle sidebar|显示(?:侧边栏|边栏|侧栏)|打开(?:侧边栏|边栏|侧栏)|展开(?:侧边栏|边栏|侧栏)|切换(?:侧边栏|边栏|侧栏))$/i.test(label(e));
  const openControls=controls.filter(isOpen);
  const openControl=openControls.find(e=>visible(e)&&!e.disabled)||openControls.find(e=>!e.disabled);
  const closeControl=controls.find(e=>visible(e)&&!e.disabled&&(e.getAttribute('data-testid')==='close-sidebar-button'||/^(close sidebar|hide sidebar|隐藏(?:侧边栏|边栏|侧栏)|关闭(?:侧边栏|边栏|侧栏)|收起(?:侧边栏|边栏|侧栏))$/i.test(label(e))));
  const history=document.querySelector('#history,[data-testid="history"],[data-testid="conversation-list"],nav[aria-label="Chat history"]');
  const sidebar=document.querySelector('#ds-sidebar,#stage-slideover-sidebar,[data-testid="sidebar"]')||history;
`;

// Some conversation layouts omit the legacy message/test attributes. Recognize
// a rendered answer by its public copy action and nearby prose, never by body text.
const MESSAGE_DOM: string = `
  const legacyMessages=!!document.querySelector('[data-message-author-role],[data-testid^="conversation-turn-"]');
  const answerActions=Array.from(document.querySelectorAll('button,[role="button"]')).filter(e=>
    !e.closest('[data-harmony-composer],form,nav,aside,[role="dialog"],[data-harmony-sidebar]')&&
    /^(复制|复制回复|复制回答|Copy|Copy response|Copy answer)$/i.test((e.getAttribute('aria-label')||e.getAttribute('title')||'').trim()));
  const renderedAnswer=answerActions.some(action=>{
    let p=action.parentElement;
    for(let i=0;p&&i<7;i++,p=p.parentElement){
      if(p.querySelector('textarea,#prompt-textarea,[contenteditable="true"][role="textbox"]'))return false;
      if(Array.from(p.querySelectorAll('p,pre,blockquote,li')).some(e=>(e.textContent||'').trim().length>0))return true;
    }
    return false;
  });
  const hasMessages=legacyMessages||renderedAnswer;
`;

export const SNAPSHOT: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return JSON.stringify({ready:false,auth:'unknown',historyEmpty:false,generating:false,model:'',chats:[]});
  const visible=e=>e&&e.getBoundingClientRect().width>0&&e.getBoundingClientRect().height>0;
` + SIDEBAR_DOM + MESSAGE_DOM + `
  const editor=document.querySelector('textarea,#prompt-textarea,[contenteditable="true"][role="textbox"]');
  const model=document.querySelector('[data-testid="model-switcher-dropdown-button"]');
  const login=Array.from(document.querySelectorAll('button,a')).some(e=>visible(e)&&/^(登录|Log in|Sign in)$/.test(e.textContent.trim()));
  const account=document.querySelector('[data-testid="profile-button"],[data-testid="accounts-profile-button"],[data-testid="user-menu-button"],button[aria-label="Open profile menu"],button[aria-label="打开个人资料菜单"]');
  const chats=[];const seen=new Set();
  for(const a of document.querySelectorAll('a[href]')){
    if((a.getAttribute('href')||'').startsWith('#'))continue;
    const u=new URL(a.href,location.href);const t=(a.innerText||a.textContent||a.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim();
    if(u.origin===location.origin&&/^\\/(?:g\\/[^/]+\\/)?c\\/[^/]+/.test(u.pathname)&&t&&!seen.has(u.pathname)){
      seen.add(u.pathname);chats.push({url:u.origin+u.pathname,title:t.slice(0,120)});
    }
  }
  const generating=Array.from(document.querySelectorAll('[data-testid="stop-button"],button[aria-label="停止生成"],button[aria-label="Stop generating"]')).some(visible);
  const auth=chats.length>0||account?'signed-in':login?'signed-out':'unknown';
  const historyEmpty=!!history&&visible(history)&&/^(暂无会话|暂无聊天|还没有聊天记录|No chats yet|Your conversations will appear here)[。.!]?$/i.test((history.textContent||'').trim());
  const ready=!!editor&&!!editor.closest('[data-harmony-composer]');
  const home=location.pathname==='/'&&ready&&!login&&!generating&&!hasMessages;
  const loading=Array.from(document.querySelectorAll('main [aria-busy="true"],main [role="progressbar"],[data-testid="conversation-loading"]')).some(visible);
  const historyRoute=/^\\/(?:g\\/[^/]+\\/)?c\\/[^/]+/.test(location.pathname);
  const contentReady=ready&&!loading&&(!historyRoute||hasMessages);
  const surface=location.pathname+'|'+(editor?.getAttribute('data-harmony-surface')||'');
  return JSON.stringify({ready,home,auth,historyEmpty,generating,route:location.pathname,surface,contentReady,model:model?(model.innerText||model.textContent||'').trim():'',chats:chats.slice(0,100)});
})()`;

export const OPEN_SIDEBAR: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'external';
  const visible=e=>e&&e.getBoundingClientRect().width>0&&e.getBoundingClientRect().height>0;
` + SIDEBAR_DOM + `
  const inViewport=e=>{if(!visible(e))return false;const r=e.getBoundingClientRect();return r.right>0&&r.left<innerWidth;};
  if(closeControl&&inViewport(closeControl))return 'already-open';
  if(history&&inViewport(history))return 'already-open';
  if(sidebar&&inViewport(sidebar)&&(!openControl||openControl.getAttribute('aria-expanded')==='true'))return 'already-open';
  if(openControl){openControl.click();return 'opened';}return 'not-found';
})()`;

export const CLOSE_SIDEBAR: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'external';
  const visible=e=>e&&e.getBoundingClientRect().width>0&&e.getBoundingClientRect().height>0;
` + SIDEBAR_DOM + `
  if(closeControl){closeControl.click();return 'closed';}return 'unchanged';
})()`;

export const OPEN_LOGIN: string = `(() => {
  const b=Array.from(document.querySelectorAll('button,a')).find(e=>e.getBoundingClientRect().width>0&&/^(登录|Log in|Sign in)$/.test(e.textContent.trim()));
  if(b){b.click();return 'ok'}return 'unavailable';
})()`;

export const OPEN_ATTACHMENTS: string = `(() => {
  const b=document.querySelector('button[aria-label="添加文件等内容"],button[aria-label="添加文件等"],button[aria-label="Add files and more"],button[data-testid="composer-plus-btn"]');
  if(b){b.click();return 'ok'}return 'unavailable';
})()`;

export const SEND: string = `(() => {
  const b=document.querySelector('button[data-testid="send-button"],button[aria-label="发送"],button[aria-label="Send"],button[aria-label="发送消息"],button[aria-label="Send message"]');
  if(!b||b.disabled||b.getAttribute('aria-disabled')==='true')return 'unavailable';
  b.click();return 'dispatched';
})()`;

export const STOP: string = `(() => {
  const b=document.querySelector('[data-testid="stop-button"],button[aria-label="停止生成"],button[aria-label="Stop generating"]');
  if(b)b.click();return 'ok';
})()`;

export function writeDraft(text: string): string {
  return `(() => {
    const e=document.querySelector('[data-harmony-editor]')||Array.from(document.querySelectorAll('textarea,#prompt-textarea,[contenteditable="true"][role="textbox"]')).find(e=>e.getBoundingClientRect().width>0&&e.getBoundingClientRect().height>0);
    if(!e)return 'unavailable';const text=` + JSON.stringify(text) + `;
    if(e.tagName==='TEXTAREA'){
      const setter=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set;
      setter.call(e,text);e.dispatchEvent(new Event('input',{bubbles:true}));
    }else{
      e.focus();const s=getSelection();const r=document.createRange();r.selectNodeContents(e);s.removeAllRanges();s.addRange(r);
      document.execCommand('insertText',false,text);
      e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:text}));
    }e.blur();return 'ready';
  })()`;
}

// Use the site's own navigation controls. Never synthesize a private API request.
export const OPEN_DOT: string = `(() => {
    if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'external';
    const pattern=/^(?:你的\\s*Dot|Your\\s*Dot|Dot)$/i;
    const controls=Array.from(document.querySelectorAll('a,button,[role="button"],[role="menuitem"]'));
    const target=controls.find(e=>!e.disabled&&[e.getAttribute('aria-label'),e.getAttribute('title'),e.textContent].some(t=>pattern.test((t||'').replace(/\\s+/g,' ').trim())));
    if(!target)return 'unavailable';
    if(target.tagName==='A'){
      const u=new URL(target.href,location.href);
      if(u.origin!==location.origin)return 'external';
      target.removeAttribute('target');
    }
    target.click();return 'opened';
})()`;

export const NAV_DIAGNOSTICS: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'auth-skip';
  return JSON.stringify(Array.from(document.querySelectorAll('button,[role="button"],a')).map(e=>({label:e.getAttribute('aria-label')||e.getAttribute('title')||'',test:e.getAttribute('data-testid')||''})).filter(x=>/sidebar|边栏|侧栏|navigation|菜单|Dot/i.test(x.label+' '+x.test)).slice(0,24));
})()`;

export const EDITOR_DIAGNOSTICS: string = `(() => {
  if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'auth-skip';
  let p=document.querySelector('[data-harmony-editor],textarea,#prompt-textarea,[contenteditable="true"][role="textbox"]');
  const result=[];
  for(let i=0;p&&i<6;i++,p=p.parentElement){
    result.push({tag:p.tagName,id:p.id,role:p.getAttribute('role'),buttons:Array.from(p.querySelectorAll('button')).map(b=>({label:b.getAttribute('aria-label'),test:b.getAttribute('data-testid'),type:b.type})).slice(0,12)});
  }
  return JSON.stringify(result);
})()`;
