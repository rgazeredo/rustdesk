from pathlib import Path
import shutil

support = Path(__file__).resolve().parent
base = Path('flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb')
for name in ('RootInput.kt', 'RootInputServer.java'):
    shutil.copyfile(support / name, base / name)

def patch(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'Expected exactly one patch target in {path}: {old[:80]}')
    path.write_text(text.replace(old, new))

patch(base / 'InputService.kt', 'get() = ctx != null', 'get() = ctx != null || RootInput.isReady')
patch(base / 'InputService.kt', '        private fun azsignSyncInputState() {', '''        fun azsignRootStateChanged() {
            azsignSyncInputState()
            MainActivity.flutterMethodChannel?.invokeMethod(
                "on_state_changed", mapOf("name" to "input", "value" to isOpen.toString()))
        }

        private fun azsignSyncInputState() {''')
patch(base / 'MainService.kt', '            when (kind) {', '''            if (RootInput.isReady) {
                RootInput.pointer(kind, mask, x, y)
                return
            }
            when (kind) {''')
patch(base / 'MainService.kt', '        InputService.ctx?.onKeyEvent(input)', '''        if (RootInput.isReady) {
            RootInput.key(input)
            return
        }
        InputService.ctx?.onKeyEvent(input)''')
patch(base / 'MainService.kt', '        InputService.azsignServerStarted()', '        InputService.azsignServerStarted()\n        RootInput.start(applicationContext)')
patch(base / 'MainService.kt', '        InputService.azsignServerStopped()', '        RootInput.stop()\n        InputService.azsignServerStopped()')
patch(base / 'MainActivity.kt', '                "stop_input" -> {', '                "stop_input" -> {\n                    RootInput.stop()')
rules = Path('flutter/android/app/proguard-rules')
rules.write_text(rules.read_text() + '\n-keep class com.carriez.flutter_hbb.RootInputServer { *; }\n')
print('AZSign MCD-125 root-input pilot applied')
