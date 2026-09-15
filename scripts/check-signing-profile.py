#!/usr/bin/env python3
# 检查 build-profile.json5 正在使用的签名 Profile（.p7b）是否与本工程对得上。
#
# 为什么需要它：受限权限（availableLevel 高于应用 APL）必须写进 Profile 的
# acls.allowed-acls。而这个列表是**烤进 p7b 文件**的 —— AGC 审批通过只改了账号侧状态，
# 手上的 p7b 不会自己变（DevEco「自动签名」还会沿用旧 Profile）。若 module.json5 声明了
# 受限权限而 Profile 里没有，**这个 HAP 一台设备都装不上**（9568289
# "install failed due to grant request permissions failed"），而且是在构建全绿之后才炸。
#
# 用法：
#   ./scripts/check-signing-profile.py                  # 读 build-profile.json5 的 default 配置
#   ./scripts/check-signing-profile.py path/to/other.p7b
#
# 退出码：0 = bundleName 一致且所有受限权限都在 ACL 白名单里；1 = 有阻塞项。
#
# 实现说明：**不需要 java / hap-sign-tool**。p7b 是 PKCS#7，签名载荷就是里面一段
# OCTET STRING，可能被 zlib 压过；这里直接遍历 DER 取出并解 JSON。工程内外那些
# `hap-sign-tool.jar` 全是 1~2 KB 的 bridge 壳，跑不起来。
import json
import pathlib
import re
import sys
import zlib

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# availableLevel 的高低。应用 APL 是 normal 时，任何更高等级的权限都要走 ACL。
LEVEL_RANK = {'normal': 0, 'system_basic': 1, 'system_core': 2}


def iter_der_primitive(buf, start, end):
    """遍历 DER，产出 (tag, content_start, content_end)。"""
    i = start
    while i < end:
        tag = buf[i]
        i += 1
        if i >= end:
            return
        length = buf[i]
        i += 1
        if length & 0x80:
            count = length & 0x7F
            length = int.from_bytes(buf[i:i + count], 'big')
            i += count
        content_end = i + length
        if tag & 0x20:  # constructed：递归下去
            yield from iter_der_primitive(buf, i, min(content_end, end))
        else:
            yield (tag, i, content_end)
        i = content_end


def extract_payload(path):
    """从 .p7b 里取出 profile 的 JSON 载荷。"""
    raw = path.read_bytes()
    best = None
    for tag, start, end in iter_der_primitive(raw, 0, len(raw)):
        if tag != 0x04:  # 只看 OCTET STRING
            continue
        blob = raw[start:end]
        candidates = [blob]
        for wbits in (15, -15, 47):  # zlib / raw deflate / auto
            try:
                candidates.append(zlib.decompress(blob, wbits))
            except Exception:
                pass
        for candidate in candidates:
            text = candidate.strip()
            if not text.startswith(b'{'):
                continue
            try:
                parsed = json.loads(text.decode('utf-8'))
            except Exception:
                continue
            if any(key in parsed for key in ('bundle-info', 'app-identifier', 'acls')):
                if best is None or len(text) > len(best[1]):
                    best = (parsed, text)
    return best[0] if best else None


def json5_field(text, pattern, what):
    match = re.search(pattern, text)
    if not match:
        raise SystemExit(f'找不到 {what}（正则 {pattern}）')
    return match.group(1)


def configured_profile():
    build_profile = (PROJECT_DIR / 'build-profile.json5').read_text()
    return pathlib.Path(json5_field(
        build_profile,
        r'"profile"\s*:\s*"([^"]+)"',
        'build-profile.json5 里的 signingConfigs[].material.profile'))


def project_bundle_name():
    app_json5 = (PROJECT_DIR / 'AppScope' / 'app.json5').read_text()
    return json5_field(app_json5, r'"bundleName"\s*:\s*"([^"]+)"', 'AppScope/app.json5 的 bundleName')


