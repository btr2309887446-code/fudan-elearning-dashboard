import { createHash } from 'node:crypto';
import { createReadStream, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { execFileSync } from 'node:child_process';
const [folder, platform] = process.argv.slice(2);
const sha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const version = platform === 'ios'
  ? readFileSync('flutter_app/ios/NativeRunner.xcodeproj/project.pbxproj', 'utf8').match(/MARKETING_VERSION = ([^;]+);/)[1]
  : JSON.parse(readFileSync('package.json', 'utf8')).version;
const files = [];
for (const name of readdirSync(folder).filter(n => /\.(exe|ipa|zip)$/.test(n))) {
  const hash = createHash('sha256'); let bytes = 0;
  for await (const chunk of createReadStream(join(folder, name))) { hash.update(chunk); bytes += chunk.length; }
  files.push({ name: basename(name), bytes, sha256: hash.digest('hex') });
}
if (!files.length) throw Error('No installable artifacts');
writeFileSync(join(folder, `${platform}-manifest.json`), JSON.stringify({ platform, version, source: sha, files }, null, 2) + '\n');
writeFileSync(join(folder, `${platform}-SHA256SUMS.txt`), files.map(f => `${f.sha256}  ${f.name}`).join('\n') + '\n');
