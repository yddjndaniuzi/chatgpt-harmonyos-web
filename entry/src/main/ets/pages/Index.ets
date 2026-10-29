import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http, connection } from '@kit.NetworkKit';
import { ADAPT, ORIGINAL, SNAPSHOT, DOCUMENT_HEALTH, OPEN_SIDEBAR, CLOSE_SIDEBAR,
  OPEN_LOGIN, OPEN_ATTACHMENTS, SEND, STOP, writeDraft, OPEN_DOT, NAV_DIAGNOSTICS, EDITOR_DIAGNOSTICS } from './WebBridge';

import { CONTROL_STATE, OPEN_CONTROL, OPEN_MODEL_OPTIONS, READ_CONTROL, CLOSE_CONTROL,
  CONTROL_DIAGNOSTICS, switchMode, chooseControl, stepEffort } from './ControlsBridge';

const HOME: string = 'https://chatgpt.com/';

interface Conversation {
  title: string;
  url: string;
}

interface WebsiteState {
  ready: boolean;
  home: boolean;
  auth: string;
  historyEmpty: boolean;
  generating: boolean;
  model: string;
  route: string;
  surface: string;
  contentReady: boolean;
  chats: Conversation[];
}

interface ControlState {
  mode: string;
  canSwitch: boolean;
  model: string;
  effort: string;
  available: boolean;
}

interface ControlChoice { key: string; label: string; selected: boolean; }
interface ControlPanel {
  choices: ControlChoice[];
  hasSlider: boolean;
  min: number;
  max: number;
  value: number;
  effort: string;
  model: string;
}

interface ConnectionCheck {
  label: string;
  host: string;
  result: string;
}

@Entry
@Component
struct Index {
  @State private progress: number = 0;
  @State private popupVisible: boolean = false;
  @State private error: string = '';
  @State private drawerVisible: boolean = false;
  @State private officialMode: boolean = false;
  @State private shellReady: boolean = false;
  @State private composerReady: boolean = false;
  @State private homeReady: boolean = false;
  @State private compactLayout: boolean = true;
  @State private generating: boolean = false;
  @State private dispatching: boolean = false;
  @State private draft: string = '';
  @State private search: string = '';
  @State private activeSection: string = '会话';
  @State private sectionBusy: boolean = false;
  private conversationUrl: string = HOME;
  @State private modelName: string = '';
  @State private chatMode: string = '';
  @State private canSwitchMode: boolean = false;
  @State private controlsAvailable: boolean = false;
  @State private effortName: string = '';
  @State private controlSheet: string = '';
  @State private controlBusy: boolean = false;
  @State private controlError: string = '';
  @State private controlChoices: ControlChoice[] = [];
  @State private effortMin: number = 0;
  @State private effortMax: number = 0;
  @State private effortValue: number = 0;
  @State private effortAvailable: boolean = false;
  private controlRequest: number = 0;
  private observedModels: Map<string, string> = new Map<string, string>();
  @State private switchingPage: boolean = false;
  @State private transitionOpacity: number = 1;
  @State private transitionLabel: string = '加载中…';
  @State private transitionSlow: boolean = false;
  private transitionRequest: number = 0;
  private transitionPoll: number = -1;
  private transitionTimeout: number = -1;
  private transitionFinish: number = -1;
  private transitionStarted: number = 0;
  private transitionStableSince: number = 0;
  private transitionSignature: string = '';
  private transitionStatus: string = '';
  private transitionTarget: string = '';
  private transitionSource: string = '';
  private transitionDocumentPending: boolean = false;
  private lastSurface: string = '';
  @State private chats: Conversation[] = [];
  @State private accountState: string = 'unknown';
  @State private historyLoading: boolean = false;
  @State private historyEmpty: boolean = false;
  private drawerRequest: number = 0;
  private lastSidebarSummary: string = '';
  @State private diagnosticsVisible: boolean = false;
  @State private diagnosticsRunning: boolean = false;
  @State private checks: ConnectionCheck[] = [];
  private lastFailedUrl: string = '';
  private pollId: number = -1;
  private syncingEpoch: number = -1;
  private documentReady: boolean = false;
  private navigation: number = 0;
  private pageActive: boolean = true;
  @State private lastWebEvent: string = '尚未收到页面事件';
  @State private webEvents: string[] = [];
  @State private documentHealth: string = '尚未检查';
  private main: webview.WebviewController = new webview.WebviewController();
  private popup: webview.WebviewController = new webview.WebviewController();
  private popupHandler: ControllerHandler | undefined = undefined;
  private mainDownload: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private popupDownload: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();

  aboutToAppear(): void {
    webview.WebCookieManager.putAcceptCookieEnabled(true);
    this.startPolling();
  }

  onPageShow(): void { this.pageActive = true; this.startPolling(); }

  onPageHide(): void {
    this.cancelPageTransition();
    this.pageActive = false;
    this.navigation++;
    if (this.pollId >= 0) { clearInterval(this.pollId); this.pollId = -1; }
  }

  aboutToDisappear(): void { this.onPageHide(); }

  private startPolling(): void {
    if (this.pollId < 0) {
      this.pollId = setInterval(() => { this.syncWebsite(); }, 1200);
    }
  }

  private cancelPageTransition(): void {
    this.transitionRequest++;
    if (this.transitionPoll >= 0) { clearInterval(this.transitionPoll); this.transitionPoll = -1; }
    if (this.transitionTimeout >= 0) { clearTimeout(this.transitionTimeout); this.transitionTimeout = -1; }
    if (this.transitionFinish >= 0) { clearTimeout(this.transitionFinish); this.transitionFinish = -1; }
    this.switchingPage = false;
    this.transitionOpacity = 1;
    this.transitionSlow = false;
  }

