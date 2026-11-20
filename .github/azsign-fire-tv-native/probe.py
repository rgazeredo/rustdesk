"""Bounded native Fire TV protocol probe. No ADB; credentials stay in owner-only state."""
import argparse
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import ssl
import sys
import urllib.request

KEYS = {'up': 'dpad_up', 'down': 'dpad_down', 'left': 'dpad_left', 'right': 'dpad_right', 'enter': 'select', 'home': 'home', 'back': 'back'}


def private_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(data)
    os.chmod(path, 0o600)


class NativeRemote:
    def __init__(self, host, state):
        self.host = str(ipaddress.ip_address(host))
        self.state = Path(state)
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.state, 0o700)
        self.cert = self.state / 'receiver.pem'
        self.credentials = self.state / 'credentials.json'

    def activate(self):
        request = urllib.request.Request(f'http://{self.host}:8009/apps/FireTVRemote', data=b'', method='POST')
        with urllib.request.urlopen(request, timeout=8) as response:
            if response.status != 201:
                raise RuntimeError('Native remote activation failed')
        print('Native remote activation accepted.', flush=True)

    def trust_receiver(self):
        if not self.cert.exists():
            # First-use public certificate bootstrap over the user-authorized VPN endpoint.
            # No PIN/token is sent during bootstrap. Subsequent requests pin this exact certificate.
            pem = ssl.get_server_certificate((self.host, 8080), timeout=8)
            private_write(self.cert, pem)
        pem = self.cert.read_text()
        self.fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).digest()
        context = ssl.create_default_context(cafile=str(self.cert))
        context.check_hostname = False  # Embedded receiver certificate is identified by the exact pin instead of DNS.
        context.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        self.context = context

    def request(self, path, body=None, authenticated=False, method=None):
        connection = http.client.HTTPSConnection(self.host, 8080, timeout=8, context=self.context)
        try:
            connection.connect()
            if hashlib.sha256(connection.sock.getpeercert(binary_form=True)).digest() != self.fingerprint:
                raise RuntimeError('Receiver certificate changed; request refused')
            headers = {'Content-Type': 'application/json; charset=utf-8', 'x-api-key': '0987654321'}
            if authenticated:
                saved = json.loads(self.credentials.read_text())
                if saved.get('host') != self.host:
                    raise RuntimeError('Credential belongs to a different receiver')
                headers['x-client-token'] = saved['clientToken']
            connection.request(method or ('POST' if body is not None else 'GET'), path, body=None if body is None else json.dumps(body).encode(), headers=headers)
            response = connection.getresponse()
            data = response.read(65537)
            if len(data) > 65536:
                raise RuntimeError('Oversized native response')
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f'Native remote HTTP {response.status}')
            parsed = json.loads(data) if data else {}
            if not isinstance(parsed, dict):
                raise RuntimeError('Invalid native response')
            return parsed
        finally:
            connection.close()

    def pair(self, pin):
        if len(pin) != 4 or not pin.isascii() or not pin.isdigit():
            raise RuntimeError('Expected a four-digit pairing PIN')
        result = self.request('/v1/FireTV/pin/verify', {'pin': pin})
        token = result.get('description')
        if not isinstance(token, str) or not token or len(token) > 4096 or not token.isprintable():
            raise RuntimeError('Pairing not accepted; credentials not saved')
        private_write(self.credentials, json.dumps({'host': self.host, 'clientToken': token}) + '\n')
        print('Native PIN pairing accepted. Token saved privately; not printed.', flush=True)

    def press(self, key):
        action = KEYS[key]
        for phase in (['keyDown', 'keyUp'] if key not in ['home', 'back'] else [None]):
            self.request('/v1/FireTV?action=' + action, None if phase is None else {'keyActionType': phase}, authenticated=True, method='POST')
        print('Native key accepted: ' + key, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('host')
    parser.add_argument('state')
    parser.add_argument('command', choices=['activate', 'start', 'pair', 'status', *KEYS])
    args = parser.parse_args()
    remote = NativeRemote(args.host, args.state)
    if args.command == 'activate':
        remote.activate()
        return
    remote.trust_receiver()
    if args.command == 'start':
        result = remote.request('/v1/FireTV/pin/display', {'friendlyName': 'AZSign Remote - teste nativo'})
        if result.get('description') != 'OK':
            raise RuntimeError('Receiver did not confirm PIN display')
        print('TV accepted PIN display request.', flush=True)
    elif args.command == 'pair':
        remote.pair(sys.stdin.readline().strip())
    elif args.command == 'status':
        result = remote.request('/v1/FireTV/status', authenticated=True)
        print('Native authenticated status valid: ' + str(all(isinstance(result.get(k), str) for k in ['osVersion', 'platformType', 'turnstileVersion'])))
    else:
        remote.press(args.command)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, http.client.HTTPException) as error:
        # Never echo HTTP bodies, PINs, tokens or raw exception details.
        print('Native probe failed: ' + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
