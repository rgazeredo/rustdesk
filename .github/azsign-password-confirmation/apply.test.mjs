import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, copyFileSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

test('patches the pinned RustDesk source without changing hardware hooks', { skip: !process.env.RUSTDESK_SOURCE }, () => {
  const root = mkdtempSync(join(tmpdir(), 'rustdesk-password-patch-'))
  const files = [
    'flutter/android/app/src/main/AndroidManifest.xml',
    'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt',
    'libs/hbb_common/src/config.rs', 'src/ui_interface.rs', 'flutter/lib/common.dart',
    'libs/hbb_common/src/config/permanent_password.rs',
  ]
  for (const file of files) {
    mkdirSync(dirname(join(root, file)), { recursive: true })
    copyFileSync(join(process.env.RUSTDESK_SOURCE, file), join(root, file))
  }
  const script = fileURLToPath(new URL('./apply.mjs', import.meta.url))
  execFileSync(process.execPath, [script, root])
  const rust = readFileSync(join(root, 'libs/hbb_common/src/config.rs'), 'utf8')
  assert.match(rust, /confy::load_path\(Self::file\(\)\)/)
  assert.match(rust, /local_permanent_password_storage_matches_plain\(&persisted.password/)
  const dart = readFileSync(join(root, 'flutter/lib/common.dart'), 'utf8')
  assert.match(dart, /'persisted': ok/)
  assert.ok(dart.includes("RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$').hasMatch(requestId)"))
  assert.equal(dart.split("showToast(translate(ok ? 'Successful' : 'Failed'));").length, 2)
  assert.doesNotMatch(dart, /print\("initialLink:/)
  // Applying twice must fail loudly, not duplicate hooks/provider declarations.
  assert.throws(() => execFileSync(process.execPath, [script, root], { stdio: 'pipe' }))
})
