// Run with npm test. Executes the real non-UI methods with an ArkWeb mock.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const ts = require('typescript');
const { parseHTML } = require('linkedom');
const root = path.resolve(__dirname, '..');
const bridgeSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/WebBridge.ets'), 'utf8');
const bridge = { exports: {} };
vm.runInNewContext(ts.transpile(bridgeSource, { module: ts.ModuleKind.CommonJS }), bridge);
const controlBridge = { exports: {} };
vm.runInNewContext(ts.transpile(fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ControlsBridge.ets'), 'utf8'), { module: ts.ModuleKind.CommonJS }), controlBridge);
let source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
source = source.slice(0, source.indexOf('  @Builder')) + '\n}\nglobalThis.TestIndex = Index;';
source = source.replace(/^import[\s\S]*?;\n/gm, '').replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace('struct Index', 'class Index');
class Controller {
  constructor() { this.url = 'https://chatgpt.com/'; this.scripts = []; }
  getUrl() { return this.url; }
  runJavaScript(script) {
    this.scripts.push(script);
    if (this.hook) return this.hook(script);
    if (script === controlBridge.exports.CONTROL_STATE) return Promise.resolve(JSON.stringify({ mode: 'chat', canSwitch: true, model: 'GPT test', effort: '', available: true }));
    return Promise.resolve(script === bridge.exports.SNAPSHOT
      ? JSON.stringify({ ready: true, auth: 'signed-in', historyEmpty: false, generating: false, model: 'model', chats: [] }) : 'ready');
  }
}
const sandbox = {
  ...bridge.exports, ...controlBridge.exports, setInterval, clearInterval, setTimeout,
  webview: { WebviewController: Controller, WebDownloadDelegate: class {} },
  hilog: { info() {}, warn() {} }
};
vm.runInNewContext(ts.transpile(source, { target: ts.ScriptTarget.ES2020 }), sandbox);
const fresh = () => { const app = new sandbox.TestIndex(); app.documentReady = true; return app; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function page(html) {
  const { document } = parseHTML('<html><body>' + html + '</body></html>');
  for (const e of document.querySelectorAll('*')) {
    e.getBoundingClientRect = () => e.hasAttribute('hidden')
      ? { width: 0, height: 0, left: 0, right: 0 }
      : { width: 100, height: 30, left: 0, right: 100 };
  }
  return { document, URL, innerWidth: 480, location: { origin: 'https://chatgpt.com', href: 'https://chatgpt.com/', pathname: '/' } };
}
const snapshot = context => JSON.parse(vm.runInNewContext(bridge.exports.SNAPSHOT, context));

(async () => {
  let app = fresh();
  await app.syncWebsite();
  assert.equal(app.composerReady, true, 'chat editor becomes available');
  assert.equal(app.accountState, 'signed-in', 'login state is consumed independently of conversation count');

  let context = page('<button data-testid="profile-button">Account</button><textarea></textarea>');
  assert.equal(snapshot(context).auth, 'signed-in', 'signed-in account without mounted history is still signed in');
  assert.equal(snapshot(page('<textarea></textarea>')).auth, 'unknown', 'missing history does not imply logged out');
  assert.equal(snapshot(page('<button>登录</button>')).auth, 'signed-out', 'explicit login control identifies signed-out state');
  const homeEditor = '<form data-harmony-composer><textarea></textarea></form>';
  assert.equal(snapshot(page(homeEditor)).home, true, 'a ready empty home can show the native welcome');
  assert.equal(snapshot(page('<textarea></textarea>')).home, false, 'never cover a homepage whose editor cannot be replaced');
  assert.equal(snapshot(page(homeEditor + '<button>登录</button>')).home, false, 'keep login controls visible');
  assert.equal(snapshot(page(homeEditor + '<div data-message-author-role="user">Existing message</div>')).home, false, 'never cover conversation content before its URL updates');
  assert.equal(snapshot(page(homeEditor + '<button data-testid="stop-button"></button>')).home, false, 'never cover a generating answer');
  context = page(homeEditor); context.location.pathname = '/c/existing';
  assert.equal(snapshot(context).home, false, 'existing conversation pages stay visible even while messages load');
  context.location.pathname = '/dot';
  assert.equal(snapshot(context).home, false, 'Dot retains its own content');
  assert.equal(snapshot(context).contentReady, true, 'an empty ready Dot editor can finish its transition');
  context.location.pathname = '/c/loading';
  assert.equal(snapshot(context).contentReady, false, 'history waits for its messages, not just its editor');
  context.document.body.insertAdjacentHTML('beforeend', '<div data-message-author-role="user">A message</div>');
  assert.equal(snapshot(context).contentReady, true);
  context.document.body.insertAdjacentHTML('beforeend', '<main><div role="progressbar"></div></main>');
  context.document.querySelector('[role="progressbar"]').getBoundingClientRect = () => ({width: 10, height: 10});
  assert.equal(snapshot(context).contentReady, false, 'a live page loading indicator keeps the transition covered');
  const idleComposer = '<section id="composer"><div><div contenteditable="true" role="textbox"></div></div><button aria-label="添加文件等内容"></button><button aria-label="选择 ChatGPT 模型"></button><button aria-label="开始语音"></button></section>';
  context = page('<main><div data-message-author-role="assistant">A loaded response</div>' + idleComposer + '</main>');
  context.location.pathname = '/c/idle';
  assert.equal(vm.runInNewContext(bridge.exports.ADAPT, context), 'ready', 'empty history composer with a voice control is adaptable');
  assert.equal(context.document.querySelector('[data-harmony-composer]').id, 'composer', 'only the input container is replaced');
  assert.equal(snapshot(context).contentReady, true, 'completed history with an idle composer releases its loading cover');
  for (const label of ['复制', 'Copy response']) {
    context = page('<main><section><p>A rendered historical answer</p><div><button aria-label="' + label + '"></button></div></section>' + idleComposer + '</main>');
    context.location.pathname = '/c/current-layout';
    vm.runInNewContext(bridge.exports.ADAPT, context);
    assert.equal(snapshot(context).contentReady, true, 'current conversation layout without legacy message markers finishes loading');
    context.location.pathname = '/';
    assert.equal(snapshot(context).home, false, 'new-layout answers are not covered by the empty-home screen');
  }
  context = page('<main><p>ChatGPT can make mistakes.</p>' + homeEditor + '<button aria-label="复制"></button></main>');
  context.location.pathname = '/c/loading';
  assert.equal(snapshot(context).contentReady, false, 'unrelated copy action and global footer do not imply a loaded answer');
  context = page('<main><div data-message-author-role="assistant">A response<button aria-label="开始语音"></button><button aria-label="选择 ChatGPT 模型"></button><button aria-label="添加文件等内容"></button></div><div contenteditable="true" role="textbox"></div></main>');
  assert.equal(vm.runInNewContext(bridge.exports.ADAPT, context), 'waiting', 'unrelated voice/model buttons cannot cause conversation content to be hidden');
  context = page('<a href="#main">Skip to content</a><nav id="history"><a href="/c/one">First</a><a href="/g/project/c/two">Second</a><a href="/c/one">Duplicate</a><a href="https://other.example/c/three">External</a></nav>');
  context.location.href = 'https://chatgpt.com/c/current';
  assert.deepEqual(snapshot(context).chats.map(c => c.title), ['First', 'Second']);
  assert.equal(snapshot(context).auth, 'signed-in');

  for (const attrs of ['aria-label="显示侧边栏"', 'aria-label="打开侧边栏"', 'aria-label="打开边栏"', 'aria-label="Open sidebar"', 'data-testid="open-sidebar-button" aria-label="Menu"']) {
    context = page('<button ' + attrs + '></button>');
    let clicked = 0; context.document.querySelector('button').addEventListener('click', () => clicked++);
    assert.equal(vm.runInNewContext(bridge.exports.OPEN_SIDEBAR, context), 'opened');
    assert.equal(clicked, 1, 'localized sidebar control opens');
  }
  context = page('<button aria-label="Open sidebar"></button><nav id="history"><a href="/c/one">First</a></nav>');
  assert.equal(vm.runInNewContext(bridge.exports.OPEN_SIDEBAR, context), 'already-open', 'retry does not toggle an open sidebar closed');
  context.document.querySelector('nav').getBoundingClientRect = () => ({ width: 100, height: 100, left: -100, right: 0 });
  assert.equal(vm.runInNewContext(bridge.exports.OPEN_SIDEBAR, context), 'opened', 'offscreen sidebar still needs opening');

  // Current navigation uses #ds-sidebar and can render duplicate hidden controls.
  context = page('<button disabled aria-label="Open sidebar"></button><button aria-label="Toggle sidebar"></button><aside id="ds-sidebar" hidden></aside>');
  let toggled = 0; context.document.querySelectorAll('button')[1].addEventListener('click', () => toggled++);
  assert.equal(vm.runInNewContext(bridge.exports.OPEN_SIDEBAR, context), 'opened');
  assert.equal(toggled, 1, 'skip a disabled duplicate toggle');
  for (const name of ['你的 Dot', 'Your Dot', 'Dot']) {
    context = page('<button>' + name + '</button>');
    let opened = 0; context.document.querySelector('button').addEventListener('click', () => opened++);
    assert.equal(vm.runInNewContext(bridge.exports.OPEN_DOT, context), 'opened');
    assert.equal(opened, 1);
  }
  context = page('<button>Dot settings</button><button>My Dot task</button>');
  assert.equal(vm.runInNewContext(bridge.exports.OPEN_DOT, context), 'unavailable', 'do not click unrelated settings or chat titles');
  context = page('<a href="https://unrelated.example/">Dot</a>');
  assert.equal(vm.runInNewContext(bridge.exports.OPEN_DOT, context), 'external', 'navigation stays on official origin');

  app = fresh(); app.chats = [{ title: 'Retained', url: 'https://chatgpt.com/c/one' }];
  await app.syncWebsite();
  assert.equal(app.chats.length, 1, 'collapsing/unmounting history does not clear the native list');
  app.main.hook = script => Promise.resolve(script === bridge.exports.SNAPSHOT
    ? JSON.stringify({ ready: true, auth: 'signed-out', historyEmpty: false, chats: [] }) : 'ready');
  await app.syncWebsite();
  assert.equal(app.chats.length, 0, 'explicit logout clears the native list');

  app = fresh(); let reads = 0;
  app.main.hook = script => Promise.resolve(script === bridge.exports.SNAPSHOT
    ? JSON.stringify({ ready: true, auth: 'signed-in', historyEmpty: false, chats: ++reads > 1 ? [{ title: 'Loaded', url: 'https://chatgpt.com/c/one' }] : [] }) : 'opened');
  await app.openDrawer();
  assert.equal(app.chats.length, 1, 'drawer waits for asynchronously mounted conversation history');
  assert.equal(app.historyLoading, false);

  app = fresh(); app.documentReady = false;
  await app.openDrawer();
  assert.equal(app.drawerVisible, true, 'native settings remain accessible before the website is ready');
  assert.equal(app.main.scripts.length, 0, 'opening native settings does not inspect an unready document');

  for (const url of ['https://auth.openai.com/log-in/password', 'https://chatgpt.com/auth/callback?code=redacted']) {
    app = fresh(); app.main.url = url;
    await app.syncWebsite(); await app.showOfficial(bridge.exports.OPEN_LOGIN);
    assert.equal(app.main.scripts.length, 0, 'no adapter or login scripts in authentication documents');
  }

  app = fresh(); app.officialMode = true;
  await app.syncWebsite();
  assert.equal(app.main.scripts.length, 0, 'official mode suspends polling scripts');

  app = fresh(); let release;
  app.main.hook = () => new Promise(resolve => { release = resolve; });
  const adapting = app.syncWebsite();
  app.navigation++; app.main.url = 'https://auth.openai.com/log-in';
  release('ready'); await adapting;
  assert.equal(app.main.scripts.length, 1, 'navigation interrupts the ADAPT to SNAPSHOT chain');
  assert.equal(app.composerReady, false);

  app = fresh(); let snapshotRelease;
  app.main.hook = script => script === bridge.exports.ADAPT ? Promise.resolve('ready') :
    script === bridge.exports.SNAPSHOT ? new Promise(resolve => { snapshotRelease = resolve; }) : Promise.resolve('ready');
  const reading = app.syncWebsite(); await tick();
  app.navigation++; app.officialMode = true;
  snapshotRelease(JSON.stringify({ ready: true, model: 'stale', chats: [] })); await reading;
  assert.equal(app.composerReady, false, 'stale snapshot cannot enable native composer during login');
  assert.equal(app.modelName, '');

  app = fresh(); let oldRelease;
  app.main.hook = () => new Promise(resolve => { oldRelease = resolve; });
  const old = app.syncWebsite(); app.navigation++;
  app.main.hook = undefined;
  await app.syncWebsite();
  assert.equal(app.composerReady, true, 'new document can sync even while old renderer promise is pending');
  oldRelease('ready'); await old;

  // Authentication documents must not be inspected even if ArkWeb reports a stale URL.
  for (const location of [
    { origin: 'https://auth.openai.com', pathname: '/log-in/password' },
    { origin: 'https://chatgpt.com', pathname: '/auth/callback' }
  ]) {
    const context = { location, document: new Proxy({}, { get() { throw Error('authentication DOM accessed'); } }) };
    assert.equal(vm.runInNewContext(bridge.exports.ADAPT, context), 'external');
    assert.equal(JSON.parse(vm.runInNewContext(bridge.exports.SNAPSHOT, context)).ready, false);
    assert.equal(vm.runInNewContext(bridge.exports.DOCUMENT_HEALTH, context), 'auth-skip');
    assert.equal(vm.runInNewContext(bridge.exports.OPEN_SIDEBAR, context), 'external');
    assert.equal(vm.runInNewContext(bridge.exports.CLOSE_SIDEBAR, context), 'external');
    for (const script of [controlBridge.exports.CONTROL_STATE, controlBridge.exports.OPEN_CONTROL, controlBridge.exports.OPEN_MODEL_OPTIONS, controlBridge.exports.READ_CONTROL, controlBridge.exports.CLOSE_CONTROL, controlBridge.exports.CONTROL_DIAGNOSTICS, controlBridge.exports.switchMode('work'), controlBridge.exports.chooseControl('0', 'GPT test'), controlBridge.exports.stepEffort(1)]) {
      assert.equal(vm.runInNewContext(script, context), 'external', 'model controls must never access authentication DOM');
    }
  }
  const controls = controlBridge.exports;
  context = page('<header><div><button aria-pressed="false">聊天</button><button aria-pressed="true">工作</button></div></header><form data-harmony-composer><button aria-label="选择 ChatGPT 模型">GPT-6.1 Sol 轻度</button></form><aside data-harmony-sidebar><a>聊天</a></aside>');
  let controlState = JSON.parse(vm.runInNewContext(controls.CONTROL_STATE, context));
  assert.equal(controlState.mode, 'work'); assert.equal(controlState.canSwitch, true);
  assert.equal(controlState.model, 'GPT-6.1 Sol'); assert.equal(controlState.effort, '轻度');
  let modeClicks = 0; context.document.querySelector('header button').addEventListener('click', () => modeClicks++);
  assert.equal(vm.runInNewContext(controls.switchMode('chat'), context), 'dispatched');
  assert.equal(modeClicks, 1);
  assert.equal(vm.runInNewContext(controls.switchMode('work'), context), 'selected');
  context = page('<nav id="history"><button>聊天</button><button>工作</button></nav>');
  assert.equal(vm.runInNewContext(controls.switchMode('work'), context), 'unavailable', 'history titles are not mode controls');
  context = page('<div role="menu"><button role="menuitemradio" aria-checked="true">GPT-6.1 Sol</button><button role="menuitemradio">GPT-6.1 Terra</button><button role="menuitemradio" aria-disabled="true">Unavailable</button></div>');
  let panel = JSON.parse(vm.runInNewContext(controls.READ_CONTROL, context));
  assert.equal(panel.choices.length, 2); assert.equal(panel.choices[0].selected, true);
  let selections = 0; context.document.querySelectorAll('button')[1].addEventListener('click', () => selections++);
  assert.equal(vm.runInNewContext(controls.chooseControl('1', 'GPT-6.1 Terra'), context), 'dispatched');
  assert.equal(selections, 1);
  assert.equal(vm.runInNewContext(controls.chooseControl('1', 'Old label'), context), 'stale', 'never select a changed or stale menu row');
  context = page('<div role="dialog"><button>GPT-6.1 Sol</button><span role="slider" aria-valuemin="0" aria-valuemax="5" aria-valuenow="1" aria-valuetext="Standard"></span></div>');
  panel = JSON.parse(vm.runInNewContext(controls.READ_CONTROL, context));
  assert.equal(panel.hasSlider, true); assert.equal(panel.max, 5); assert.equal(panel.effort, 'Standard');
  assert.equal(panel.choices.length, 0, 'power popover model row is not mistaken for the model choices');
  context = page('<form data-harmony-composer><textarea></textarea><button aria-label="选择 ChatGPT 模型" data-state="open">选择推理强度</button><div><div>标准</div><div><span>GPT-6.1 Sol</span></div><div><span role="slider" aria-valuemin="0" aria-valuemax="5" aria-valuenow="1"></span></div></div></form>');
  let modelOpened = 0;
  context.document.querySelector('span').addEventListener('click', () => modelOpened++);
  assert.equal(vm.runInNewContext(controls.OPEN_MODEL_OPTIONS, context), 'opened', 'custom model row without a button role is supported');
  assert.equal(modelOpened, 1);
  panel = JSON.parse(vm.runInNewContext(controls.READ_CONTROL, context));
  assert.equal(panel.effort, '标准', 'separate power label from model and composer text');
  assert.equal(panel.model, 'GPT-6.1 Sol');
  let popupClosed = 0;
  context.document.querySelector('button').addEventListener('click', () => popupClosed++);
  assert.equal(vm.runInNewContext(controls.CLOSE_CONTROL, context), 'closed');
  assert.equal(popupClosed, 1, 'custom popup closes through its own trigger');
  context = page('<button aria-label="选择 ChatGPT 模型" data-state="open">选择推理强度</button><div><button>GPT-6.1 Sol</button><button>GPT-6.1 Terra</button></div><aside data-harmony-sidebar><button>GPT-6.1 unrelated conversation</button></aside>');
  panel = JSON.parse(vm.runInNewContext(controls.READ_CONTROL, context));
  assert.equal(panel.choices.length, 2, 'custom model menu supports ordinary buttons without capturing sidebar titles');
  context = page('<button aria-label="选择 ChatGPT 模型">思考强度 High</button>');
  controlState = JSON.parse(vm.runInNewContext(controls.CONTROL_STATE, context));
  assert.equal(controlState.model, '', 'reasoning label is never presented as a model');
  assert.equal(controlState.effort, 'High');
  context = page('<button aria-label="选择 ChatGPT 模型" data-state="open">思考强度 Instant</button><div role="menu"><div role="menuitem" aria-label="选择模型">Instant</div><div role="menuitem"><span role="slider" aria-valuemin="0" aria-valuemax="4" aria-valuenow="0"></span></div><div role="menuitemradio" aria-checked="true">GPT-6</div><div role="menuitemradio">GPT-5.6 Sol</div></div>');
  let explicitModelOpened = 0;
  context.document.querySelector('[aria-label="选择模型"]').addEventListener('click', () => explicitModelOpened++);
  assert.equal(vm.runInNewContext(controls.OPEN_MODEL_OPTIONS, context), 'opened', 'model submenu uses its own labelled control even when text says Instant');
  assert.equal(explicitModelOpened, 1);
  panel = JSON.parse(vm.runInNewContext(controls.READ_CONTROL, context));
  assert.equal(panel.choices.length, 2, 'models remain readable when the same popup also contains the effort slider');
  assert.equal(panel.model, 'GPT-6', 'checked model is independent from the effort label');
  app = fresh(); app.controlSheet = 'model';
  await app.syncWebsite(); assert.equal(app.main.scripts.length, 0, 'background adaptation is suspended while native picker is open');

  // Deterministic timers exercise real native transition methods, including stale callbacks.
  let now = 1000, timerID = 0;
  const timers = new Map();
  sandbox.Date = { now: () => now };
  sandbox.setInterval = sandbox.setTimeout = fn => { timers.set(++timerID, fn); return timerID; };
  sandbox.clearInterval = sandbox.clearTimeout = id => timers.delete(id);
  const readyPage = { auth: 'signed-in', route: '/c/new', surface: '/c/new|editor', contentReady: true };
  app = fresh(); app.lastSurface = '/c/old|editor';
  app.beginPageTransition('加载会话…', 'https://chatgpt.com/c/new', true);
  app.updatePageTransition(readyPage);
  assert.equal(app.transitionStableSince, 0, 'do not reveal before the new document starts');
  app.transitionDocumentPending = false;
  app.updatePageTransition({ ...readyPage, route: '/c/old' });
  assert.equal(app.transitionStableSince, 0, 'stale route cannot reveal a different destination');
  app.updatePageTransition({ ...readyPage, contentReady: false });
  assert.equal(app.transitionStableSince, 0, 'unadapted or incomplete content stays covered');
  app.updatePageTransition(readyPage);
  now += 300;
  app.updatePageTransition(readyPage);
  assert.equal(app.transitionOpacity, 0, 'stable content starts a short fade');
  assert.equal(app.switchingPage, true, 'keep the cover mounted until the fade finishes');
  const oldFinish = timers.get(app.transitionFinish);
  app.beginPageTransition('正在打开 Dot…');
  oldFinish();
  assert.equal(app.switchingPage, true, 'an old fade callback cannot dismiss a newer transition');
  app.updatePageTransition(readyPage);
  assert.equal(app.transitionStableSince, 0, 'Dot cannot reveal the previous editor while SPA navigation is pending');
  app.updatePageTransition({ ...readyPage, surface: '/dot|new-editor' });
  now += 300;
  app.updatePageTransition({ ...readyPage, surface: '/dot|new-editor' });
  timers.get(app.transitionFinish)();
  assert.equal(app.switchingPage, false);
  assert.equal(timers.size, 0, 'successful reveal clears transition timers');

  app.beginPageTransition('加载中…');
  timers.get(app.transitionTimeout)();
  assert.equal(app.transitionSlow, true, 'slow loads expose a manual escape instead of hiding forever');
  app.updatePageTransition({ ...readyPage, auth: 'signed-out' });
  assert.equal(app.switchingPage, false, 'login is never hidden behind a loading cover');
  app.beginPageTransition('加载中…');
  app.onPageHide();
  assert.equal(timers.size, 0, 'leaving the page cancels all transition work');

  app = fresh();
  const navigated = [];
  app.main.loadUrl = url => navigated.push(url);
  const loading = app.loadChatPage('https://chatgpt.com/c/first', '加载会话…');
  assert.equal(app.switchingPage, true, 'cover is committed before requesting another document');
  assert.equal(navigated.length, 0);
  const beforeLoad = timers.get(timerID);
  timers.delete(timerID);
  app.beginPageTransition('新页面…', 'https://chatgpt.com/c/second', true);
  beforeLoad(); await loading;
  assert.equal(navigated.length, 0, 'superseded navigation cannot load its old destination');
  app.cancelPageTransition();
  assert.equal(timers.size, 0);
  console.log('PASS: page transition readiness, stale route/fade guards, slow-load escape, login visibility, native controls, login/history separation, async history, auth isolation, navigation races');
})().catch(error => { console.error(error); process.exitCode = 1; });
