import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
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

interface StartupSplashSpec {
  widthVp: number;
  heightVp: number;
}

// Qt cannot host the system paste widget, so FreeCAD reaches the pasteboard
// through the native pasteboard API. That API is gated behind this restricted
// permission; see requestPasteboardPermission().
const READ_PASTEBOARD_PERMISSION: Permissions = 'ohos.permission.READ_PASTEBOARD';

// JSON.stringify() renders a BusinessError as "{}", because its name/message are
// non-enumerable. Native setup failures are reported through napi_throw_error,
// so surfacing .message is the only way to see what went wrong.
function describeError(error: Object): string {
  const candidate = error as Error;
  if (candidate !== undefined && candidate !== null && typeof candidate.message === 'string' &&
    candidate.message.length > 0) {
    return candidate.name === undefined ? candidate.message : candidate.name + ': ' + candidate.message;
  }
  return JSON.stringify(error);
}

// Logical dimensions are half of the official _2x PNG canvas. The generated
// resource adds 8 vp around every side for the expanded glass silhouette.
const STARTUP_GLASS_PADDING_VP = 8;
const STARTUP_SPLASH_SPECS: StartupSplashSpec[] = [
  { widthVp: 579, heightVp: 434 },
  { widthVp: 576, heightVp: 443 },
  { widthVp: 602, heightVp: 432 },
  { widthVp: 573, heightVp: 439 },
  { widthVp: 610, heightVp: 456 },
  { widthVp: 621, heightVp: 415 },
  { widthVp: 567.5, heightVp: 434 },
  { widthVp: 567.5, heightVp: 410 },
  { widthVp: 629, heightVp: 402 },
  { widthVp: 673, heightVp: 396 },
  { widthVp: 654, heightVp: 386 },
  { widthVp: 619, heightVp: 420 },
  { widthVp: 633, heightVp: 412 }
];

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

  // ohos.permission.READ_PASTEBOARD is a restricted permission (system_basic,
  // user_grant) that is granted through the signing Profile ACL. FreeCAD needs
  // it because its own widgets do the editing: the OHOS QPA talks to the
  // native pasteboard API (OH_Pasteboard_HasData / OH_Pasteboard_GetData) and
  // there is no system paste widget to fall back on.
  //
  // Without the grant OH_Pasteboard_HasData() returns false, the QPA then
  // reports an empty clipboard, and Ctrl+V replaces the selection with
  // nothing -- silently, with no error anywhere. So ask for it once at startup
  // instead of leaving the user to discover that paste appears to be broken.
  //
  // On PC/2in1 the system grants the first request without showing a dialog
  // (the user can still revoke it in Settings > Privacy); on phone/tablet this
  // would raise the normal permission dialog, which is why the call is written
  // as a real request rather than a silent assumption.
  private async requestPasteboardPermission(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = (this.context as common.UIAbilityContext).applicationInfo.accessTokenId;
      const state = atManager.checkAccessTokenSync(tokenId, READ_PASTEBOARD_PERMISSION);
      if (state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: READ_PASTEBOARD already granted');
        return;
      }
      const result = await atManager.requestPermissionsFromUser(this.context, [READ_PASTEBOARD_PERMISSION]);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'QAbility: READ_PASTEBOARD requested -> authResults=' + JSON.stringify(result.authResults));
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG,
        'QAbility: READ_PASTEBOARD request FAILED: ' + describeError(e));
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
      const splashIndex = Math.floor(Math.random() * STARTUP_SPLASH_SPECS.length);
      const splashSpec = STARTUP_SPLASH_SPECS[splashIndex];
      AppStorage.setOrCreate<number>('freecadSplashIndex', splashIndex);
      const desiredSplashWidth = vp2px(splashSpec.widthVp + STARTUP_GLASS_PADDING_VP * 2);
      const desiredSplashHeight = vp2px(splashSpec.heightVp + STARTUP_GLASS_PADDING_VP * 2);
      const splashScale = Math.min(1,
        this.displayWidth * 0.8 / desiredSplashWidth,
        this.displayHeight * 0.8 / desiredSplashHeight);
      const splashWidth = Math.round(desiredSplashWidth * splashScale);
      const splashHeight = Math.round(desiredSplashHeight * splashScale);
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
        `QAbility: startup splash variant=${splashIndex}` +
        ` display=${this.displayWidth}x${this.displayHeight}` +
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
      try {
        // A child window gets a rectangular border shadow by default even
        // when its content is transparent. The splash silhouette comes from
        // the generated PNG alpha, so the compositor shadow must be disabled.
        this.startupSplashWindow.setWindowShadowRadius(0);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: startup splash window shadow disabled');
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot disable startup splash window shadow: ' + JSON.stringify(e));
      }
      try {
        await this.startupSplashWindow.setWindowCornerRadius(0);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: startup splash window corner radius cleared');
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'QAbility: cannot clear startup splash window corner radius: ' + JSON.stringify(e));
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
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): setupFreecadEnv FAILED: ' + describeError(e));
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
        hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): materialize FAILED: ' + describeError(e));
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): native materialize queued; Qt start deferred');
    } catch (e) {
      this.runtimeFailed = true;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): native materialize setup FAILED: ' + describeError(e));
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
    // Fire and forget: Qt must not wait for a permission answer, and on PC the
    // grant is silent anyway. Doing it here (rather than on first paste) keeps
    // the clipboard usable from the very first Ctrl+V.
    void this.requestPasteboardPermission();
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
