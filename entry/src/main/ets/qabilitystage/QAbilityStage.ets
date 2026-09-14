import AbilityStage from '@ohos.app.ability.AbilityStage';
import QAbility from '../qability/QAbility';
import QChildProcess from '../process/QChildProcess';
import QtUtils from '../qability/QtUtils';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import acceptance from 'libfreecadacceptance.so';
import {APP_LIBRARY_NAME, LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

export default class QAbilityStage extends AbilityStage {

  // setting "appArgs" overrides arguments from initial Want object
  private static appArgs?: Array<string>;

  private static setupQtApplicationCalled: boolean = false;

  // QPA consumes this as the argv passed to FreeCAD's real main(). The generic
  // startup script clears stale references to workbenches that are no longer
  // installed; product-specific workbenches are injected by their own launcher.
  public static setAppArgsFromWant(want: Want, filesDir: string): void {
    let args: Array<string> = [APP_LIBRARY_NAME, filesDir + '/freecad-home/harmonyos_startup.py'];
    let parameters = want.parameters as Record<string, Object> | undefined;
    let candidate: string | undefined = (parameters?.['designFilePath'] as string | undefined)
      ?? (parameters?.['freecadFilePath'] as string | undefined)
      ?? (parameters?.['fcstdPath'] as string | undefined);
    if (typeof candidate === 'string' && candidate.toLowerCase().endsWith('.fcstd')) {
      args.push(candidate);
    } else {
      let uri = want.uri;
      if (typeof uri === 'string' && uri.toLowerCase().endsWith('.fcstd')) {
        args.push(uri);
      }
    }
    QAbilityStage.appArgs = args;
  }

  private static initQtAppContextImpl(appContext: common.ApplicationContext, abilityClassName: string, uiExtensionMode: boolean): void {
    if (!QAbilityStage.setupQtApplicationCalled) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::initQtAppContextImpl: init with uiExtensionMode=' + uiExtensionMode);
      QAbilityStage.setupQtApplicationCalled = true;
      // QPA creates the EGL/OpenGL state before QAbility.onCreate() runs.
      // Set the HarmonyOS OpenGL wrapper mode before handing control to Qt.
      acceptance.prepareOpenGL();
      qpa.setupQtApplication({
        appContext: appContext,
        modules: QtUtils.getModulesMapForQt(),
        appName: APP_LIBRARY_NAME,
        appArgs: QAbilityStage.appArgs,
        abilityClassName: abilityClassName,
        uiExtensionMode: uiExtensionMode,
        _unusedQChildProcess: new QChildProcess(),
      });
    } else {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::initQtAppContextImpl: already initialized');
    }
  }

  public static initQtAppContextIfNeeded(appContext: common.ApplicationContext): void {
    QAbilityStage.initQtAppContextImpl(appContext, QAbility.name, false);
  }

  public static initQtAppContextInUiExtensionMode(appContext: common.ApplicationContext, abilityClassName: string): void {
    QAbilityStage.initQtAppContextImpl(appContext, abilityClassName, true);
  }

  onCreate(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onCreate()');
    // Prepare the OpenGL wrapper before any QPA lifecycle callback can create
    // an EGL context. The native constructor also sets the environment as a
    // guard for module-import ordering.
    acceptance.prepareOpenGL();
    qpa.handleAbilityStageOnCreate(this);
  }

  onNewProcessRequest(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest: want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.setAppArgsFromWant(want, this.context.getApplicationContext().filesDir);
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    let processKey: string = qpa.handleAbilityStageOnNewProcessRequest(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest: processKey: "' + processKey + '"');
    return processKey;
  }

  onAcceptWant(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant: want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.setAppArgsFromWant(want, this.context.getApplicationContext().filesDir);
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    let instanceKey: string = qpa.handleAbilityStageOnAcceptWant(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant: instanceKey: "' + instanceKey + '"');
    return instanceKey;
  }

  onDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onDestroy()');
    qpa.handleAbilityStageOnDestroy(this);
  }
}
