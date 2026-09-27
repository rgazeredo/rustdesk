# Authenticated relay scope (pilot v21)

The Android relay transport negotiates `azsign-relay-scope-v1` with ALPN.
After its normal RequestRelay, it requires one framed JSON prelude from the
authenticated gateway, before processing the end-to-end RustDesk handshake:

```json
{"schema":"azsign-relay-scope-v1","session_uuid":"<RequestRelay UUID>","connection_type":"file_transfer"}
```

Only `remote_control` and `file_transfer` are accepted. Missing/invalid frames,
unsupported gateways, wrong UUIDs, and timeouts fail closed. The scope is kept
in a Tokio task-local for the entire controlled connection; no global map, IPC
changes or cross-connection state. Every LoginRequest must match it. FileAction,
FileResponse and Cliprdr are refused on control-only connections, including
printer/file-copy side channels. Existing RustDesk password and device-side
permission checks still apply; the CMS permit is not a replacement for them.

The gateway must refuse file transfer to older APKs without this ALPN capability.
Deploy CMS/migration and gateway before installing v21. Enable the CMS transfer
flag only for the existing pilot after these checks. Preserve Android app data:
use an in-place signed APK upgrade, never uninstall or enroll again. The
renewal scheduler, certificate and keys are unchanged.

Scope regression surface: the feature-gated Android relay connector and incoming
message handler, plus the feature's hbb_common helper. Feature-off paths retain
the existing behavior. The APK workflow still builds tag 1.4.9 plus explicit
patches; it does not switch to the fork HEAD's unrelated native changes.

Tests: Rust scope parsing/task isolation compiled against the real hbb_common
API; patch application checked against tag 1.4.9 and its exact submodule.
Physical Android transfers and block/logout remain required before acceptance.
