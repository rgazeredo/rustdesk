import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from probe import NativeRemote


class NativeProbeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.remote = NativeRemote('127.0.0.1', self.temp.name)

    def test_pairing_saves_only_valid_token_privately_without_logging_it(self):
        self.remote.request = Mock(return_value={'description': 'synthetic-client-token'})
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.remote.pair('1234')
        self.assertNotIn('1234', output.getvalue())
        self.assertNotIn('synthetic-client-token', output.getvalue())
        self.assertEqual(os.stat(self.remote.credentials).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(self.remote.state).st_mode & 0o777, 0o700)
        self.assertEqual(json.loads(self.remote.credentials.read_text())['host'], '127.0.0.1')

    def test_bad_pin_does_not_overwrite_existing_credential(self):
        self.remote.credentials.write_text('previous-credential')
        self.remote.request = Mock(return_value={'description': ''})
        with self.assertRaises(RuntimeError): self.remote.pair('1234')
        self.assertEqual(self.remote.credentials.read_text(), 'previous-credential')
        self.remote.request.reset_mock()
        with self.assertRaises(RuntimeError): self.remote.pair('not-a-pin')
        self.remote.request.assert_not_called()

    def test_complete_press_is_serialized_down_then_up(self):
        self.remote.request = Mock(return_value={})
        with contextlib.redirect_stdout(io.StringIO()): self.remote.press('right')
        calls = self.remote.request.call_args_list
        self.assertEqual([c.args[1]['keyActionType'] for c in calls], ['keyDown', 'keyUp'])
        self.assertTrue(all(c.args[0] == '/v1/FireTV?action=dpad_right' for c in calls))
        self.assertTrue(all(c.kwargs['authenticated'] for c in calls))

    def test_changed_certificate_refuses_http_before_reading_credentials(self):
        connection = Mock()
        connection.sock.getpeercert.return_value = b'changed-certificate'
        self.remote.context = Mock()
        self.remote.fingerprint = hashlib.sha256(b'original-certificate').digest()
        with patch('probe.http.client.HTTPSConnection', return_value=connection):
            with self.assertRaises(RuntimeError):
                self.remote.request('/v1/FireTV/status', authenticated=True)
        connection.request.assert_not_called()
        connection.close.assert_called_once()


if __name__ == '__main__': unittest.main()
