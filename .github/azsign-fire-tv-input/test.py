import subprocess, tempfile, unittest
from pathlib import Path

PATCH = Path(__file__).with_name('apply.py')
ANCHORS = """class InputService : AccessibilityService() {
        if (aquarioNodeClick.mouse(mask, mouseX, mouseY)) return
        if (aquarioNodeClick.touch(mask, _x, _y, SCREEN_INFO.scale)) return
        setServiceInfo(info)
                    if (AzsignDpadNavigation.handle(this@InputService, event)) return@post
        aquarioNodeClick.close()
        aquarioNodeClick.close()
"""
class PatchTest(unittest.TestCase):
    def fixture(self, root, text=ANCHORS):
        p = Path(root)/'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/InputService.kt'
        p.parent.mkdir(parents=True)
        p.write_text(text)
        return p
    def apply(self, root):
        return subprocess.run(['python3', str(PATCH), str(root)], capture_output=True)
    def test_both_input_paths_and_lifecycle_are_patched(self):
        with tempfile.TemporaryDirectory() as root:
            p = self.fixture(root)
            self.assertEqual(self.apply(root).returncode, 0)
            s = p.read_text()
            self.assertEqual(s.count('fireTvNodeClick.close()'), 2)
            self.assertIn('fireTvNodeClick.mouse', s)
            self.assertIn('fireTvNodeClick.touch', s)
            self.assertIn('TYPE_WINDOW_CONTENT_CHANGED', s)
            self.assertIn('if (FireTvNodeClick.isTarget())', s)
            self.assertTrue(p.with_name('FireTvNodeClick.java').exists())
            self.assertNotEqual(self.apply(root).returncode, 0)
    def test_divergence_fails_without_partial_edit(self):
        with tempfile.TemporaryDirectory() as root:
            initial = ANCHORS.replace('aquarioNodeClick.close()', 'somethingElse()')
            p = self.fixture(root, initial)
            self.assertNotEqual(self.apply(root).returncode, 0)
            self.assertEqual(p.read_text(), initial)
            self.assertFalse(p.with_name('FireTvNodeClick.java').exists())
if __name__ == '__main__': unittest.main()
