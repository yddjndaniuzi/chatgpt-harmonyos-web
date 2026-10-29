import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }

  onBackground(): void {
    webview.WebCookieManager.saveCookieAsync().catch(() => {});
  }
}
