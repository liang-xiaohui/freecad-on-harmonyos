import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import acceptance from 'libfreecadacceptance.so';
import common from '@ohos.app.ability.common';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

export default class QAbility extends UIAbility {

  private localStorage: LocalStorage | null = new LocalStorage();
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
  private startupSplashReady: boolean = false;
  private mainWindow: Window.Window | null = null;
  private startupSplashWindow: Window.Window | null = null;
  private guiReadyMarkerPath: string = '';
  private guiReadyTimer: number = -1;
  private guiReadyChecks: number = 0;
  private displayWidth: number = 0;
  private displayHeight: number = 0;
  private preSplashWindowLeft: number = -1;
  private preSplashWindowTop: number = -1;
  private preSplashWindowWidth: number = 0;
  private preSplashWindowHeight: number = 0;
  // Read and updated by the downstream QPA while the ArkUI main-window host
  // page is reused for the Qt XComponent behind the separate splash window.
  public freecadStartupContentLoaded: boolean = false;
  public freecadStartupSplashActive: boolean = true;
  public freecadPendingWindowLeft: number = -1;
  public freecadPendingWindowTop: number = -1;
  public freecadPendingWindowWidth: number = 0;
  public freecadPendingWindowHeight: number = 0;

  private configureStartupWindowBackground(): void {
    try {
      this.mainWindow?.setWindowBackgroundColor('#00000000');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'QAbility: cannot configure startup window background: ' + JSON.stringify(e));
    }
  }

  private async revealMainWindow(markerReady: boolean): Promise<void> {
    this.freecadStartupSplashActive = false;
    try {
      if (this.mainWindow !== null) {
        const minMainWidth = Math.round(this.displayWidth * 0.55);
        const minMainHeight = Math.round(this.displayHeight * 0.4);
        let targetWidth = this.freecadPendingWindowWidth;
        let targetHeight = this.freecadPendingWindowHeight;
        let targetLeft = this.freecadPendingWindowLeft;
        let targetTop = this.freecadPendingWindowTop;

        // A floating startup window can be reported back to Qt as the saved
        // application geometry. Reject that splash-sized value and recover a
        // normal desktop window. The corrected rectangle will then become the
        // geometry FreeCAD persists for later launches.
        if (targetWidth < minMainWidth || targetHeight < minMainHeight) {
          if (this.preSplashWindowWidth >= minMainWidth &&
              this.preSplashWindowHeight >= minMainHeight) {
            targetWidth = this.preSplashWindowWidth;
            targetHeight = this.preSplashWindowHeight;
            targetLeft = this.preSplashWindowLeft;
            targetTop = this.preSplashWindowTop;
          } else {
            targetWidth = Math.round(this.displayWidth * 2 / 3);
            targetHeight = Math.round(this.displayHeight / 2);
            targetLeft = Math.round((this.displayWidth - targetWidth) / 2);
            targetTop = Math.round((this.displayHeight - targetHeight) / 2);
          }
        }

        if (targetWidth > 0 && targetHeight > 0) {
          hilog.info(LOG_DOMAIN, LOG_TAG,
            `QAbility: restoring main-window geometry ${targetWidth}x${targetHeight}` +
            ` at ${targetLeft},${targetTop}`);
          await this.mainWindow.resize(targetWidth, targetHeight);
          if (targetLeft >= 0 && targetTop >= 0) {
            await this.mainWindow.moveWindowToGlobal(targetLeft, targetTop);
          }
        }
        // The startup host is explicitly decor-free. Restore the normal
        // FreeCAD frame only after the full-size geometry is in place and
        // while the splash child still covers the parent. Decoration changes
        // are best-effort on HarmonyOS and must not block the reveal path.
        try {
          await this.mainWindow.setWindowDecorVisible(true);
        } catch (e) {
          hilog.warn(LOG_DOMAIN, LOG_TAG,
            'QAbility: cannot restore main-window decoration: ' + JSON.stringify(e));
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility: cannot restore main-window geometry: ' + JSON.stringify(e));
    }

    if (this.abilityDestroyed) {
      return;
    }
    if (this.localStorage !== null) {
      this.localStorage.setOrCreate('freecadGuiReady', true);
    }
    // Let ArkUI apply the XComponent translation while the splash still
    // covers the parent, then raise the already-created main window before
    // removing the only visible child window.
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 50);
    });
    if (this.mainWindow !== null) {
      try {
        await this.mainWindow.showWindow();
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: main window raised behind startup splash');
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot raise main window before splash removal: ' + JSON.stringify(e));
      }
    }
    if (this.startupSplashWindow !== null) {
      try {
        await this.startupSplashWindow.destroyWindow();
        this.startupSplashWindow = null;
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot destroy startup splash window: ' + JSON.stringify(e));
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, markerReady
      ? 'QAbility: FreeCAD GUI ready; startup transition complete'
      : 'QAbility: GUI ready marker timed out; startup transition complete');
  }

  private stopGuiReadyMonitor(): void {
    if (this.guiReadyTimer !== -1) {
      clearInterval(this.guiReadyTimer);
      this.guiReadyTimer = -1;
    }
  }

  private startGuiReadyMonitor(): void {
    this.stopGuiReadyMonitor();
    this.guiReadyChecks = 0;
    this.guiReadyTimer = setInterval(() => {
      if (this.abilityDestroyed || this.localStorage === null) {
        return;
      }

      this.guiReadyChecks++;
      let ready = false;
      try {
        ready = fs.accessSync(this.guiReadyMarkerPath);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility: GUI ready marker check failed: ' + JSON.stringify(e));
      }

      // The timeout only prevents a permanent splash if startup fails before
      // FreeCAD can publish its normal workbench-ready marker.
      if (!ready && this.guiReadyChecks < 600) {
        return;
      }
      this.stopGuiReadyMonitor();
      void this.revealMainWindow(ready);
    }, 50);
  }

  private forwardWindowStageIfReady(): void {
    if (!this.runtimeReady || this.runtimeFailed || this.abilityDestroyed ||
        this.pendingWindowStage === null || this.windowStageForwarded ||
        !this.startupSplashReady) {
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
    if (this.localStorage !== null) {
      this.localStorage.setOrCreate('freecadGuiReady', this.pendingWindowStageRestore);
      if (!this.pendingWindowStageRestore) {
        this.startGuiReadyMonitor();
      }
    }
    this.windowStageForwarded = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: window stage forwarded after runtime became ready');

    if (this.foregroundRequested) {
      qpa.handleAbilityOnForeground(this);
    }
  }

  private async loadStartupSplash(windowStage: Window.WindowStage): Promise<void> {
    this.startupSplashReady = false;
    this.freecadStartupSplashActive = true;
    this.freecadStartupContentLoaded = false;
    try {
      this.mainWindow = windowStage.getMainWindowSync();
      const windowProperties = this.mainWindow.getWindowProperties();
      const oldRect = windowProperties.windowRect;
      this.preSplashWindowLeft = oldRect.left;
      this.preSplashWindowTop = oldRect.top;
      this.preSplashWindowWidth = oldRect.width;
      this.preSplashWindowHeight = oldRect.height;

      const defaultDisplay = display.getDefaultDisplaySync();
      this.displayWidth = defaultDisplay.width;
      this.displayHeight = defaultDisplay.height;
      const splashWidth = Math.round(vp2px(568));
      const splashHeight = Math.round(vp2px(368));
      const splashLeft = Math.round((this.displayWidth - splashWidth) / 2);
      const splashTop = Math.round((this.displayHeight - splashHeight) / 2);
      // HarmonyOS requires the parent to be shown before it will create an
      // application subwindow. Match the parent to the splash exactly so its
      // compositor layer cannot appear as a second, differently sized panel
      // through the transparent shadow around the official splash image.
      const startupHostWidth = splashWidth;
      const startupHostHeight = splashHeight;
      const startupHostLeft = splashLeft;
      const startupHostTop = splashTop;
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `QAbility: startup geometry display=${this.displayWidth}x${this.displayHeight}` +
            ` original=${oldRect.left},${oldRect.top},${oldRect.width}x${oldRect.height}` +
        ` host=${startupHostLeft},${startupHostTop},${startupHostWidth}x${startupHostHeight}` +
        ` splash=${splashLeft},${splashTop},${splashWidth}x${splashHeight}`);
      await this.mainWindow.resize(startupHostWidth, startupHostHeight);
      await this.mainWindow.moveWindowToGlobal(startupHostLeft, startupHostTop);

      if (this.localStorage === null) {
        this.localStorage = new LocalStorage();
      }
      this.localStorage.setOrCreate('freecadGuiReady', false);
      await windowStage.loadContent('pages/MainWindowNativeNode', this.localStorage);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: startup host content loaded');
      this.configureStartupWindowBackground();
      await this.mainWindow.showWindow();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: startup host window shown');
      // HarmonyOS rejects this call before the first showWindow() on some
      // devices. Keep it outside the splash setup failure path: a decoration
      // failure must not suppress the official splash child.
      try {
        await this.mainWindow.setWindowDecorVisible(false);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot hide startup host decoration: ' + JSON.stringify(e));
      }
      if (this.abilityDestroyed || this.pendingWindowStage !== windowStage) {
        return;
      }
      this.freecadStartupContentLoaded = true;

      this.startupSplashWindow = await windowStage.createSubWindowWithOptions(
        'FreeCADStartupSplash', {
          title: '',
          decorEnabled: false,
          isModal: false,
          windowRect: {
            left: splashLeft,
            top: splashTop,
            width: splashWidth,
            height: splashHeight
          }
        });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: decor-free startup window created');
      await this.startupSplashWindow.setUIContent('pages/StartupSplash');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: decor-free startup content loaded');
      await this.startupSplashWindow.showWindow({ focusOnShow: false });
      try {
        this.startupSplashWindow.setWindowBackgroundColor('#00000000');
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: decor-free startup background made transparent');
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot make startup splash background transparent: ' + JSON.stringify(e));
      }
      this.startupSplashReady = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: decor-free startup splash loaded');
      this.forwardWindowStageIfReady();
    } catch (e) {
      if (this.abilityDestroyed || this.pendingWindowStage !== windowStage) {
        return;
      }
      // Do not prevent Qt from starting if the temporary ArkUI page fails.
      this.startupSplashReady = true;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility: startup splash load FAILED: ' + JSON.stringify(e));
      this.forwardWindowStageIfReady();
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
    this.guiReadyMarkerPath = context.filesDir + '/freecad-data/.gui-ready';
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
    // rawfile 必须在主线程通过 resourceManager 复制；实际解压由 native async work 执行。
    // window stage 暂不转交给 QPA，因此 XComponent 和 Qt main() 不会提前启动。
    try {
      acceptance.setupFreecadEnv(context.filesDir, context.resourceManager);
      if (fs.accessSync(this.guiReadyMarkerPath)) {
        fs.unlinkSync(this.guiReadyMarkerPath);
      }
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
    this.startupSplashReady = false;
    this.mainWindow = null;
    this.startupSplashWindow = null;
    this.stopGuiReadyMonitor();
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
    void this.loadStartupSplash(windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.pendingWindowStage = windowStage;
    this.pendingWindowStageRestore = true;
    this.startupSplashReady = true;
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
    this.startupSplashReady = false;
    this.mainWindow = null;
    this.startupSplashWindow = null;
    this.stopGuiReadyMonitor();
    if (this.windowStageForwarded) {
      qpa.handleAbilityOnWindowStageDestroy(this);
      this.windowStageForwarded = false;
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return qpa.handleAbilityOnContinue(this, wantParam);
  }
}