  private beginPageTransition(label: string, url: string = '', waitForDocument: boolean = false): number {
    this.cancelPageTransition();
    const request: number = this.transitionRequest;
    this.transitionLabel = label;
    this.transitionTarget = url.replace('https://chatgpt.com', '').split(/[?#]/)[0];
    this.transitionSource = this.lastSurface;
    this.transitionDocumentPending = waitForDocument;
    this.transitionStarted = Date.now();
    this.transitionStableSince = 0;
    this.transitionSignature = '';
    this.transitionStatus = 'waiting for document';
    this.switchingPage = true;
    // SPA navigation does not reliably fire onPageBegin/onPageEnd.
    this.transitionPoll = setInterval(() => { this.syncWebsite(); }, 160);
    this.transitionTimeout = setTimeout(() => {
      if (request === this.transitionRequest && this.switchingPage) {
        this.transitionSlow = true;
        hilog.info(0x0001, 'ChatWeb', 'transition wait %{public}s', this.transitionStatus);
        this.inspectDocument();
      }
    }, 10000);
    return request;
  }

  private updatePageTransition(state: WebsiteState): void {
    if (this.switchingPage && state.auth === 'signed-out') { this.cancelPageTransition(); }
    const arrived: boolean = this.transitionTarget.length > 0 ? state.route === this.transitionTarget :
      !!state.surface && state.surface !== this.transitionSource;
    this.lastSurface = state.surface || '';
    if (!this.switchingPage || this.transitionFinish >= 0) { return; }
    this.transitionStatus = 'pending=' + this.transitionDocumentPending.toString() +
      ' arrived=' + arrived.toString() + ' content=' + (!!state.contentReady).toString() +
      ' editor=' + (!!state.ready).toString();
    if (this.transitionDocumentPending || !arrived || !state.contentReady) {
      this.transitionStableSince = 0;
      this.transitionSignature = '';
      return;
    }
    // Wait for two matching adapted frames, including the native controls' layout.
    const signature: string = state.surface + '|' + this.activeSection + '|' + this.chatMode + '|' +
      this.modelName + '|' + this.effortName + '|' + this.controlsAvailable.toString();
    if (signature !== this.transitionSignature) {
      this.transitionSignature = signature;
      this.transitionStableSince = Date.now();
      return;
    }
    if (Date.now() - this.transitionStableSince < 180 || Date.now() - this.transitionStarted < 250) { return; }
    const request: number = this.transitionRequest;
    this.transitionOpacity = 0;
    this.transitionFinish = setTimeout(() => {
      if (request === this.transitionRequest) { this.cancelPageTransition(); }
    }, 200);
  }

  private async loadChatPage(url: string, label: string): Promise<void> {
    const request: number = this.beginPageTransition(label, url, true);
    this.closeDrawer();
    // Commit the opaque native cover before ArkWeb starts replacing its document.
    await new Promise<void>((resolve) => { setTimeout(resolve, 32); });
    if (request !== this.transitionRequest || !this.pageActive) { return; }
    try { this.main.loadUrl(url); }
    catch (_) { this.cancelPageTransition(); this.toast('页面未能打开，请重试'); }
  }

  private isChatDocument(): boolean {
    try {
      const url: string = this.main.getUrl();
      return /^https:\/\/chatgpt\.com\//.test(url) && !/^https:\/\/chatgpt\.com\/(?:auth|api|backend-api|login|signin|signup)(?:[/?#]|$)/i.test(url);
    } catch (_) { return false; }
  }

  private canAdapt(epoch: number): boolean {
    return this.pageActive && this.documentReady && !this.officialMode &&
      !this.popupVisible && this.navigation === epoch && this.isChatDocument();
  }

  private recordWebEvent(controller: webview.WebviewController, stage: string): void {
    let host: string = '未知页面';
    try { host = controller.getUrl().split('/')[2] || host; } catch (_) {}
    // Keep authentication query strings, form data and credentials out of logs.
    this.lastWebEvent = stage + ' · ' + host;
    this.webEvents = this.webEvents.concat([this.lastWebEvent]).slice(-20);
    hilog.info(0x0001, 'ChatWeb', 'web %{public}s host=%{public}s', stage, host);
  }

  private async inspectDocument(): Promise<void> {
    if (!this.documentReady || !this.isChatDocument() || this.popupVisible) {
      this.documentHealth = '认证期间跳过页面检查';
      return;
    }
    const epoch: number = this.navigation;
    try {
      const raw: string = await this.main.runJavaScript(DOCUMENT_HEALTH);
      if (epoch !== this.navigation) { return; }
      this.documentHealth = this.jsText(raw);
      hilog.warn(0x0001, 'ChatWeb', 'document %{public}s', this.documentHealth);
      const structure: string = this.jsText(await this.main.runJavaScript(EDITOR_DIAGNOSTICS));
      hilog.info(0x0001, 'ChatWeb', 'editor %{public}s', structure);
      if (epoch === this.navigation && this.isChatDocument()) {
        const controls: string = this.jsText(await this.main.runJavaScript(CONTROL_DIAGNOSTICS));
        hilog.info(0x0001, 'ChatWeb', 'controls %{public}s', controls);
      }
    } catch (_) { this.documentHealth = '无法读取页面结构'; }
  }

  private async syncWebsite(): Promise<void> {
    const epoch: number = this.navigation;
    if (this.syncingEpoch === epoch || this.controlSheet.length > 0 || !this.canAdapt(epoch)) { return; }
    this.syncingEpoch = epoch;
    try {
      await this.main.runJavaScript(ADAPT);
      if (!this.canAdapt(epoch)) { return; }
      const raw: string = await this.main.runJavaScript(SNAPSHOT);
      if (!this.canAdapt(epoch)) { return; }
      let decoded: string = raw;
      if (decoded.startsWith('"')) { decoded = JSON.parse(decoded) as string; }
      const state: WebsiteState = JSON.parse(decoded) as WebsiteState;
      this.composerReady = state.ready;
      this.homeReady = state.home === true;
      this.generating = state.generating;
      if (state.model) { this.modelName = state.model; }
      await this.syncControls(epoch);
      if (!this.canAdapt(epoch)) { return; }
      this.accountState = state.auth;
      this.historyEmpty = state.historyEmpty;
      // A collapsed/unmounted mobile sidebar is not an empty account or a logout.
      if (state.auth === 'signed-out') { this.chats = []; }
      else if (state.chats.length > 0 || state.historyEmpty) {
        if (JSON.stringify(this.chats) !== JSON.stringify(state.chats)) { this.chats = state.chats; }
      }
      if (this.drawerVisible) {
        const summary: string = state.auth + ' count=' + state.chats.length.toString();
        if (summary !== this.lastSidebarSummary) {
          this.lastSidebarSummary = summary;
          this.recordWebEvent(this.main, '会话列表 ' + summary);
        }
      }
      this.shellReady = true;
      this.updatePageTransition(state);
    } catch (_) {
      if (!this.canAdapt(epoch)) { return; }
      // An adapter failure must never leave an otherwise loaded page invisible.
      this.shellReady = true;
      this.composerReady = false;
      await this.main.runJavaScript(ORIGINAL).catch(() => '');
      if (this.canAdapt(epoch)) { this.cancelPageTransition(); }
    } finally { if (this.syncingEpoch === epoch) { this.syncingEpoch = -1; } }
  }

  private async syncControls(epoch: number): Promise<void> {
    if (!this.canAdapt(epoch)) { return; }
    try {
      const raw: string = this.jsText(await this.main.runJavaScript(CONTROL_STATE));
      if (!this.canAdapt(epoch)) { return; }
      const state: ControlState = JSON.parse(raw) as ControlState;
      this.chatMode = state.mode;
      this.canSwitchMode = state.canSwitch;
      this.controlsAvailable = state.available;
      if (state.model && state.mode) { this.observedModels.set(state.mode, state.model); }
      this.modelName = state.model || this.observedModels.get(state.mode) || '';
      this.effortName = state.effort || '';
    } catch (_) {}
  }

  private async changeMode(mode: string): Promise<void> {
    const epoch: number = this.navigation;
    if (this.controlBusy || !this.canAdapt(epoch)) { return; }
    this.controlBusy = true;
    this.modelName = '';
    this.effortName = '';
    try {
      const result: string = this.jsText(await this.main.runJavaScript(switchMode(mode)));
      if (!this.canAdapt(epoch)) { return; }
      if (result === 'unavailable') { this.toast('当前页面暂未提供模式切换'); return; }
      await new Promise<void>((resolve) => { setTimeout(resolve, 350); });
      if (!this.canAdapt(epoch)) { return; }
      await this.syncWebsite();
      this.recordWebEvent(this.main, '模式切换 ' + mode + ' / ' + this.chatMode);
    } finally { this.controlBusy = false; }
  }

  private async readControlPanel(epoch: number, request: number): Promise<boolean> {
    if (!this.canAdapt(epoch) || request !== this.controlRequest) { return false; }
    const raw: string = this.jsText(await this.main.runJavaScript(READ_CONTROL));
    if (!this.canAdapt(epoch) || request !== this.controlRequest) { return false; }
    const panel: ControlPanel = JSON.parse(raw) as ControlPanel;
    this.controlChoices = panel.choices;
    const model: RegExpMatchArray | null = panel.model.match(/GPT[-\s]?\d[\w. -]*?(?=\s*(?:[一-龥]|Light|Standard|Extended|Heavy|Minimal|Low|Medium|High|XHigh|Max|Ultra|$))/i);
    if (model && this.chatMode) {
      this.modelName = model[0].trim();
      this.observedModels.set(this.chatMode, this.modelName);
    }
    this.effortAvailable = panel.hasSlider && panel.max > panel.min;
    this.effortMin = panel.min;
    this.effortMax = panel.max;
    this.effortValue = panel.value;
    if (panel.effort) { this.effortName = panel.effort; }
    hilog.info(0x0001, 'ChatWeb', 'picker %{public}s choices=%{public}d slider=%{public}s value=%{public}d',
      this.controlSheet, panel.choices.length, panel.hasSlider.toString(), panel.value);
    return this.controlSheet === 'model' ? panel.choices.length > 0 : this.effortAvailable;
  }

  private async openControlPanel(kind: string): Promise<void> {
    const epoch: number = this.navigation;
    if (this.controlBusy || !this.canAdapt(epoch)) { return; }
    const request: number = ++this.controlRequest;
    this.controlSheet = kind;
    this.controlBusy = true;
    this.controlError = '';
    this.controlChoices = [];
    this.effortAvailable = false;
    try {
      const result: string = this.jsText(await this.main.runJavaScript(OPEN_CONTROL));
      if (!this.canAdapt(epoch) || request !== this.controlRequest) { return; }
      if (result === 'unavailable') { this.controlError = '当前页面暂未提供此选项'; return; }
      for (let attempt: number = 0; attempt < 8; attempt++) {
        await new Promise<void>((resolve) => { setTimeout(resolve, 180); });
        if (!this.canAdapt(epoch) || request !== this.controlRequest) { return; }
        if (kind === 'model' && attempt === 1) { await this.main.runJavaScript(OPEN_MODEL_OPTIONS); }
        if (await this.readControlPanel(epoch, request)) { return; }
      }
      this.controlError = kind === 'effort' ? '当前模式未提供思考等级' : '暂时未读取到模型，请重试';
    } catch (_) { this.controlError = '选项加载失败，请重试'; }
    finally {
      if (request === this.controlRequest) {
        this.controlBusy = false;
        if (this.canAdapt(epoch)) {
          const details: string = this.jsText(await this.main.runJavaScript(CONTROL_DIAGNOSTICS).catch(() => ''));
          hilog.info(0x0001, 'ChatWeb', 'control panel %{public}s %{public}s', kind, details);
        }
      }
    }
  }

  private async closeControlPanel(): Promise<void> {
    const epoch: number = this.navigation;
    this.controlRequest++;
    if (this.canAdapt(epoch)) {
      // The Work model menu can be nested inside the power menu.
      await this.main.runJavaScript(CLOSE_CONTROL).catch(() => '');
      await new Promise<void>((resolve) => { setTimeout(resolve, 80); });
      if (this.canAdapt(epoch)) { await this.main.runJavaScript(CLOSE_CONTROL).catch(() => ''); }
    }
    this.controlSheet = '';
    this.controlBusy = false;
    this.syncWebsite();
  }

  private async selectModel(choice: ControlChoice): Promise<void> {
    const epoch: number = this.navigation;
    if (this.controlBusy || !this.canAdapt(epoch)) { return; }
    this.controlBusy = true;
    try {
      const result: string = this.jsText(await this.main.runJavaScript(chooseControl(choice.key, choice.label)));
      if (!this.canAdapt(epoch)) { return; }
      if (result !== 'dispatched') { this.controlError = '选项已更新，请关闭后重试'; return; }
      this.recordWebEvent(this.main, '已选择模型 ' + choice.label);
      await new Promise<void>((resolve) => { setTimeout(resolve, 180); });
      if (this.canAdapt(epoch)) {
        await this.readControlPanel(epoch, this.controlRequest);
        await this.closeControlPanel();
      }
    } finally { this.controlBusy = false; }
  }

  private async adjustEffort(target: number): Promise<void> {
    const epoch: number = this.navigation;
    const request: number = this.controlRequest;
    if (this.controlBusy || !this.canAdapt(epoch) || !this.effortAvailable) { return; }
    const next: number = Math.min(this.effortMax, Math.max(this.effortMin, Math.round(target)));
    this.controlBusy = true;
    this.controlError = '';
    try {
      for (let i: number = 0; i < 16 && this.effortValue !== next; i++) {
        const before: number = this.effortValue;
        await this.main.runJavaScript(stepEffort(next > before ? 1 : -1));
        await new Promise<void>((resolve) => { setTimeout(resolve, 120); });
        if (!this.canAdapt(epoch) || request !== this.controlRequest) { return; }
        await this.readControlPanel(epoch, request);
        hilog.info(0x0001, 'ChatWeb', 'effort before=%{public}d after=%{public}d target=%{public}d', before, this.effortValue, next);
        if (this.effortValue === before) { this.controlError = '调整尚未生效，请重试'; break; }
      }
    } finally { if (request === this.controlRequest) { this.controlBusy = false; } }
  }

  private async checkEndpoint(label: string, host: string): Promise<ConnectionCheck> {
    let request: http.HttpRequest | undefined = undefined;
    let dns: string = 'DNS 未通过';
    try {
      const addresses: connection.NetAddress[] = await connection.getAddressesByName(host);
      dns = addresses.length > 0 ? 'DNS 正常' : 'DNS 无结果';
    } catch (_) {}
    try {
      request = http.createHttp();
      const response: http.HttpResponse = await request.request('https://' + host + '/', {
        method: http.RequestMethod.HEAD,
        connectTimeout: 7000,
        readTimeout: 7000,
        usingCache: false
      });
      return { label: label, host: host, result: dns + ' · HTTP ' + response.responseCode.toString() };
    } catch (e) {
      const failure: Error = e as Error;
      return { label: label, host: host, result: dns + ' · ' + (failure.message || 'HTTPS 连接失败').slice(0, 160) };
    } finally { if (request !== undefined) { request.destroy(); } }
  }

  private async diagnose(): Promise<void> {
    this.diagnosticsVisible = true;
    this.inspectDocument();
    if (this.diagnosticsRunning) { return; }
    this.diagnosticsRunning = true;
    this.checks = [];
    try {
      this.checks = await Promise.all([
        this.checkEndpoint('ChatGPT', 'chatgpt.com'),
        this.checkEndpoint('账号认证', 'auth.openai.com'),
        this.checkEndpoint('静态资源', 'cdn.oaistatic.com')
      ]);
    } finally { this.diagnosticsRunning = false; }
  }

  private retryPage(): void {
    this.error = '';
    if (this.lastFailedUrl.startsWith('https://')) {
      this.current().loadUrl(this.lastFailedUrl);
    } else { this.current().refresh(); }
  }

  private async openDrawer(): Promise<void> {
    const epoch: number = this.navigation;
    const request: number = ++this.drawerRequest;
    this.drawerVisible = true;
    this.search = '';
    this.historyLoading = this.canAdapt(epoch);
    // Native settings and cached history remain reachable while the page is offline or loading.
    if (!this.historyLoading) { return; }
    try {
      const result: string = this.jsText(await this.main.runJavaScript(OPEN_SIDEBAR));
      if (!this.canAdapt(epoch) || request !== this.drawerRequest) { return; }
      this.recordWebEvent(this.main, '打开会话栏 ' + result);
      if (result === 'not-found') {
        const controls: string = this.jsText(await this.main.runJavaScript(NAV_DIAGNOSTICS));
        hilog.info(0x0001, 'ChatWeb', 'navigation %{public}s', controls);
      }
      // History mounts/fetches asynchronously after opening the mobile sidebar.
      for (let attempt: number = 0; attempt < 20; attempt++) {
        if (!this.canAdapt(epoch) || request !== this.drawerRequest || !this.drawerVisible) { return; }
        await this.syncWebsite();
        if (this.chats.length > 0 || this.accountState === 'signed-out' || this.historyEmpty) { break; }
        await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      }
    } catch (_) {
      if (request === this.drawerRequest) { this.recordWebEvent(this.main, '会话栏读取未完成'); }
    } finally { if (request === this.drawerRequest) { this.historyLoading = false; } }
  }

  private closeDrawer(): void {
    const wasOpen: boolean = this.drawerVisible;
    this.drawerRequest++;
    this.historyLoading = false;
    this.drawerVisible = false;
    if (wasOpen && this.canAdapt(this.navigation)) {
      this.main.runJavaScript(CLOSE_SIDEBAR).catch(() => {});
    }
  }

  private newChat(): void {
    this.homeReady = false;
    this.activeSection = '会话';
    this.conversationUrl = HOME;
    this.officialMode = false;
    this.draft = '';
    this.error = '';
    this.loadChatPage(HOME, '加载中…');
  }

  private openChat(chat: Conversation): void {
    if (!/^https:\/\/chatgpt\.com\/(?:g\/[^/]+\/)?c\/[^/?#]+/.test(chat.url)) { return; }
    this.homeReady = false;
    this.activeSection = '会话';
    this.conversationUrl = chat.url;
    this.officialMode = false;
    this.draft = '';
    this.loadChatPage(chat.url, '加载会话…');
  }

  private async selectSection(section: string): Promise<void> {
    if (this.sectionBusy) { return; }
    if (section === '会话') {
      if (this.activeSection !== '会话') {
        this.activeSection = '会话';
        this.officialMode = false;
        this.loadChatPage(this.conversationUrl, '加载会话…');
      } else {
        this.closeDrawer();
      }
      return;
    }
    if (section !== 'Dot' || !this.canAdapt(this.navigation)) { return; }
    if (this.activeSection === 'Dot') { this.closeDrawer(); return; }
    this.sectionBusy = true;
    const epoch: number = this.navigation;
    const request: number = this.beginPageTransition('正在打开 Dot…');
    this.closeDrawer();
    try {
      await new Promise<void>((resolve) => { setTimeout(resolve, 32); });
      if (!this.canAdapt(epoch) || request !== this.transitionRequest) { return; }
      if (this.activeSection === '会话') { this.conversationUrl = this.main.getUrl(); }
      await this.main.runJavaScript(OPEN_SIDEBAR);
      if (!this.canAdapt(epoch) || request !== this.transitionRequest) { return; }
      let result: string = this.jsText(await this.main.runJavaScript(OPEN_DOT));
      if (result === 'unavailable') {
        await new Promise<void>((resolve) => { setTimeout(resolve, 450); });
        if (!this.canAdapt(epoch) || request !== this.transitionRequest) { return; }
        result = this.jsText(await this.main.runJavaScript(OPEN_DOT));
      }
      if (request !== this.transitionRequest) { return; }
      if (result === 'opened') {
        this.homeReady = false;
        this.activeSection = section;
        this.modelName = '';
        this.effortName = '';
        this.controlsAvailable = false;
        this.closeDrawer();
        this.officialMode = false;
        this.draft = '';
        await this.main.runJavaScript(CLOSE_SIDEBAR).catch(() => '');
        this.recordWebEvent(this.main, section + ' 入口已打开');
        setTimeout(() => { this.syncWebsite(); }, 400);
      } else {
        this.cancelPageTransition();
        await this.main.runJavaScript(CLOSE_SIDEBAR).catch(() => '');
        this.toast('当前页面尚未提供 ' + section + ' 入口');
        this.recordWebEvent(this.main, section + ' 入口 ' + result);
      }
    } catch (_) {
      if (request === this.transitionRequest) { this.cancelPageTransition(); }
      this.toast('暂时无法打开 ' + section + '，请稍后重试');
    }
    finally { this.sectionBusy = false; }
  }

  private async showOfficial(script: string = ''): Promise<void> {
    this.cancelPageTransition();
    this.observedModels.clear();
    this.homeReady = false;
    this.drawerRequest++;
    this.historyLoading = false;
    this.drawerVisible = false;
    const epoch: number = ++this.navigation;
    this.officialMode = true;
    this.composerReady = false;
    if (!this.documentReady || !this.isChatDocument()) { return; }
    await this.main.runJavaScript(ORIGINAL).catch(() => '');
    if (this.navigation !== epoch || !this.isChatDocument()) { return; }
    if (this.draft.length > 0) {
      await this.main.runJavaScript(writeDraft(this.draft)).catch(() => '');
    }
    if (this.navigation !== epoch || !this.isChatDocument()) { return; }
    if (script.length > 0) { await this.main.runJavaScript(script).catch(() => ''); }
  }

  private async finishOfficial(): Promise<void> {
    if (!this.isChatDocument() || !this.documentReady) {
      this.toast('登录尚未返回聊天页面，请先完成登录或点重试');
      return;
    }
    this.officialMode = false;
    await this.syncWebsite();
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private jsText(value: string): string {
    try { return value.startsWith('\"') ? JSON.parse(value) as string : value; } catch (_) { return value; }
  }

  private async sendDraft(): Promise<void> {
    const epoch: number = this.navigation;
    if (!this.canAdapt(epoch)) { return; }
    if (this.generating) { await this.main.runJavaScript(STOP).catch(() => ''); return; }
    if (!this.draft.trim() || this.dispatching) { return; }
    this.dispatching = true;
    try {
      const inserted: string = await this.main.runJavaScript(writeDraft(this.draft));
      if (!this.canAdapt(epoch)) { return; }
      if (this.jsText(inserted) !== 'ready') { this.toast('输入区尚未就绪，请稍后重试'); return; }
      await new Promise<void>((resolve) => { setTimeout(resolve, 180); });
      if (!this.canAdapt(epoch)) { return; }
      const receipt: string = await this.main.runJavaScript(SEND);
      if (this.jsText(receipt) === 'dispatched') {
        this.homeReady = false;
        this.draft = '';
        this.generating = true;
      } else {
        this.toast('请确认输入或登录状态');
        await this.showOfficial();
      }
    } catch (_) { this.toast('发送未完成，草稿已保留'); }
    finally { this.dispatching = false; }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private current(): webview.WebviewController {
    return this.popupVisible ? this.popup : this.main;
  }

  private back(): boolean {
    if (this.controlSheet.length > 0) { this.closeControlPanel(); return true; }
    if (this.diagnosticsVisible) { this.diagnosticsVisible = false; return true; }
    if (this.drawerVisible) { this.closeDrawer(); return true; }
    try {
      if (this.current().accessBackward()) {
        this.current().backward();
        return true;
      }
    } catch (_) {}
    if (this.popupVisible) {
      this.popupVisible = false;
      return true;
    }
    if (this.officialMode) { this.finishOfficial(); return true; }
    return false;
  }

  onBackPress(): boolean {
    return this.back();
  }

  private openBrowser(): void {
    let url: string = HOME;
    try { url = this.current().getUrl(); } catch (_) {}
    if (!url.startsWith('https://')) { url = HOME; }
    this.context().startAbility({ action: 'ohos.want.action.viewData', uri: url }).catch(() => {
      promptAction.showToast({ message: '无法打开系统浏览器' });
    });
  }

  private async chooseFile(event: OnShowFileSelectorEvent): Promise<void> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode ? 10 : 1;
      const files: string[] = await new picker.DocumentViewPicker(this.context()).select(options);
      event.result.handleFileList(files);
    } catch (_) {
      event.result.handleFileList([]);
    }
  }

  private attachDownloads(controller: webview.WebviewController,
    delegate: webview.WebDownloadDelegate): void {
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      const name: string = item.getSuggestedFileName().replace(/[\\/]/g, '_') || 'download';
      item.start(this.context().cacheDir + '/' + Date.now().toString() + '-' + name);
    });
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.saveDownload(item);
    });
    delegate.onDownloadFailed(() => {
      promptAction.showToast({ message: '下载未完成，请重试' });
    });
    controller.setDownloadDelegate(delegate);
  }

