// Public UI controls only. Values and choices come from the signed-in page.
const GUARD: string = `if(location.origin!=='https://chatgpt.com'||/^\\/(?:auth|api|backend-api|login|signin|signup)(?:\\/|$)/i.test(location.pathname))return 'external';`;
const DOM: string = `
  const text=e=>(e?.innerText||e?.textContent||'').replace(/\\s+/g,' ').trim();
  const label=e=>(e?.getAttribute('aria-label')||'').trim();
  const enabled=e=>e&&!e.disabled&&e.getAttribute('aria-disabled')!=='true';
  const visible=e=>e&&e.getBoundingClientRect().width>0&&e.getBoundingClientRect().height>0;
  const buttons=Array.from(document.querySelectorAll('button,[role="button"],[role="tab"],[role="radio"],[tabindex="0"],a'));
  const selected=e=>e&&(e.getAttribute('aria-selected')==='true'||e.getAttribute('aria-pressed')==='true'||e.getAttribute('aria-checked')==='true'||e.getAttribute('data-state')==='active'||e.getAttribute('data-state')==='on'||e.getAttribute('data-state')==='checked');
  const modeButtons=buttons.filter(e=>/^(聊天|工作|Chat|Work)$/.test(text(e))&&!e.closest('[data-harmony-sidebar],#history'));
  const modePair=modeButtons.filter(e=>{let p=e.parentElement;for(let i=0;p&&i<3;i++,p=p.parentElement){const t=text(p);if(/(?:聊天.*工作|Chat.*Work)/.test(t)&&t.length<60)return true;}return false;});
  const modelTrigger=document.querySelector('[data-testid="model-switcher-dropdown-button"],button[aria-label="选择 ChatGPT 模型"],button[aria-label="Choose ChatGPT model"],button[aria-label="Select ChatGPT model"]')||buttons.find(e=>/^(选择推理强度|Choose reasoning effort|Select reasoning effort)$/.test(label(e)));
  const slider=Array.from(document.querySelectorAll('[role="slider"],input[type="range"]')).find(visible);
  const menus=Array.from(document.querySelectorAll('[role="menu"],[role="listbox"],[role="dialog"],[data-radix-popper-content-wrapper]')).filter(visible);
  const inMenu=e=>menus.some(m=>m.contains(e));
  const isModel=e=>/^GPT[-\\s]?\\d[\\w. -]*$/.test(text(e));
  const safe=e=>!e.closest('[data-harmony-sidebar],#history,[data-message-author-role],[data-testid^="conversation-turn-"],#ds-sidebar');
  let powerPanel=slider?.parentElement;
  for(let i=0;powerPanel&&i<7;i++){
    if(powerPanel.querySelector('textarea,[contenteditable="true"]')){powerPanel=null;break;}
    if(Array.from(powerPanel.querySelectorAll('button,span,div')).some(e=>!e.children.length&&isModel(e)))break;
    powerPanel=powerPanel.parentElement;
  }
  if(powerPanel&&!powerPanel.querySelector('textarea,[contenteditable="true"]'))menus.push(powerPanel);
  const modelRow=document.querySelector('[role="menuitem"][aria-label="选择模型"],[role="menuitem"][aria-label="Select model"],[role="menuitem"][aria-label="Choose model"]')||buttons.find(e=>e!==modelTrigger&&enabled(e)&&visible(e)&&safe(e)&&isModel(e)&&(inMenu(e)||!!slider))||
    (powerPanel?Array.from(powerPanel.querySelectorAll('span,div')).find(e=>!e.children.length&&isModel(e)):null);
  const triggerOpen=modelTrigger&&(modelTrigger.getAttribute('aria-expanded')==='true'||modelTrigger.getAttribute('data-state')==='open');
  const owned=e=>inMenu(e)||(triggerOpen&&e!==modelTrigger&&safe(e)&&e.tagName!=='A');
  const modelText=text(modelTrigger);
  const modelMatch=modelText.match(/GPT[-\\s]?\\d[\\w. -]*?(?=\\s*(?:[一-龥]|Light|Standard|Extended|Heavy|Minimal|Low|Medium|High|XHigh|Max|Ultra|$))/i);
  const effortText=slider?.getAttribute('aria-valuetext')||(modelMatch?modelText.replace(modelMatch[0],'').trim():modelText.replace(/^(?:思考强度|选择推理强度|Reasoning effort)\\s*/i,'').replace(/^\\d+(?:\\.\\d+)?\\s+/,'').trim());
  const activeMode=modePair.find(selected);
`;

export const CONTROL_STATE: string = `(() => {` + GUARD + DOM + `
  return JSON.stringify({mode:activeMode?(/^(工作|Work)$/.test(text(activeMode))?'work':'chat'):'',canSwitch:modePair.length>=2,model:modelMatch?modelMatch[0].trim():'',effort:effortText,available:!!modelTrigger});
})()`;

export function switchMode(mode: string): string {
  return `(() => {` + GUARD + DOM + `
    const target=modePair.find(e=>` + (mode === 'work' ? `/^(工作|Work)$/` : `/^(聊天|Chat)$/`) + `.test(text(e))&&enabled(e));
    if(!target)return 'unavailable';if(selected(target))return 'selected';target.click();return 'dispatched';
  })()`;
}

