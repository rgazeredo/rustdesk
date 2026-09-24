import { mkdtempSync, mkdirSync, copyFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
const source = resolve(process.argv[2]);
const target = mkdtempSync(join(tmpdir(), 'azsign-access-patch-'));
for (const file of ['Cargo.toml', 'libs/hbb_common/Cargo.toml', 'libs/hbb_common/src/lib.rs',
  'libs/hbb_common/src/socket_client.rs', 'libs/hbb_common/src/udp.rs', 'flutter/ndk_arm.sh',
  'flutter/android/app/src/main/AndroidManifest.xml', 'src/rendezvous_mediator.rs']) {
  mkdirSync(dirname(join(target, file)), { recursive: true });
  copyFileSync(join(source, file), join(target, file));
}
mkdirSync(join(target, 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb'), { recursive: true });
execFileSync(process.execPath, [join(import.meta.dirname, 'apply.mjs'), target], { stdio: 'inherit' });
const sockets = readFileSync(join(target, 'libs/hbb_common/src/socket_client.rs'), 'utf8');
assert.equal((sockets.match(/azsign_access::tcp/g) ?? []).length, 2);
assert.equal((sockets.match(/azsign_access::udp/g) ?? []).length, 2);
assert.match(sockets, /PoC direct UDP denied/);
const module = readFileSync(join(target, 'libs/hbb_common/src/azsign_access.rs'), 'utf8');
assert.match(module, /TLS13/);
assert.match(module, /with_client_auth_cert/);
assert.doesNotMatch(module, /dangerous\(|unwrap\(|expect\(/);
console.log(`Patch assertions passed: ${target}`);
