#!/bin/sh
# PACKAGE_FLEXIMIND=ON 时才需要：装载外部私有钩子。
#
# 为什么外部化：这个仓库是公开的，而 ON 分支要处理的是**私有工作台**的载荷 ——
# 输入文件名、目录结构、源码位置都属于不该公开的部分。所以公开侧只留"开关 + 通用逻辑"，
# 私有侧用一个不进仓库的钩子提供**数据清单**。
#
# 钩子路径：$FLEXIMIND_HOOK，默认 $PROJECT_DIR/scripts/private/fleximind-stage.sh
# （`scripts/private/` 在 .gitignore 里）。钩子必须定义：
#
#   fleximind_check_inputs            校验私有输入是否齐备；缺失时自行报错并 exit 1
#   fleximind_input_files             每行打印一个私有输入路径（供新鲜度比对用）
#   fleximind_stage_payload <raw_stage>
#                                     把载荷打进 <raw_stage>/freecad-runtime.zip
#   fleximind_payload_entries         每行打印内部包应有的 zip 条目
#   fleximind_forbidden_pattern       打印一条 ERE：命中的 zip 条目属于"已禁用、不得进包"的东西
#
# 钩子可读取调用方导出的环境变量（PROJECT_DIR、RAW_STAGE 等）。

fleximind_load_hook() {
    FLEXIMIND_HOOK="${FLEXIMIND_HOOK:-$PROJECT_DIR/scripts/private/fleximind-stage.sh}"
    if [ ! -f "$FLEXIMIND_HOOK" ]; then
        cat >&2 <<EOF
错误：PACKAGE_FLEXIMIND=ON 需要外部私有钩子，但没有找到：
  $FLEXIMIND_HOOK

这个仓库的公开版本**不包含**该钩子（它定义私有工作台的输入清单与打包逻辑）。
用 FLEXIMIND_HOOK=<路径> 指定，或把它放回默认位置。
EOF
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$FLEXIMIND_HOOK"
    for required_fn in \
        fleximind_check_inputs \
        fleximind_stage_payload \
        fleximind_input_files \
        fleximind_payload_entries \
        fleximind_forbidden_pattern; do
        if ! command -v "$required_fn" >/dev/null 2>&1; then
            echo "错误：$FLEXIMIND_HOOK 没有定义 $required_fn" >&2
            exit 1
        fi
    done
    echo "==> FlexiMind 私有钩子已装载：$FLEXIMIND_HOOK"
}