  private async saveDownload(item: webview.WebDownloadItem): Promise<void> {
    let file: fs.File | undefined = undefined;
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [item.getSuggestedFileName() || 'download'];
      const uris: string[] = await new picker.DocumentViewPicker(this.context()).save(options);
      if (uris.length === 0) { return; }
      file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
      fs.copyFileSync(item.getFullPath(), file.fd);
      promptAction.showToast({ message: '文件已保存' });
    } catch (_) {
      promptAction.showToast({ message: '未保存文件，可重新下载后选择位置' });
    } finally {
      if (file !== undefined) { fs.closeSync(file); }
      try { fs.unlinkSync(item.getFullPath()); } catch (_) {}
    }
  }

  @Builder
  private website(controller: webview.WebviewController, isPopup: boolean) {
    Web({ src: isPopup ? '' : HOME, controller: controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .mixedMode(MixedMode.None)
      .multiWindowAccess(true)
      .onControllerAttached(() => {
        if (isPopup && this.popupHandler !== undefined) {
          this.popupHandler.setWebController(this.popup);
          this.popupHandler = undefined;
        }
        this.attachDownloads(controller, isPopup ? this.popupDownload : this.mainDownload);
      })
      .onProgressChange((event: OnProgressChangeEvent) => { this.progress = event.newProgress; })
      .onPageBegin((event: OnPageBeginEvent) => {
        this.error = '';
        this.recordWebEvent(controller, '开始加载');
        if (!isPopup) {
          this.navigation++;
          this.documentReady = false;
          this.composerReady = false;
          this.homeReady = false;
          this.controlRequest++;
          this.controlSheet = '';
          this.controlBusy = false;
          this.canSwitchMode = false;
          this.controlsAvailable = false;
          this.modelName = '';
          this.effortName = '';
          if (!/^https:\/\/chatgpt\.com\//.test(event.url) || /^https:\/\/chatgpt\.com\/(?:auth|api|backend-api|login|signin|signup)(?:[/?#]|$)/i.test(event.url)) {
            this.cancelPageTransition();
            this.officialMode = true;
            this.chats = [];
            this.accountState = 'unknown';
          } else if (!this.officialMode) {
            if (!this.switchingPage) { this.beginPageTransition('加载中…', event.url); }
            this.transitionDocumentPending = false;
          }
        }
      })
      .onPageEnd(() => {
        this.recordWebEvent(controller, this.error.length > 0 ? '加载结束（有错误）' : '加载完成');
        webview.WebCookieManager.saveCookieAsync().catch(() => {});
        if (!isPopup) {
          this.documentReady = this.error.length === 0;
          this.shellReady = true;
          this.syncWebsite();
          setTimeout(() => { this.syncWebsite(); }, 400);
          setTimeout(() => { this.inspectDocument(); }, 2000);
        }
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (!event.request.isMainFrame()) {
          const host: string = event.request.getRequestUrl().split('/')[2] || '资源';
          this.recordWebEvent(controller, '资源失败 ' + host + ' ' + event.error.getErrorCode().toString());
        }
        if (event.request.isMainFrame() && event.error.getErrorCode() !== -3) {
          const target: string = event.request.getRequestUrl();
          const host: string = target.split('/')[2] || '当前页面';
          const code: number = event.error.getErrorCode();
          this.lastFailedUrl = target;
          this.shellReady = true;
          this.composerReady = false;
          if (!isPopup) { this.cancelPageTransition(); this.documentReady = false; this.navigation++; }
          this.recordWebEvent(controller, '网络错误 ' + code.toString());
          hilog.warn(0x0001, 'ChatWeb', 'main-frame failed host=%{public}s code=%{public}d', host, code);
          this.error = '无法连接 ' + host + '（' + code.toString() + '），请检查网络后重试。';
        }
      })
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
        if (!event.request.isMainFrame()) {
          const host: string = event.request.getRequestUrl().split('/')[2] || '资源';
          this.recordWebEvent(controller, '资源 HTTP ' + event.response.getResponseCode().toString() + ' ' + host);
        }
        if (event.request.isMainFrame()) {
          this.lastFailedUrl = event.request.getRequestUrl();
          const host: string = this.lastFailedUrl.split('/')[2] || '当前页面';
          const code: number = event.response.getResponseCode();
          this.shellReady = true;
          if (!isPopup) { this.cancelPageTransition(); this.documentReady = false; this.navigation++; }
          this.composerReady = false;
          this.recordWebEvent(controller, 'HTTP ' + code.toString());
          this.error = host + ' 返回 HTTP ' + code.toString() + '。';
          hilog.warn(0x0001, 'ChatWeb', 'main-frame HTTP host=%{public}s status=%{public}d', host, code);
        }
      })
      .onConsole((event: OnConsoleEvent): boolean => {
        if (event.message.getMessageLevel() === MessageLevel.Error) {
          const message: string = event.message.getMessage();
          const match: RegExpMatchArray | null = message.match(/ChunkLoadError|SyntaxError|TypeError|ReferenceError|SecurityError|ERR_[A-Z_]+|Content Security Policy|CORS|Failed to fetch|Loading chunk|dynamically imported module|Hydration|hydration/);
          // Record only known error categories, never arbitrary website console text.
          const category: string = match !== null ? match[0] : '其他脚本错误';
          const sourceHost: string = event.message.getSourceId().split('/')[2] || 'inline';
          this.recordWebEvent(controller, '脚本 ' + category + ' ' + sourceHost);
        }
        return false;
      })
      .onRenderExited((event: OnRenderExitedEvent) => {
        const reason: number = event.renderExitReason;
        this.recordWebEvent(controller, '页面进程退出 ' + reason.toString());
        if (!isPopup) { this.cancelPageTransition(); this.navigation++; this.documentReady = false; }
        this.composerReady = false;
        this.shellReady = true;
        // Do not automatically resubmit or reload a credentials form.
        this.lastFailedUrl = '';
        this.error = '页面进程已退出（' + reason.toString() + '），可点重试重新加载。';
      })
      .onRenderProcessNotResponding(() => {
        this.recordWebEvent(controller, '页面暂未响应');
      })
      .onRenderProcessResponding(() => {
        this.recordWebEvent(controller, '页面恢复响应');
      })
      .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
        this.chooseFile(event);
        return true;
      })
      .onWindowNew((event: OnWindowNewEvent) => {
        if (isPopup) {
          promptAction.showToast({ message: '请关闭当前弹窗后重试，或使用系统浏览器' });
          return;
        }
        this.popup = new webview.WebviewController();
        this.cancelPageTransition();
        this.popupHandler = event.handler;
        this.popupVisible = true;
      })
      .onWindowExit(() => { if (isPopup) { this.popupVisible = false; } })
      .width('100%')
      .height('100%')
  }

  @Builder
  private loadingCover() {
    Column({ space: 12 }) {
      LoadingProgress().width(24).height(24).color($r('sys.color.font_secondary'))
      Text(this.transitionLabel).fontSize(14).fontColor($r('sys.color.font_secondary'))
      if (this.transitionSlow) {
        Text('加载时间较长，可继续等待或查看页面')
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
        Button('查看页面').fontSize(13).backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontColor($r('sys.color.font_primary')).onClick(() => { this.showOfficial(); })
      }
    }.justifyContent(FlexAlign.Center).padding(24).width('100%').height('100%')
      .backgroundColor($r('sys.color.background_primary'))
      .opacity(this.transitionOpacity)
      .animation({ duration: this.transitionOpacity === 0 ? 180 : 0, curve: Curve.EaseOut })
  }

  @Builder
  private icon(name: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Image(name).width(21).height(21)
    }.width(42).height(42).backgroundColor(Color.Transparent)
      .accessibilityText(label).onClick(action)
  }

  @Builder
  private header() {
    Row({ space: 6 }) {
      if (this.popupVisible || this.officialMode) {
        this.icon($r('app.media.ic_close'), '返回聊天', () => {
          if (this.popupVisible) { this.popupVisible = false; }
          else if (this.isChatDocument()) { this.finishOfficial(); }
          else { this.newChat(); }
        })
      } else {
        this.icon($r('app.media.ic_sidebar'), '打开侧栏', () => { this.openDrawer(); })
      }
      if (!this.popupVisible && !this.officialMode && this.activeSection === '会话') {
        Blank()
        Row({ space: 2 }) {
          this.modeButton('聊天', 'chat')
          this.modeButton('工作', 'work')
        }.padding(3).borderRadius(20).backgroundColor($r('sys.color.comp_background_tertiary'))
        Blank()
      } else {
        Text(this.popupVisible ? '账号登录' : this.activeSection === '会话' ? 'ChatGPT' : this.activeSection)
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      if (this.popupVisible || this.officialMode) {
        Button('完成').fontSize(14).fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.popupVisible = false;
            this.finishOfficial();
          })
      } else {
        this.icon($r('app.media.ic_new'), '新对话', () => { this.newChat(); })
      }
    }.height(this.compactLayout ? 48 : 52).width('100%').padding({ left: 8, right: 8 })
  }

  @Builder
  private composer() {
    Column({ space: 2 }) {
    Row() {
      Row({ space: 2 }) {
        this.icon($r('app.media.ic_add'), '添加附件', () => { this.showOfficial(OPEN_ATTACHMENTS); })
        TextArea({ text: this.draft, placeholder: '发消息…' })
          .onChange((value: string) => { this.draft = value; })
          .fontSize(16).fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .backgroundColor(Color.Transparent).padding({ top: 10, left: 2, right: 4, bottom: 10 })
          .minLines(1).maxLines(this.compactLayout ? 3 : 6, { overflowMode: MaxLinesMode.SCROLL })
          .textOverflow(TextOverflow.Clip).constraintSize({ minHeight: 42, maxHeight: this.compactLayout ? 88 : 144 })
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Stack() {
            if (this.dispatching) { LoadingProgress().width(20).height(20).color(Color.White); }
            else {
              Image(this.generating ? $r('app.media.ic_stop') : $r('app.media.ic_send'))
                .width(18).height(18)
            }
          }.width(32).height(32).borderRadius(16).backgroundColor('#191919')
            .opacity(this.draft.trim().length > 0 || this.generating ? 1 : 0.28)
        }.width(42).height(42).backgroundColor(Color.Transparent)
          .enabled(!this.dispatching && (this.draft.trim().length > 0 || this.generating))
          .accessibilityText(this.generating ? '停止生成' : '发送消息')
          .onClick(() => { this.sendDraft(); })
      }.alignItems(VerticalAlign.Bottom).padding(4).width('100%').constraintSize({ maxWidth: 720 })
        .borderRadius(25).backgroundColor($r('sys.color.comp_background_tertiary'))
    }.justifyContent(FlexAlign.Center).width('100%')
      .padding({ left: 12, right: 12, top: 6 })
      if (this.activeSection !== 'Dot' || this.controlsAvailable) {
      Row({ space: 4 }) {
        Button() {
          Text((this.modelName || '模型') + ' ⌄').fontSize(12).fontColor($r('sys.color.font_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).height(36).backgroundColor(Color.Transparent)
          .accessibilityText('选择模型').onClick(() => { this.openControlPanel('model'); })
        if (this.activeSection !== 'Dot') {
        Button() {
          Text((this.effortName || '思考等级') + ' ⌄').fontSize(12).fontColor($r('sys.color.font_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).height(36).backgroundColor(Color.Transparent)
          .accessibilityText('调整思考等级').onClick(() => { this.openControlPanel('effort'); })
        }
      }.width('100%').constraintSize({ maxWidth: 440 }).padding({ left: 12, right: 12 })
      }
    }.width('100%').padding({ bottom: this.compactLayout ? 2 : 8 })
  }

  @Builder
  private modeButton(label: string, mode: string) {
    Button(label).fontSize(14).fontWeight(this.chatMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.chatMode === mode ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.chatMode === mode ? $r('sys.color.background_primary') : Color.Transparent)
      .height(34).width(60).borderRadius(18).enabled(!this.controlBusy && !this.switchingPage && this.composerReady)
      .accessibilityText('切换到' + label).onClick(() => { this.changeMode(mode); })
  }

  @Builder
  private controlPicker() {
    Column() {
      Blank().onClick(() => { this.closeControlPanel(); })
      Column({ space: 8 }) {
        Row() {
          Text(this.controlSheet === 'model' ? '选择模型' : '思考等级').fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          this.icon($r('app.media.ic_close'), '关闭选项', () => { this.closeControlPanel(); })
        }.height(44).width('100%')
        if (this.controlBusy) { LoadingProgress().width(20).height(20); }
        if (this.controlError) {
          Text(this.controlError).fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
        }
        if (this.controlSheet === 'model') {
          List({ space: 4 }) {
            ForEach(this.controlChoices, (choice: ControlChoice) => {
              ListItem() {
                Button() {
                  Row({ space: 10 }) {
                    Text(choice.label).fontSize(15).fontColor($r('sys.color.font_primary'))
                      .maxLines(2).layoutWeight(1)
                    if (choice.selected) { Text('✓').fontSize(18).fontColor($r('sys.color.font_primary')); }
                  }.padding(12).width('100%')
                }.width('100%').constraintSize({ minHeight: 48 }).borderRadius(12)
                  .backgroundColor(choice.selected ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
                  .enabled(!this.controlBusy).onClick(() => { this.selectModel(choice); })
              }
            }, (choice: ControlChoice) => choice.key + choice.label)
          }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        } else if (this.effortAvailable) {
          Text(this.effortName || ('等级 ' + (this.effortValue - this.effortMin + 1).toString()))
            .fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Slider({ value: this.effortValue, min: this.effortMin, max: this.effortMax, step: 1 })
            .showSteps(true).width('100%').enabled(!this.controlBusy)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.adjustEffort(value); }
            })
          Row() {
            Button('减少').enabled(!this.controlBusy && this.effortValue > this.effortMin)
              .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
              .onClick(() => { this.adjustEffort(this.effortValue - 1); })
            Blank()
            Button('增加').enabled(!this.controlBusy && this.effortValue < this.effortMax)
              .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
              .onClick(() => { this.adjustEffort(this.effortValue + 1); })
          }.width('100%')
          Blank()
        } else { Blank(); }
      }.padding({ left: 20, right: 20, top: 8, bottom: 16 }).width('100%')
        .height(this.compactLayout ? '86%' : '60%').constraintSize({ maxHeight: 480, maxWidth: 640 })
        .borderRadius({ topLeft: 24, topRight: 24 }).backgroundColor($r('sys.color.background_primary'))
    }.width('100%').height('100%').backgroundColor('#55000000')
  }

  @Builder
  private diagnostics() {
    Column({ space: 20 }) {
      Row() {
        Text('连接诊断').fontSize(22).fontWeight(FontWeight.Medium)
        Blank()
        this.icon($r('app.media.ic_close'), '关闭连接诊断', () => { this.diagnosticsVisible = false; })
      }.width('100%')
      Text('检查本应用到官网、认证和资源服务的连接，不读取登录凭据。')
        .fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
      Text('最近页面事件：' + this.lastWebEvent)
        .fontSize(13).width('100%')
      Scroll() {
        Column({ space: 8 }) {
          Text(this.documentHealth).fontSize(11).width('100%').copyOption(CopyOptions.InApp)
          Text(this.webEvents.join('\n')).fontSize(11).width('100%').copyOption(CopyOptions.InApp)
        }
      }.width('100%').height(180)
      if (this.diagnosticsRunning) { LoadingProgress().width(30).height(30); }
      ForEach(this.checks, (check: ConnectionCheck) => {
        Column({ space: 8 }) {
          Text(check.label).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
          Text(check.host).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
          Text(check.result).fontSize(13).width('100%')
        }.padding(16).borderRadius(16).width('100%')
          .backgroundColor($r('sys.color.comp_background_tertiary'))
      }, (check: ConnectionCheck) => check.host)
      Text('HTTP 403 表示服务已响应但拒绝当前请求；它与 DNS 或连接失败不同。')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      Button('重新检查').enabled(!this.diagnosticsRunning)
      Blank()
    }.padding(24).width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  private navigationRow(name: string, image: Resource) {
    Button() {
      Row({ space: 12 }) {
        Image(image).width(21).height(21)
        Text(name).fontSize(16).fontWeight(this.activeSection === name ? FontWeight.Medium : FontWeight.Regular)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (this.sectionBusy && name !== '会话') { LoadingProgress().width(16).height(16); }
      }.width('100%').padding({ left: 12, right: 12 })
    }.height(44).width('100%').borderRadius(10)
      .backgroundColor(this.activeSection === name ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .accessibilityText(name).onClick(() => { this.selectSection(name); })
  }

  @Builder
  private sidebar() {
    Row() {
      Column({ space: 4 }) {
        Row() {
          Text('ChatGPT').fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Blank()
          this.icon($r('app.media.ic_sidebar'), '收起侧栏', () => { this.closeDrawer(); })
        }.width('100%').height(48).padding({ left: 12 })
        // A single scroll viewport keeps navigation from consuming the entire cover screen.
        List({ space: 4 }) {
          ListItem() {
            Button() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_new')).width(21).height(21)
                Text('新会话').fontSize(16).fontColor($r('sys.color.font_primary'))
                Blank()
              }.width('100%').padding({ left: 12, right: 12 })
            }.height(44).width('100%').borderRadius(10).backgroundColor(Color.Transparent)
              .onClick(() => { this.newChat(); })
          }
          ListItem() { this.navigationRow('会话', $r('app.media.ic_chat')); }
          ListItem() { this.navigationRow('Dot', $r('app.media.ic_dot')); }
          ListItem() {
            TextInput({ text: this.search, placeholder: '搜索会话' })
              .onChange((v: string) => { this.search = v; }).height(38).borderRadius(10).fontSize(14)
              .backgroundColor($r('sys.color.comp_background_tertiary')).margin({ top: 14, bottom: 10 })
          }
          ListItem() {
            Row() {
              Text('最近会话').fontSize(12).fontColor($r('sys.color.font_secondary'))
              Blank()
              if (this.historyLoading) { LoadingProgress().width(16).height(16); }
            }.width('100%').height(28).padding({ left: 12, right: 12 })
          }
          if (this.chats.length === 0) {
            ListItem() {
              Column({ space: 14 }) {
                if (this.historyLoading) {
                  Text('正在加载会话…').fontSize(14).fontColor($r('sys.color.font_secondary'))
                } else if (this.accountState === 'signed-out') {
                  Text('登录后可查看历史会话').fontSize(14).fontColor($r('sys.color.font_secondary'))
                  Button('登录 ChatGPT').fontColor(Color.White).backgroundColor('#191919')
                    .onClick(() => { this.showOfficial(OPEN_LOGIN); })
                } else if (this.historyEmpty) {
                  Text('暂无历史会话').fontSize(14).fontColor($r('sys.color.font_secondary'))
                } else {
                  Text('会话尚未加载').fontSize(14).fontColor($r('sys.color.font_secondary'))
                  Button('重试').fontColor($r('sys.color.font_primary'))
                    .backgroundColor($r('sys.color.comp_background_tertiary')).onClick(() => { this.openDrawer(); })
                }
              }.constraintSize({ minHeight: 120 }).padding(12).justifyContent(FlexAlign.Center).width('100%')
            }
          } else {
            ForEach(this.chats.filter((c: Conversation) => c.title.toLowerCase().includes(this.search.toLowerCase())),
              (c: Conversation) => {
                ListItem() {
                  Text(c.title).fontSize(15).fontColor($r('sys.color.font_primary'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%').padding({ top: 11, bottom: 11, left: 12, right: 12 })
                }.borderRadius(9).onClick(() => { this.openChat(c); })
              }, (c: Conversation) => c.url)
          }
          ListItem() {
            Column() {
              Divider().color($r('sys.color.comp_background_tertiary')).margin({ top: 6 })
              Button() {
                Row() {
                  Text('账号与设置').fontSize(14).fontColor($r('sys.color.font_primary'))
                  Blank()
                  Image($r('app.media.ic_more')).width(21).height(21)
                }.width('100%').padding({ left: 12, right: 12 })
              }.height(48).width('100%').backgroundColor(Color.Transparent).borderRadius(10)
                .accessibilityText('账号与设置')
                .bindMenu([
                  { value: '登录与账号', action: () => { this.showOfficial(OPEN_LOGIN); } },
                  { value: '更多功能', action: () => { this.showOfficial(); } },
                  { value: '连接诊断', action: () => { this.closeDrawer(); this.diagnose(); } },
                  { value: '重新加载', action: () => { this.closeDrawer(); this.main.refresh(); } },
                  { value: '在浏览器中打开', action: () => { this.openBrowser(); } }
                ])
            }.width('100%')
          }
        }
        .id('chat-sidebar-scroll').layoutWeight(1).width('100%')
        .listDirection(Axis.Vertical).scrollBar(BarState.Auto).clip(true)
      }.padding({ left: 12, right: 12, top: 6, bottom: 8 })
        .width('84%').constraintSize({ maxWidth: 360 }).height('100%')
        .backgroundColor($r('sys.color.background_primary')).clip(true)
      Blank().onClick(() => { this.closeDrawer(); })
    }.width('100%').height('100%').backgroundColor('#66000000')
      .transition(TransitionEffect.move(TransitionEdge.START).combine(TransitionEffect.OPACITY))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.header();
        if (this.error.length > 0) {
          Column({ space: 8 }) {
            Text(this.error).fontSize(13).fontColor('#8A3600').width('100%')
            Row({ space: 16 }) {
              Text('重试').fontSize(14).fontColor('#147D64').onClick(() => { this.retryPage(); })
              Text('连接诊断').fontSize(14).fontColor('#147D64').onClick(() => { this.diagnose(); })
            }.width('100%')
          }.padding(12).width('100%').backgroundColor('#FFF4E8')
        }
        Stack() {
          Column() {
            Stack() {
              Column() { this.website(this.main, false); }
                .visibility(this.popupVisible ? Visibility.Hidden : Visibility.Visible)
                .opacity(this.shellReady || this.officialMode || this.error.length > 0 ? 1 : 0)
                .width('100%').height('100%')
              if (this.popupVisible) { this.website(this.popup, true); }
              if (this.homeReady && this.composerReady && this.activeSection === '会话' &&
                !this.generating && !this.dispatching && !this.popupVisible && !this.officialMode && !this.error) {
                Column() {
                  Text(this.chatMode === 'work' ? '想完成什么？' : '聊点什么？').fontSize(this.compactLayout ? 22 : 28)
                    .fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
                    .maxLines(1).minFontSize(16).maxFontSize(this.compactLayout ? 22 : 28)
                }.justifyContent(FlexAlign.Center).width('100%').height('100%')
                  .backgroundColor($r('sys.color.background_primary'))
              }
              if (!this.shellReady && !this.popupVisible && !this.officialMode && !this.error) {
                Column({ space: 10 }) {
                  LoadingProgress().width(20).height(20).color($r('sys.color.font_secondary'))
                  Text('正在连接…').fontSize(12).fontColor($r('sys.color.font_secondary'))
                }
              }
            }.layoutWeight(1).width('100%')
            if (this.composerReady && !this.popupVisible && !this.officialMode) { this.composer(); }
          }.width('100%').height('100%')
          if (this.switchingPage && !this.popupVisible && !this.officialMode && !this.error) {
            this.loadingCover();
          }
        }.layoutWeight(1).width('100%')
      }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
      if (this.drawerVisible) { this.sidebar(); }
      if (this.controlSheet.length > 0) { this.controlPicker(); }
      if (this.diagnosticsVisible) { this.diagnostics(); }
    }.width('100%').height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => { this.compactLayout = Number(newArea.height) < 500; })
  }
}