def declared_permissions():
    module_json5 = (PROJECT_DIR / 'entry' / 'src' / 'main' / 'module.json5').read_text()
    # 收尾的 `]` 缩进不超过 6 格 —— 里面的 usedScene.abilities 数组缩进更深，
    # 不加这个约束非贪婪匹配会在第一个内层 `]` 就截断（只读到第一条权限）。
    block = re.search(r'"requestPermissions"\s*:\s*\[(.*?)\n\s{0,6}\],', module_json5, re.S)
    if not block:
        return []
    return re.findall(r'"name"\s*:\s*"(ohos\.permission\.[A-Za-z0-9_]+)"', block.group(1))


def permission_levels():
    """从 SDK 的权限定义表读 availableLevel；找不到就返回空表（跳过该项检查）。"""
    candidates = sorted(PROJECT_DIR.glob('.sdk-overlay/*/toolchains/lib/PermissionDefinitions.json'))
    candidates += sorted(PROJECT_DIR.glob('.ohos-sdk/*/toolchains/lib/PermissionDefinitions.json'))
    for path in candidates:
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue
        levels = {}

        def walk(node):
            if isinstance(node, dict):
                if isinstance(node.get('name'), str) and node['name'].startswith('ohos.permission.'):
                    levels[node['name']] = node.get('availableLevel', 'normal')
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)

        walk(data)
        if levels:
            return levels, path
    return {}, None


def main():
    if len(sys.argv) > 2:
        raise SystemExit(f'用法：{sys.argv[0]} [profile.p7b]')
    profile_path = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else configured_profile()
    if not profile_path.exists():
        raise SystemExit(f'Profile 不存在：{profile_path}')

    payload = extract_payload(profile_path)
    if payload is None:
        raise SystemExit(f'解不出 profile 载荷（文件损坏或格式变了）：{profile_path}')

    bundle_info = payload.get('bundle-info', {})
    acls = set(payload.get('acls', {}).get('allowed-acls', []))
    apl = bundle_info.get('apl', 'unknown')
    expected_bundle = project_bundle_name()
    declared = declared_permissions()
    levels, levels_path = permission_levels()

    print(f'profile     : {profile_path}')
    print(f'type        : {payload.get("type")}')
    print(f'bundle-name : {bundle_info.get("bundle-name")}')
    print(f'app-ident   : {bundle_info.get("app-identifier")}')
    print(f'apl         : {apl}')
    print(f'acls        : {sorted(acls) if acls else "（空）"}')
    device_ids = payload.get('debug-info', {}).get('device-ids', [])
    print(f'device-ids  : {len(device_ids)} 个（调试 Profile 的设备白名单）')
    print(f'权限表      : {levels_path if levels_path else "未找到，跳过受限权限核对"}')
    print()

    failures = []
    if bundle_info.get('bundle-name') != expected_bundle:
        failures.append(f'bundleName 不一致：Profile={bundle_info.get("bundle-name")}，'
                        f'工程={expected_bundle}（构建会在 SignHap 报 00303074）')

    rank_apl = LEVEL_RANK.get(apl, 0)
    for name in declared:
        level = levels.get(name) if levels else None
        if level is None:
            print(f'  {name}: 未在权限表中（相对 APL={apl} 无法判定），ACL 状态 '
                  f'{"已在白名单" if name in acls else "未知"}')
            continue
        needs_acl = LEVEL_RANK.get(level, 0) > rank_apl
        if needs_acl and name not in acls:
            failures.append(f'{name}（{level} > apl {apl}）需要 ACL，但 Profile 的 '
                            f'acls.allowed-acls 里没有它 → 安装会报 9568289')
        print(f'  {name}: {level}, {"需 ACL" if needs_acl else "普通声明即可"}, '
              f'ACL {"✓" if name in acls else ("缺 ←" if needs_acl else "不需要")}')

    for name in sorted(acls):
        if name not in declared:
            print(f'  （提示）Profile 里有 {name}，但 module.json5 未声明')

    print()
    if failures:
        print('阻塞项：')
        for item in failures:
            print(f'  ✗ {item}')
        return 1
    print('✓ Profile 与工程一致，受限权限齐备。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
