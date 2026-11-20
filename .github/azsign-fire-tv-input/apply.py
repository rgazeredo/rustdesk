from pathlib import Path
import sys, shutil
root = Path(sys.argv[1])
base = root / 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb'
p = base / 'InputService.kt'
s = p.read_text()
if 'FireTvNodeClick' in s:
    raise SystemExit('Fire TV input patch already applied')
def replace_once(old, new):
    global s
    if s.count(old) != 1:
        raise SystemExit('Expected exactly one anchor: ' + old)
    s = s.replace(old, new)
replace_once('class InputService : AccessibilityService() {', 'class InputService : AccessibilityService() {\n    private val fireTvNodeClick by lazy { FireTvNodeClick(this) }')
replace_once('        if (aquarioNodeClick.mouse(mask, mouseX, mouseY)) return', '        if (fireTvNodeClick.mouse(mask, mouseX, mouseY)) return\n        if (aquarioNodeClick.mouse(mask, mouseX, mouseY)) return')
replace_once('        if (aquarioNodeClick.touch(mask, _x, _y, SCREEN_INFO.scale)) return', '        if (fireTvNodeClick.touch(mask, _x, _y, SCREEN_INFO.scale)) return\n        if (aquarioNodeClick.touch(mask, _x, _y, SCREEN_INFO.scale)) return')
replace_once('        setServiceInfo(info)', """        if (FireTvNodeClick.isTarget()) {
            info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_VIEW_FOCUSED or AccessibilityEvent.TYPE_WINDOWS_CHANGED
            info.flags = info.flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
        }
        setServiceInfo(info)""")
replace_once('                    if (AzsignDpadNavigation.handle(this@InputService, event)) return@post', '                    if (FireTvNodeClick.isTarget()) rootInActiveWindow?.refresh()\n                    if (AzsignDpadNavigation.handle(this@InputService, event)) return@post')
# Reuse the established service lifecycle; cancel any pending click callbacks.
if s.count('        aquarioNodeClick.close()') != 2:
    raise SystemExit('Expected both lifecycle cleanup hooks')
s = s.replace('        aquarioNodeClick.close()', '        fireTvNodeClick.close()\n        aquarioNodeClick.close()')
p.write_text(s)
shutil.copy2(Path(__file__).with_name('FireTvNodeClick.java'), base / 'FireTvNodeClick.java')
