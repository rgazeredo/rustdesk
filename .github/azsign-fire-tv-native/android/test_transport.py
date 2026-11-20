"""Independent JVM HTTPS receiver fixture. No production secret or APK needed."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SUPPORT = Path(__file__).resolve().parent
JAVA = Path(os.environ.get('JAVA_HOME', '/opt/homebrew/opt/openjdk@17')) / 'bin'

class TransportTest(unittest.TestCase):
    def test_real_tls_and_hardware_policy(self):
        with tempfile.TemporaryDirectory(prefix='fire-native-test-') as folder:
            root = Path(folder)
            store = root / 'fixture.p12'
            subprocess.run([str(JAVA/'keytool'), '-genkeypair', '-alias', 'fixture', '-keyalg', 'EC', '-groupname', 'secp256r1', '-storetype', 'PKCS12', '-keystore', str(store), '-storepass', 'fixture-password', '-keypass', 'fixture-password', '-dname', 'CN=localhost', '-validity', '1', '-ext', 'SAN=IP:127.0.0.1'], check=True, capture_output=True)
            fixture = root / 'TransportTest.java'
            fixture.write_text((SUPPORT/'TransportTest.java.fixture').read_text())
            subprocess.run([str(JAVA/'javac'), '--add-modules', 'jdk.httpserver', '-d', str(root), str(SUPPORT/'FireTvTransport.java'), str(SUPPORT/'FireTvInputPolicy.java'), str(fixture)], check=True, capture_output=True)
            result = subprocess.run([str(JAVA/'java'), '--add-modules', 'jdk.httpserver', '-cp', str(root), 'com.carriez.flutter_hbb.TransportTest', str(store)], timeout=30, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Transport and hardware policy checks passed', result.stdout)

if __name__ == '__main__': unittest.main()
