"""A changed upstream baseline must never leave a half-patched build tree."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SUPPORT = Path(__file__).resolve().parent
NATIVE = 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/'
BASELINE = {
    NATIVE + 'InputService.kt': '''        setServiceInfo(info)
                    if (FireTvNodeClick.isTarget()) rootInActiveWindow?.refresh()
        Log.d(logTag, "onKeyEvent $keyEvent textToCommit:$textToCommit")
''',
    NATIVE + 'MainActivity.kt': '            when (call.method) {',
    NATIVE + 'AzsignProvisioningProvider.java': '        if ("/device-id".equals(uri.getPath())) {',
    'flutter/android/app/src/main/AndroidManifest.xml': '<manifest><application></application></manifest>',
    'flutter/lib/mobile/pages/azsign_device_page.dart': '''  Map<String, dynamic> _status = {};
      final raw = await platformFFI.invokeMethod('azsign_device_status');
        _unavailable = false;
    if (model.connectStatus > 0) return 'Pronto para acesso remoto';
    final ready = !missingScreen && !missingInput && model.connectStatus > 0;
                    const SizedBox(height: 28),
                    Align(''',
}

class ApplyTest(unittest.TestCase):
    def setup_tree(self, root):
        for name, source in BASELINE.items():
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(source)
        (root/'flutter/android/app/src/main/res/xml').mkdir(parents=True)

    def run_patch(self, root):
        return subprocess.run(['python3', str(SUPPORT/'apply.py'), str(root)], capture_output=True)

    def test_upstream_drift_is_atomic_and_duplicate_application_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.setup_tree(root)
            changed = root/'flutter/lib/mobile/pages/azsign_device_page.dart'
            changed.write_text('upstream changed this file')
            before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertNotEqual(self.run_patch(root).returncode, 0)
            after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertEqual(before, after)
            changed.write_text(BASELINE[str(changed.relative_to(root))])
            self.assertEqual(self.run_patch(root).returncode, 0)
            self.assertTrue((root/NATIVE/'FireTvNativeRemote.java').exists())
            self.assertNotEqual(self.run_patch(root).returncode, 0)

if __name__ == '__main__': unittest.main()
