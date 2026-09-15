import { hapTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode } from '@ohos/hvigor';

// ---------------------------------------------------------------------------
// 为什么这里会有一段改 module.json5 的代码
//
// EntryAbility（ets/entryability/EntryAbility.ets）是这台设备上的无头桥：它把 want
// 参数里的 freecadJobJson 丢给 libfreecadacceptance.so 去跑 FlexiMind 作业，也跑设备侧
// 六项验收。它对上架的 GUI 包没有用处，而且留在对外包里有两个实打实的问题：
//
//   1. 它声明了 exported: true，意思是**任何应用**都能拉起它并投喂参数；
//   2. PACKAGE_FLEXIMIND=OFF（对外包的默认值）已经把载荷拿掉了 —— FlexiMind/ 不在
//      freecad-runtime.zip 里，rawfile 里也没有验收脚本 —— 于是它的作业分支只会报
//      "FlexiMind job runner is missing from the staged runtime"，是个跑不通的导出 API。
//
// 所以对外包（PACKAGE_FLEXIMIND != ON）就在构建期把这条声明从 module.json5 里去掉，
// 内部构建（PACKAGE_FLEXIMIND=ON）原样保留，设备侧验收流程不受影响。
//
// 为什么落在 hvigorfile.ts 而不是 build-profile.json5：模块级 target 的 source.abilities
// 只支持 FA 模型工程定制 Ability 下的 page 页面，管不了 Stage 模型的能力清单（见
// "模块级 build-profile.json5" 表 6）；target 的 source.sourceRoots 也只换源码目录。
// hvigor 官方给出的构建期改 module.json5 的口子就是 OhosHapContext 的
// getModuleJsonOpt()/setModuleJsonOpt() 这一对，setModuleJsonOpt 还会走一遍 schema 校验，
// 所以改错了会在构建期直接报错，而不是悄悄产出坏包。
//
// 注意：这里**不动** libfreecadacceptance.so。QAbilityStage.prepareOpenGL()、
// QAbility.setupFreecadEnv()/materializeFreecadRuntimeAsync() 都 import 它 —— 它是这台
// 设备上 GUI 自己的 NAPI 模块，不是 FlexiMind 专属件，删了 GUI 起不来。它导出的
// runJob/runAcceptance 在 ability 被剥离后就只剩一个调用方都没有的死分支。
// ---------------------------------------------------------------------------
const QUARANTINED_ABILITY = 'EntryAbility';

// 开关由 scripts/build-gui-hap-ohos.sh 归一化为 ON/OFF 后 export（默认 OFF）。这里读不到
// 就等于 OFF：DevEco 直接 Sync/Build 也走对外包的形态，免得一个手滑把无头桥传上架。
const env = ((globalThis as Record<string, unknown>).process as { env?: Record<string, string> } | undefined)?.env ?? {};
const packageFlexiMind = env.PACKAGE_FLEXIMIND === 'ON';

if (!packageFlexiMind) {
    getNode(__filename).afterNodeEvaluate((node: any) => {
        const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
        const moduleJsonOpt = hapContext.getModuleJsonOpt();
        const abilities: Array<{ name?: string }> = moduleJsonOpt?.module?.abilities ?? [];
        const kept = abilities.filter((ability) => ability?.name !== QUARANTINED_ABILITY);
        if (kept.length === abilities.length) {
            return;
        }
        moduleJsonOpt.module.abilities = kept;
        hapContext.setModuleJsonOpt(moduleJsonOpt);
        console.info(
            `[freecad] PACKAGE_FLEXIMIND is not ON: dropped the exported ${QUARANTINED_ABILITY} ` +
            `(headless bridge) from module.json5; abilities = [${kept.map((ability) => ability?.name).join(', ')}]`
        );
    });
}

export default {
  system: hapTasks,
  plugins: []
}
