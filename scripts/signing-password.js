#!/usr/bin/env node
// 读写 build-profile.json5 里 storePassword / keyPassword 那种"DevEco 加密串"。
//
// 为什么需要它：hvigor 不接受明文口令。SignHap 阶段会调用
// DecipherUtil.decryptPwd(dirname(storeFile), storePassword, <配置文件>)，
// 而它第一件事就是拒绝长度 <32 或长度为奇数的输入（INVALID_DATA /
// INVALID_PASSWORD_LENGTH），随后按 AES-128-GCM 解密。也就是说：
//
//   * 口令必须是**密文**（hex、>=32 字符、偶数长度），明文一律报错；
//   * 解密用的密钥材料固定放在 **storeFile 所在目录的 material/{fd,ac,ce}** 里
//     —— 所以 .p12 换目录时必须把 material/ 一起搬，否则 hvigor 直接
//     报 SIGNING_FAILED_CAN_NOT_FIND_SIGNING_MATERIAL。
//
// 这两条合起来意味着：只要我们能生成密文，就能**完全绕开 DevEco Studio GUI**
// 配置发布签名（发布证书用 keytool 生成 CSR 即可，不必 DevEco）。
// 本脚本就是那个 encrypt 能力，外加 decrypt 用于找回已有口令。
//
// 算法（逐字节对齐 hvigor @ohos/hvigor-ohos-plugin/src/utils/decipher-util.js）：
//   根种子 = fd/0^fd/1^fd/2^<硬编码组件>            （各 16 字节）
//   根密钥 = PBKDF2-HmacSHA256(Buffer(根种子).toString(), ac, 10000, 16)
//   工作密钥 = AES-128-GCM-decrypt(根密钥, ce)
//   口令明文 = AES-128-GCM-decrypt(工作密钥, 密文)
//   密文格式 = | contentLen (4B 大端) | iv (12B) | 密文 | tag (16B) |
//              其中 contentLen = 密文长度 + 16（含 tag）
//   注意根种子要先过 Buffer.toString()（utf8），高字节会被替换成 U+FFFD ——
//   这里原样复刻，不能"修正"成 Buffer.from(seed)，否则结果不同。
//
// 用法：
//   node scripts/signing-password.js decrypt [--store-file <p12>] [--material-dir <dir>]
//                                            [--print | --out <file>]
//   node scripts/signing-password.js encrypt <明文口令> [--material-dir <dir>]
//
//   decrypt 默认从工程 build-profile.json5 读 storeFile/storePassword；
//   不带 --print/--out 时只报告长度与字符集，不输出明文（适合贴日志）。
//   encrypt 输出可直接粘进 build-profile.json5 的密文串。
//
// 退出码：0 成功；2 参数/材料不齐；3 解密失败。
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PROJECT_DIR = path.resolve(__dirname, '..');
const COMPONENT = new Int8Array([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);
const DIRS = ['fd', 'ac', 'ce'];

const die = (code, msg) => { console.error(msg); process.exit(code); };

const parseArgs = (argv) => {
    const opt = { _: [] };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--print') opt.print = true;
        else if (a === '--store-file') opt.storeFile = argv[++i];
        else if (a === '--material-dir') opt.materialDir = argv[++i];
        else if (a === '--out') opt.out = argv[++i];
        else opt._.push(a);
    }
    return opt;
};

const readOne = (dir) => {
    const names = fs.readdirSync(dir).filter((n) => n !== '.DS_Store');
    if (names.length !== 1) die(2, `${dir} 里应恰好 1 个文件，实际 ${names.length}`);
    return new Int8Array(fs.readFileSync(path.resolve(dir, names[0])));
};

// material/fd/ 下是 3 个子目录，每个子目录里恰好一个文件
const readComponents = (dir) => {
    const names = fs.readdirSync(dir).filter((n) => n !== '.DS_Store');
    if (names.length !== 3) die(2, `${dir} 里应恰好 3 个条目，实际 ${names.length}`);
    return names
        .sort()
        .map((n) => {
            const p = path.resolve(dir, n);
            return fs.statSync(p).isDirectory() ? readOne(p) : new Int8Array(fs.readFileSync(p));
        });
};

const xor = (a, b) => {
    if (a.byteLength !== b.byteLength) die(2, '密钥分量长度不一致（应为 16 字节）');
    const out = new Int8Array(a.byteLength);
    for (let i = 0; i < a.byteLength; i++) out[i] = a[i] ^ b[i];
    return out;
};

