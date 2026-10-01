/**
 * 用 GitHub Contents API 推送单个文件。
 *
 * 背景：本机到 github.com:443（git push 走这个）经常连不上，
 * 但 api.github.com 是通的。所以当 git push 失败、而改动只有一个文件时，
 * 可以用 API 直接提交，不必干等网络恢复。
 *
 * 局限：一次只能推一个文件，且会产生一个独立的提交。
 * 这只当作应急通道，网络恢复后仍应正常 git push。
 *
 *   node recon/push-file-via-api.mjs <仓库相对路径> "<提交信息>"
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const REPO = 'btr2309887446-code/fudan-elearning-dashboard';
const BRANCH = 'master';

const relPath = process.argv[2];
const message = process.argv[3] ?? `chore: 更新 ${relPath}`;

if (!relPath) {
  console.error('用法: node recon/push-file-via-api.mjs <仓库相对路径> "<提交信息>"');
  process.exit(1);
}

const abs = `D:/vit/杂/elearning/${relPath}`;
const gh = (args) => execFileSync('gh', args, { encoding: 'utf8' }).trim();

// 1) 取远程当前内容的 SHA（文件不存在时会报 404）
let sha = null;
try {
  sha = gh(['api', `repos/${REPO}/contents/${relPath}?ref=${BRANCH}`, '--jq', '.sha']);
} catch {
  console.log('远程没有这个文件，将新建');
}

// 2) 内容按 base64 送上去
const content = readFileSync(abs).toString('base64');

const args = [
  'api',
  '-X',
  'PUT',
  `repos/${REPO}/contents/${relPath}`,
  '-f',
  `message=${message}`,
  '-f',
  `content=${content}`,
  '-f',
  `branch=${BRANCH}`,
];
if (sha) args.push('-f', `sha=${sha}`);

const out = gh(args);
const parsed = JSON.parse(out);
console.log('已提交:', parsed.commit.sha.slice(0, 7));
console.log('提交信息:', parsed.commit.message.split('\n')[0]);
