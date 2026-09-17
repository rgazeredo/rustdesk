from pathlib import Path
import shutil

support = Path(__file__).resolve().parent
base = Path('flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb')

def patch(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'Expected one patch target in {path}: {old[:80]}')
    path.write_text(text.replace(old, new))

shutil.copyfile(support / 'SmartProAccessibility.java', base / 'SmartProAccessibility.java')
patch(Path('flutter/android/app/src/main/AndroidManifest.xml'),
      '    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />',
      '    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />\n'
      '    <uses-permission android:name="android.permission.WRITE_SECURE_SETTINGS" />')
patch(base / 'MainService.kt', '        InputService.azsignServerStarted()',
      '        InputService.azsignServerStarted()\n        SmartProAccessibility.start(applicationContext)')
patch(base / 'MainService.kt', '        InputService.azsignServerStopped()',
      '        SmartProAccessibility.stop()\n        InputService.azsignServerStopped()')
patch(base / 'MainActivity.kt', '                "stop_input" -> {',
      '                "stop_input" -> {\n                    SmartProAccessibility.setManuallyDisabled(context, true)')
patch(base / 'MainActivity.kt', '                        startAction(context, call.arguments as String)',
      '                        if (call.arguments == android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS) {\n'
      '                            SmartProAccessibility.setManuallyDisabled(context, false)\n'
      '                            if (MainService.isReady) SmartProAccessibility.start(context)\n'
      '                        }\n'
      '                        startAction(context, call.arguments as String)')
print('AZSign SmartPro accessibility recovery applied (permission opt-in, Android 10 only)')