const gcmDecrypt = (key, msg) => {
    const contentLen = ((255 & msg[0]) << 24) | ((255 & msg[1]) << 16) | ((255 & msg[2]) << 8) | (255 & msg[3]);
    const ivLen = msg.length - 4 - contentLen;
    const d = crypto.createDecipheriv('aes-128-gcm', key, msg.slice(4, 4 + ivLen));
    d.setAuthTag(msg.slice(msg.length - 16));
    return Buffer.concat([d.update(msg.subarray(4 + ivLen, msg.length - 16)), d.final()]);
};

// contentLen 字段写的是"密文 + tag"的长度
const gcmEncrypt = (key, plaintext) => {
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-128-gcm', key, iv);
    const body = Buffer.concat([c.update(plaintext), c.final(), c.getAuthTag()]);
    const head = Buffer.alloc(4);
    head.writeUInt32BE(body.length, 0);
    return Buffer.concat([head, iv, body]);
};

const loadWorkKey = (materialDir) => {
    const m = path.resolve(materialDir, 'material');
    for (const d of DIRS) {
        if (!fs.existsSync(path.resolve(m, d))) {
            die(2, `缺少密钥材料目录：${path.resolve(m, d)}\n` +
                   '（hvigor 要求它就在 .p12 所在目录下；换目录时把 material/ 一起搬）');
        }
    }
    const parts = readComponents(path.resolve(m, DIRS[0]));
    const salt = readOne(path.resolve(m, DIRS[1]));
    let seed = xor(parts[0], parts[1]);
    seed = xor(seed, parts[2]);
    seed = xor(seed, COMPONENT);
    // 原样复刻 hvigor：先 Buffer.toString()（utf8）再喂给 pbkdf2
    const rootKey = new Int8Array(
        crypto.pbkdf2Sync(Buffer.from(seed).toString(), salt, 10000, 16, 'sha256'));
    return new Int8Array(gcmDecrypt(rootKey, readOne(path.resolve(m, DIRS[2]))));
};

const readBuildProfile = () => {
    const p = path.resolve(PROJECT_DIR, 'build-profile.json5');
    if (!fs.existsSync(p)) {
        die(2, `找不到 ${p}；在工程外使用时请用 --store-file 或 --material-dir 指定位置`);
    }
    return fs.readFileSync(p, 'utf8');
};

const configuredStoreFile = () => {
    const m = readBuildProfile().match(/"storeFile"\s*:\s*"([^"]+)"/);
    if (!m) die(2, 'build-profile.json5 里找不到 signingConfigs[].material.storeFile');
    return m[1];
};

const configuredPassword = () => {
    const m = readBuildProfile().match(/"storePassword"\s*:\s*"([0-9A-Fa-f]+)"/);
    if (!m) die(2, 'build-profile.json5 里找不到密文形式的 storePassword');
    return m[1];
};

const main = () => {
    const opt = parseArgs(process.argv.slice(2));
    const mode = opt._[0];
    // 两种模式都以工程的 signingConfigs[].material.storeFile 为默认材料位置
    const storeFile = opt.storeFile || configuredStoreFile();
    const materialDir = opt.materialDir || path.dirname(path.resolve(storeFile));
    const workKey = loadWorkKey(materialDir);

    if (mode === 'encrypt') {
        const plain = opt._[1];
        if (!plain) die(2, 'encrypt 需要明文口令作为第二个参数');
        console.log(gcmEncrypt(workKey, Buffer.from(plain, 'utf8')).toString('hex'));
        return 0;
    }

    if (mode === 'decrypt') {
        const hex = opt._[1] || configuredPassword();
        if (hex.length < 32 || hex.length % 2 !== 0) {
            die(3, `密文长度不合法（${hex.length}）：hvigor 会直接报 INVALID_DATA，` +
                   '明文口令不能直接填进 build-profile.json5');
        }
        let plain;
        try {
            plain = gcmDecrypt(workKey, Buffer.from(hex, 'hex')).toString('utf8');
        } catch (e) {
            die(3, `解密失败（${e.message}）：密文与 material/ 不配对，或密文被改动过`);
        }
        if (opt.print) {
            process.stdout.write(plain + '\n');
        } else if (opt.out) {
            fs.writeFileSync(opt.out, plain, { mode: 0o600 });
            console.log(`明文已写入 ${opt.out}（0600）`);
        } else {
            console.log(`材料目录     : ${materialDir}`);
            console.log(`密文长度     : ${hex.length}`);
            console.log(`解出明文长度 : ${plain.length}`);
            console.log(`全可打印ASCII: ${/^[\x20-\x7e]+$/.test(plain) ? 'yes' : 'no'}`);
            console.log('（想看明文请加 --print，或 --out <file>）');
        }
        return 0;
    }

    die(2, '用法：\n' +
           '  node scripts/signing-password.js decrypt [--store-file <p12>] [--print | --out <file>]\n' +
           '  node scripts/signing-password.js encrypt <明文口令> [--material-dir <dir>]');
};

process.exit(main());
