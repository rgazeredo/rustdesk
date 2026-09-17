from pathlib import Path
import shutil

support = Path(__file__).resolve().parent
base = Path('flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb')

def patch(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'Expected exactly one patch target in {path}: {old[:80]}')
    path.write_text(text.replace(old, new))

shutil.copyfile(support / 'AquarioNodeClick.java', base / 'AquarioNodeClick.java')
patch(base / 'InputService.kt',
      '    private val logTag = "input service"',
      '    private val aquarioNodeClick by lazy { AquarioNodeClick(this) }\n\n    private val logTag = "input service"')
patch(base / 'InputService.kt',
      '        // left button down, was up',
      '        if (aquarioNodeClick.mouse(mask, mouseX, mouseY)) return\n\n        // left button down, was up')
patch(base / 'InputService.kt',
      '    fun onTouchInput(mask: Int, _x: Int, _y: Int) {',
      '    fun onTouchInput(mask: Int, _x: Int, _y: Int) {\n        if (aquarioNodeClick.touch(mask, _x, _y, SCREEN_INFO.scale)) return')
patch(base / 'InputService.kt',
      '    override fun onDestroy() {',
      '    override fun onDestroy() {\n        aquarioNodeClick.close()')
patch(base / 'InputService.kt',
      '    override fun onUnbind(intent: Intent?): Boolean {',
      '    override fun onUnbind(intent: Intent?): Boolean {\n        aquarioNodeClick.close()')

# Install alongside the existing APK; the pilot must not erase production app data.
patch(Path('flutter/android/app/build.gradle'),
      'applicationId "com.carriez.flutter_hbb"',
      'applicationId "com.carriez.flutter_hbb.aquariopilot"')
patch(Path('flutter/android/app/src/main/AndroidManifest.xml'),
      'android:label="RustDesk"', 'android:label="RustDesk Aquário Piloto"')
patch(Path('flutter/android/app/src/main/AndroidManifest.xml'),
      'android:label="RustDesk Input"', 'android:label="RustDesk Aquário Input"')
print('AZSign Aquario native node-click pilot applied')
