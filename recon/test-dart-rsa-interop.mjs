/**
 * Dart ↔ Node 的 RSA 交叉验证。
 *
 * 龙芯点在于：Node 那版实现（src/core/uis.ts）已经实测与复旦认证服务器一致，
 * 所以只要 Dart 加密的结果能被 Node 正确解密，就证明 Dart 版同样正确。
 *
 *   node recon/test-dart-rsa-interop.mjs
 */

import { execFileSync } from 'node:child_process';
import {
  constants,
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  privateDecrypt,
} from 'node:crypto';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const FLUTTER = 'D:\\flutter-sdk\\flutter\\bin\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe';
const DART = 'D:\\flutter-sdk\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe';
const APP_DIR = join(process.cwd(), 'flutter_app');

let pass = 0;
let fail = 0;
const check = (name, ok, info = '') => {
  if (ok) {
    pass++;
    console.log(`  OK   ${name}${info ? '  — ' + info : ''}`);
  } else {
    fail++;
    console.log(` FAIL  ${name}${info ? '  — ' + info : ''}`);
  }
};

const tmp = mkdtempSync(join(tmpdir(), 'dart-rsa-'));

console.log('=== Dart ↔ Node RSA/PKCS#1 v1.5 交叉验证 ===\n');
void FLUTTER;

// --- 1. 生成密钥对，交给 Dart 加密 -----------------------------------------
console.log('[1] Node 生成密钥对 → Dart 加密 → Node 解密');
{
  const { publicKey, privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'der' },
    privateKeyEncoding: { type: 'pkcs8', format: 'der' },
  });

  const pubPath = join(tmp, 'pub.txt');
  writeFileSync(pubPath, Buffer.from(publicKey).toString('base64'), 'utf8');

  // 故意用非 ASCII 与表情，检验 UTF-8 编码路径。
  const password = 'P@ssw0rd-测试-🔐';

  let stdout;
  try {
    stdout = execFileSync(DART, ['run', 'tool/rsa_probe.dart', pubPath, password], {
      cwd: APP_DIR,
      encoding: 'utf8',
      timeout: 300000,
    });
  } catch (err) {
    check('Dart 侧执行成功', false, err.message.split('\n')[0]);
    console.log(`\n=== 结果：${pass}/${pass + fail} 项通过 ===`);
    process.exit(1);
  }

  const bits = /BITS=(\d+)/.exec(stdout)?.[1];
  const cipherB64 = /CIPHER=([A-Za-z0-9+/=]+)/.exec(stdout)?.[1];

  check('Dart 解析出正确的模数位数', bits === '2048', `${bits} 位`);
  check('Dart 产出了密文', !!cipherB64, cipherB64 ? `${cipherB64.length} 个 base64 字符` : '无');

  if (cipherB64) {
    const der = Buffer.from(cipherB64, 'base64');
    check('密文长度与模数匹配', der.length === 256, `${der.length} 字节`);

    let decrypted = null;
    try {
      decrypted = privateDecrypt(
        { key: createPrivateKey({ key: Buffer.from(privateKey), format: 'der', type: 'pkcs8' }), padding: constants.RSA_PKCS1_PADDING },
        der
      ).toString('utf8');
    } catch (err) {
      console.log('       解密异常:', err.message);
    }
    check('Node 能用标准 PKCS#1 v1.5 解密 Dart 的密文', decrypted === password,
      decrypted === null ? '解密失败' : `得到「${decrypted}」`);
  }
}

// --- 2. 用复旦真实公钥 ------------------------------------------------------
console.log('\n[2] 用复旦真实公钥（3072 位）验证');
{
  let key = null;
  try {
    const res = await fetch('https://id.fudan.edu.cn/idp/authn/getJsPublicKey', { method: 'POST' });
    key = (await res.json())?.data ?? null;
  } catch (err) {
    console.log('  --   拿不到真实公钥，跳过（可能不在校园网）:', err.message);
  }

  if (key) {
    const pubPath = join(tmp, 'fudan-pub.txt');
    writeFileSync(pubPath, key, 'utf8');

    const stdout = execFileSync(DART, ['run', 'tool/rsa_probe.dart', pubPath, 'a-sample-password'], {
      cwd: APP_DIR,
      encoding: 'utf8',
      timeout: 300000,
    });

    const bits = /BITS=(\d+)/.exec(stdout)?.[1];
    const cipherB64 = /CIPHER=([A-Za-z0-9+/=]+)/.exec(stdout)?.[1];

    check('Dart 解析真实公钥', bits === '3072', `${bits} 位`);

    if (cipherB64) {
      const der = Buffer.from(cipherB64, 'base64');
      check('密文长度匹配 3072 位密钥', der.length === 384, `${der.length} 字节`);

      // 与 Node 自己的实现对比：同样输入长度下密文长度必须一致。
      const nodeCipher = (await import('node:crypto')).publicEncrypt(
        {
          key: createPublicKey({
            key: `-----BEGIN PUBLIC KEY-----\n${key.replace(/(.{64})/g, '$1\n').trim()}\n-----END PUBLIC KEY-----`,
          }),
          padding: constants.RSA_PKCS1_PADDING,
        },
        Buffer.from('a-sample-password', 'utf8')
      );
      check('与 Node 实现产出的密文长度一致', nodeCipher.length === der.length,
        `Node ${nodeCipher.length} / Dart ${der.length}`);
    }
  }
}

console.log(`\n=== 结果：${pass}/${pass + fail} 项通过 ===`);
if (fail > 0) process.exit(1);
