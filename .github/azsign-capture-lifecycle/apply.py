"""Serialize Android frame access with capture teardown (Android 1.4.9 base)."""
from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else '.') / 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt'
source = path.read_text()
marker = '// AZSign: closing the reader also invalidates its acquired images.'
if marker in source:
    raise SystemExit(0)

start = '                    setOnImageAvailableListener({ imageReader: ImageReader ->\n'
end = '                    }, serviceHandler)'
assert source.count(start) == 1 and source.count(end) == 1
begin = source.index(start) + len(start)
finish = source.index(end, begin)
body = source[begin:finish]
replacement = (
    '                        ' + marker + '\n'
    '                        synchronized(this@MainService) {\n'
    '                            if (imageReader !== this@MainService.imageReader) return@setOnImageAvailableListener\n'
    + ''.join('    ' + line if line.strip() else line for line in body.splitlines(keepends=True))
    + '                        }\n'
)
source = source[:begin] + replacement + source[finish:]
for signature in ['    fun startCapture(): Boolean {', '    private fun updateScreenInfo(orientation: Int) {']:
    assert source.count(signature) == 1
    if '    @Synchronized\n' + signature not in source:
        source = source.replace(signature, '    @Synchronized\n' + signature)
assert '    @Synchronized\n    fun stopCapture() {' in source
path.write_text(source)
