import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import acceptance from 'libfreecadacceptance.so';
import common from '@ohos.app.ability.common';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

export default class QAbility extends UIAbility {

  private localStorage: LocalStorage | null = null;
  private runtimeReady: boolean = false;
  private runtimeFailed: boolean = false;
  private abilityDestroyed: boolean = false;
  private qpaAbilityCreated: boolean = false;
  private pendingWant: Want | null = null;
  private pendingLaunchParam: AbilityConstant.LaunchParam | null = null;
  private pendingWindowStage: Window.WindowStage | null = null;
  private pendingWindowStageRestore: boolean = false;
  private windowStageForwarded: boolean = false;
  private foregroundRequested: boolean = false;

  private forwardWindowStageIfReady(): void {
    if (!this.runtimeReady || this.runtimeFailed || this.abilityDestroyed ||
        this.pendingWindowStage === null || this.windowStageForwarded) {
      return;
    }

    if (!this.qpaAbilityCreated) {
      if (this.pendingWant === null || this.pendingLaunchParam === null) {
        return;
      }
      qpa.handleAbilityOnCreate(this, this.pendingWant, this.pendingLaunchParam);
      this.qpaAbilityCreated = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: QPA ability created after runtime became ready');
    }

    if (this.pendingWindowStageRestore) {
      qpa.handleAbilityOnWindowStageRestore(this, this.pendingWindowStage);
    } else {
      qpa.handleAbilityOnWindowStageCreate(this, this.pendingWindowStage);
    }
    this.windowStageForwarded = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: window stage forwarded after runtime became ready');

    if (this.foregroundRequested) {
      qpa.handleAbilityOnForeground(this);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // FreeCAD uses QOpenGLWidget.  The OHOS QPA's GL backing store is the
    // supported compositor for RasterGLSurface; leaving this unset makes Qt
    // select the generic QRhi compositor, whose GLES pipeline is not usable
    // through the GL4ES compatibility layer on this device.
    const launchParameters = want.parameters as Record<string, Object>;
    launchParameters['io.qt.experimental.enableGlBackingStore'] = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): want.parameters: ' + JSON.stringify(want.parameters));
    const context = this.context as common.UIAbilityContext;
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
    // rawfile 必须在主线程通过 resourceManager 复制；实际解压由 native async work 执行。
    // window stage 暂不转交给 QPA，因此 XComponent 和 Qt main() 不会提前启动。
    try {
      acceptance.setupFreecadEnv(context.filesDir, context.resourceManager);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): setupFreecadEnv done');
    } catch (e) {
      this.runtimeFailed = true;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): setupFreecadEnv FAILED: ' + JSON.stringify(e));
      return;
    }

    QAbilityStage.setAppArgsFromWant(want, context.filesDir);
    QAbilityStage.initQtAppContextIfNeeded(context.getApplicationContext());

    try {
      acceptance.materializeFreecadRuntimeAsync(context.filesDir).then(() => {
        if (this.abilityDestroyed) {
          return;
        }
        this.runtimeReady = true;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): runtime ready');
        this.forwardWindowStageIfReady();
      }).catch((e: Error) => {
        this.runtimeFailed = true;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): materialize FAILED: ' + JSON.stringify(e));
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): native materialize queued; Qt start deferred');
    } catch (e) {
      this.runtimeFailed = true;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): native materialize setup FAILED: ' + JSON.stringify(e));
    }
  }

  onDestroy(): void | Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onDestroy()');
    this.abilityDestroyed = true;
    this.pendingWant = null;
    this.pendingLaunchParam = null;
    this.pendingWindowStage = null;
    if (!this.qpaAbilityCreated) {
      return;
    }
    return qpa.handleAbilityOnDestroy(this);
  }

  onPrepareToTerminate(): boolean {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminate()');
    if (!this.qpaAbilityCreated) {
      return false;
    }
    return qpa.handleAbilityOnPrepareToTerminate(this);
  }

  onPrepareToTerminateAsync(): Promise<boolean> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminateAsync()');
    if (!this.qpaAbilityCreated) {
      return Promise.resolve(false);
    }
    return qpa.handleAbilityOnPrepareToTerminateAsync(this);
  }

  onWindowStageCreate(windowStage: Window.WindowStage) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onWindowStageCreate(): this.launchWant.parameters: ' + JSON.stringify(this.launchWant.parameters));
    this.pendingWindowStage = windowStage;
    this.pendingWindowStageRestore = false;
    this.forwardWindowStageIfReady();
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.pendingWindowStage = windowStage;
    this.pendingWindowStageRestore = true;
    this.forwardWindowStageIfReady();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant(): want.parameters: ' + JSON.stringify(want.parameters));
    if (!this.qpaAbilityCreated) {
      this.pendingWant = want;
      this.pendingLaunchParam = launchParam;
      return;
    }
    qpa.handleAbilityOnNewWant(this, want, launchParam);
  }

  onForeground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    this.foregroundRequested = true;
    if (this.windowStageForwarded) {
      qpa.handleAbilityOnForeground(this);
    } else {
      this.forwardWindowStageIfReady();
    }
  }

  onBackground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground()');
    this.foregroundRequested = false;
    if (this.windowStageForwarded) {
      qpa.handleAbilityOnBackground(this);
    }
  }

  onWindowStageDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onStageDestroy()');
    this.pendingWindowStage = null;
    if (this.windowStageForwarded) {
      qpa.handleAbilityOnWindowStageDestroy(this);
      this.windowStageForwarded = false;
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return qpa.handleAbilityOnContinue(this, wantParam);
  }
}
