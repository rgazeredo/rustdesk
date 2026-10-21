# Android capture lifecycle

Candidate for the v27 Android 1.4.9 build. `apply.py` serializes image access with
`stopCapture` using the service monitor, rejects callbacks from retired readers,
and serializes capture startup and screen-size changes. It preserves the existing
service restart policy. No desktop or server change.

Run `python3 .github/azsign-capture-lifecycle/apply.py <android-source-root>`.
The Android build workflow applies it to the upstream tag before other patches.

For the focused regression test, set `KOTLIN_TEST_CLASSPATH` to a classpath of an
existing Kotlin JVM compiler and its runtime dependencies (compiler embeddable,
stdlib, script runtime, reflect, trove, annotations and coroutines), then run:

```
python3 .github/azsign-capture-lifecycle/test.py
```

The test compiles the actual `createSurface` and `stopCapture` methods extracted
from tag 1.4.9 with fake Android resources. A barrier holds the callback inside
`getPlanes` while teardown starts. It demonstrates the original race, verifies
teardown waits after the patch, and checks stale callbacks after reader replacement.
It also checks patch idempotence. It does not emulate JNI or prove the cause of a
particular firmware crash. Full APK build and physical-device testing are required
before release. The Rust borrowed-buffer lifetime is outside this patch's scope.
