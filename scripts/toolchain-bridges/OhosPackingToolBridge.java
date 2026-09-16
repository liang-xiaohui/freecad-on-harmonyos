/*
 * app_packing_tool.jar 的桥接壳（见本目录 README.md）。
 *
 * 背景：hvigor 打包时用 `java -jar <SDK>/toolchains/lib/app_packing_tool.jar <args...>` 调打包工具；
 * 而 OpenHarmony 官方发布的 Public SDK（windows_linux-public）里**没有**这个 jar，只有等价的
 * 本机可执行文件 `<SDK>/toolchains/lib/ohos_packing_tool`。于是需要一个薄壳把 jar 调用转成
 * 对那个可执行文件的调用，否则 hvigor 会直接报找不到打包工具。
 *
 * 语义（逐条对应调用方）：
 *   - 目标可执行文件从环境变量 OHOS_PACKING_TOOL 取；缺失即抛异常，不做任何猜测；
 *   - 子命令固定为 `pack`（与 ohos_packing_tool 的 CLI 一致），再接 hvigor 传来的原始参数；
 *   - inheritIO()：打包工具的 stdout/stderr 直接接到 hvigor 的终端，否则进度与报错全丢；
 *   - 退出码原样透传（非 0 时 System.exit），让 hvigor 能据实判失败。
 *
 * 编译与安装：./build.sh，或工程根的 `sh scripts/switch-ohos-sdk.sh <SDK 根目录>`。
 */
import java.io.IOException;

public final class OhosPackingToolBridge {

    private OhosPackingToolBridge() {
    }

    public static void main(String[] args) throws IOException, InterruptedException {
        String tool = System.getenv("OHOS_PACKING_TOOL");
        if (tool == null || tool.isEmpty()) {
            throw new IllegalStateException("OHOS_PACKING_TOOL is not set");
        }

        String[] command = new String[args.length + 2];
        command[0] = tool;
        command[1] = "pack";
        System.arraycopy(args, 0, command, 2, args.length);

        Process process = new ProcessBuilder(command).inheritIO().start();
        int exitCode = process.waitFor();
        if (exitCode != 0) {
            System.exit(exitCode);
        }
    }
}