export const OPEN_CONTROL: string = `(() => {` + GUARD + DOM + `
  if(triggerOpen&&(slider||menus.length))return 'open';
  if(!enabled(modelTrigger))return 'unavailable';modelTrigger.setAttribute('data-harmony-control-trigger','');
  modelTrigger.click();return 'opened';
})()`;

export const OPEN_MODEL_OPTIONS: string = `(() => {` + GUARD + DOM + `
  if(slider&&modelRow){modelRow.click();return 'opened';}return 'unchanged';
})()`;

export const READ_CONTROL: string = `(() => {` + GUARD + DOM + `
  let options=Array.from(document.querySelectorAll('[role="menuitemradio"],[role="menuitem"],[role="option"]')).filter(e=>visible(e)&&enabled(e)&&owned(e)&&text(e)&&!e.querySelector('[role="menuitemradio"],[role="menuitem"],[role="option"]'));
  // Some model pickers expose ordinary buttons instead of menu roles.
  if(!options.length&&!slider)options=buttons.filter(e=>visible(e)&&enabled(e)&&owned(e)&&/^(?:GPT[-\\s]?\\d|默认|Default|推荐模型集|Recommended models)/i.test(text(e)));
  options=options.filter(e=>(e!==modelRow||!slider||e.matches('[role="menuitem"],[role="menuitemradio"],[role="option"]'))&&!/^(选择模型|Select model|Choose model)$/.test(label(e))&&/^(?:GPT[-\\s]?\\d|o[1-9](?:[-\\s]|$)|默认|Default|推荐模型集|Recommended models|Auto|Instant|Thinking|Pro|自动|即时|思考|专业)(?:.*)$/i.test(text(e)));
  const choices=options.slice(0,30).map((e,i)=>{e.setAttribute('data-harmony-control-choice',String(i));return {key:String(i),label:text(e).slice(0,100),selected:selected(e)};});
  let effort=effortText;
  if(slider&&!effort&&powerPanel){effort=text(powerPanel).replace(text(modelRow),'').trim().slice(0,50);}
  return JSON.stringify({choices,hasSlider:!!slider,min:slider?Number(slider.getAttribute('aria-valuemin')||slider.min||0):0,max:slider?Number(slider.getAttribute('aria-valuemax')||slider.max||0):0,value:slider?Number(slider.getAttribute('aria-valuenow')||slider.value||0):0,effort,model:choices.find(c=>c.selected)?.label||text(modelRow)||modelText});
})()`;

export function chooseControl(key: string, expectedLabel: string): string {
  return `(() => {` + GUARD + DOM + `
    const key=` + JSON.stringify(key) + `, expected=` + JSON.stringify(expectedLabel) + `;
    const target=Array.from(document.querySelectorAll('[data-harmony-control-choice]')).find(e=>e.getAttribute('data-harmony-control-choice')===key&&text(e).slice(0,100)===expected&&visible(e)&&enabled(e)&&owned(e));
    if(!target)return 'stale';target.click();return 'dispatched';
  })()`;
}

export function stepEffort(direction: number): string {
  return `(() => {` + GUARD + DOM + `
    if(!slider||!enabled(slider))return 'unavailable';
    const key=` + JSON.stringify(direction > 0 ? 'ArrowRight' : 'ArrowLeft') + `;
    slider.focus();slider.dispatchEvent(new KeyboardEvent('keydown',{key,code:key,bubbles:true,cancelable:true}));
    slider.dispatchEvent(new KeyboardEvent('keyup',{key,code:key,bubbles:true,cancelable:true}));slider.blur();return 'dispatched';
  })()`;
}

export const CLOSE_CONTROL: string = `(() => {` + GUARD + DOM + `
  if(triggerOpen){modelTrigger.click();return 'closed';}
  const target=document.querySelector('[role="slider"],[role="menuitemradio"],[role="menuitem"],[role="option"]')||document.activeElement||document.body;
  target.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',code:'Escape',bubbles:true,cancelable:true}));
  target.dispatchEvent(new KeyboardEvent('keyup',{key:'Escape',code:'Escape',bubbles:true,cancelable:true}));
  return 'closed';
})()`;

// Restricted structural diagnostics: never include editors, conversation text or links.
export const CONTROL_DIAGNOSTICS: string = `(() => {` + GUARD + DOM + `
  const describe=e=>({tag:e.tagName,role:e.getAttribute('role'),label:label(e),text:text(e).slice(0,100),state:e.getAttribute('data-state'),pressed:e.getAttribute('aria-pressed'),selected:e.getAttribute('aria-selected'),checked:e.getAttribute('aria-checked'),test:e.getAttribute('data-testid'),min:e.getAttribute('aria-valuemin'),max:e.getAttribute('aria-valuemax'),value:e.getAttribute('aria-valuenow'),valueText:e.getAttribute('aria-valuetext')});
  const optionNodes=Array.from(document.querySelectorAll('[role="menuitem"],[role="menuitemradio"],[role="option"]')).filter(e=>visible(e)&&owned(e)&&/GPT|默认|Default|选择模型|思考/.test(label(e)+' '+text(e)));
  return JSON.stringify({modes:modePair.map(describe),trigger:modelTrigger?describe(modelTrigger):null,slider:slider?describe(slider):null,options:optionNodes.slice(0,8).map(describe)});
})()`;
