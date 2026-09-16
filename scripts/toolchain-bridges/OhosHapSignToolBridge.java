/*
 * hap-sign-tool.jar 的桥接壳（见本目录 README.md）。
 *
 * 背景：hvigor 用 `java -jar <SDK>/toolchains/lib/hap-sign-tool.jar <args...>` 调签名工具；
 * OpenHarmony 官方 Public SDK 里没有这个 jar，只有等价的本机可执行文件
 * `<SDK>/toolchains/lib/hap-sign-tool`。这个薄壳负责转发。
 *
 * 语义：
 *   - 目标可执行文件从环境变量 OHOS_HAP_SIGN_TOOL 取；缺失即抛异常；
 *   - 除首参数外原样透传，inheritIO()，退出码非 0 时 System.exit 透传；
 *   - 例外：`verify-profile -inFile <p7b> -outFile <json>` 需要**改写输出**。
 *     原生工具往 -outFile 写的是**裸 Profile JSON**（顶层是 `bundle-info` 等键），
 *     而 hvigor 读这个文件时取的是 `json5Obj.content["bundle-info"]`
 *     （依据：@ohos/hvigor-ohos-plugin/src/utils/validate/validate-util.js 的
 *     getBundleNameFromP7b），即它期待 `{"content": <裸 JSON>}`。华为官方 jar 正是这么写的，
 *     原生可执行文件不是 ⇒ 这里补一层包裹。幂等：已经是 `{"content"` 开头就不再动。
 *
 * 编译与安装：./build.sh，或工程根的 `sh scripts/switch-ohos-sdk.sh <SDK 根目录>`。
 */
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;

public final class OhosHapSignToolBridge {

    private OhosHapSignToolBridge() {
    }

    public static void main(String[] args) throws IOException, InterruptedException {
        String tool = System.getenv("OHOS_HAP_SIGN_TOOL");
        if (tool == null || tool.isEmpty()) {
            throw new IllegalStateException("OHOS_HAP_SIGN_TOOL is not set");
        }

        String[] command = new String[args.length + 1];
        command[0] = tool;
        System.arraycopy(args, 0, command, 1, args.length);

        Process process = new ProcessBuilder(command).inheritIO().start();
        int exitCode = process.waitFor();

        if (exitCode == 0 && args.length > 0 && "verify-profile".equals(args[0])) {
            for (int i = 0; i + 1 < args.length; i++) {
                if ("-outFile".equals(args[i])) {
                    String content = Files.readString(Paths.get(args[i + 1])).trim();
                    if (!content.startsWith("{\"content\"")) {
                        Files.writeString(Paths.get(args[i + 1]), "{\"content\":" + content + "}");
                    }
                }
            }
        }

        if (exitCode != 0) {
            System.exit(exitCode);
        }
    }
}
