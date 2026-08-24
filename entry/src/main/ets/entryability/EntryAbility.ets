import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import acceptance from 'libfreecadacceptance.so';
import common from '@ohos.app.ability.common';

const LOG_DOMAIN = 0x3202;
const LOG_TAG = 'FreeCADProbe';

/**
 * Headless bridge for FlexiMind. A caller starts EntryAbility with
 * `freecadJobJson` containing the allow-listed job request. Geometry and
 * metadata are written below filesDir/jobs/<jobId>; the same JSON is also
 * emitted to hilog for callers using the device bridge.
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void {
    const context = this.context as common.UIAbilityContext;
    const parameters = want.parameters as Record<string, Object> | undefined;
    const request = parameters?.['freecadJobJson'] as string | undefined;
    if (typeof request === 'string' && request.length > 0) {
      acceptance.runJob(context.filesDir, request, context.resourceManager).then((result: string) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'FlexiMind job result=%{public}s', result);
      }).catch((error: Error) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'FlexiMind job failed=%{public}s', JSON.stringify(error));
      });
      return;
    }
    acceptance.runAcceptance(context.filesDir, context.resourceManager).then((result: string) => {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Python acceptance result=%{public}s', result);
    }).catch((error: Error) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Headless acceptance failed=%{public}s', JSON.stringify(error));
    });
  }
}
