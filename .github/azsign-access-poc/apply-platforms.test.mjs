import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args]);
const files = ['Cargo.toml', 'src/core_main.rs', 'src/lib.rs', 'src/flutter.rs',
  'src/flutter_ffi.rs', 'src/server.rs', 'src/server/connection.rs', 'src/rendezvous_mediator.rs',
  'flutter/ndk_arm.sh', 'flutter/android/app/build.gradle',
  'flutter/android/app/src/main/AndroidManifest.xml',
  'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainApplication.kt'];

for (const [platform, ref, flags] of [['android', '1.4.9', []], ['desktop', 'HEAD', ['--desktop']]]) {
  test(`transport patch applies twice to the real ${platform} source tree`, t => {
    const target = mkdtempSync(join(tmpdir(), 'azsign-platform-patch-'));
    t.after(() => rmSync(target, { recursive: true, force: true }));
    const save = (path, data) => {
      mkdirSync(dirname(join(target, path)), { recursive: true });
      writeFileSync(join(target, path), data);
    };
    for (const file of files) save(file, git(root, 'show', `${ref}:${file}`));
    const submodule = git(root, 'rev-parse', `${ref}:libs/hbb_common`).toString().trim();
    for (const file of ['Cargo.toml', 'src/lib.rs', 'src/socket_client.rs', 'src/udp.rs']) {
      save(`libs/hbb_common/${file}`, git(join(root, 'libs/hbb_common'), 'show', `${submodule}:${file}`));
    }
    const apply = () => execFileSync(process.execPath, [join(import.meta.dirname, 'apply.mjs'), target, ...flags]);
    apply();
    const first = readFileSync(join(target, 'libs/hbb_common/src/lib.rs'), 'utf8');
    apply();
    assert.equal(readFileSync(join(target, 'libs/hbb_common/src/lib.rs'), 'utf8'), first);
    assert.match(readFileSync(join(target, 'src/server/connection.rs'), 'utf8'), /azsign_scope::allows_login/);
    const native = readFileSync(join(target, 'src/lib.rs'), 'utf8');
    if (platform === 'desktop') assert.match(native, /azsign_native_access_logout/);
    else assert.doesNotMatch(native, /azsign_native_access_logout/);
  });
}
