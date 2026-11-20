"""QA helper: prepare TLS before keyDown so VPN handshakes do not hold a key.
The Android integration uses loopback and does not depend on this helper.
"""
import argparse
import hashlib
import http.client
import json
import sys
import time
from probe import NativeRemote, KEYS


def press(remote, key, quiet=False):
    saved = json.loads(remote.credentials.read_text())
    if saved.get('host') != remote.host:
        raise RuntimeError('Credential belongs to another receiver')
    connections = []
    try:
        for _ in range(1 if key in ('home', 'back') else 2):
            connection = http.client.HTTPSConnection(remote.host, 8080, timeout=8, context=remote.context)
            connections.append(connection)
            connection.connect()
            if hashlib.sha256(connection.sock.getpeercert(binary_form=True)).digest() != remote.fingerprint:
                raise RuntimeError('Receiver certificate changed')
        headers = {'Content-Type': 'application/json; charset=utf-8', 'x-api-key': '0987654321', 'x-client-token': saved['clientToken']}

        def send(connection, phase):
            body = b'' if phase is None else json.dumps({'keyActionType': phase}).encode()
            connection.request('POST', '/v1/FireTV?action=' + KEYS[key], body=body, headers=headers)
            response = connection.getresponse()
            if len(response.read(65537)) > 65536:
                raise RuntimeError('Oversized native response')
            if response.status < 200 or response.status >= 300:
                raise RuntimeError('Native HTTP ' + str(response.status))

        started = time.monotonic()
        if key in ('home', 'back'):
            send(connections[0], None)
        else:
            try:
                send(connections[0], 'keyDown')
            finally:
                send(connections[1], 'keyUp')
        if not quiet:
            print('Native short press accepted: ' + key + '; duration ms=' + str(round((time.monotonic() - started) * 1000)), flush=True)
    finally:
        for connection in connections:
            connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('host')
    parser.add_argument('state')
    parser.add_argument('key', choices=KEYS)
    args = parser.parse_args()
    remote = NativeRemote(args.host, args.state)
    remote.trust_receiver()
    press(remote, args.key)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, http.client.HTTPException) as error:
        print('Native short press failed: ' + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
