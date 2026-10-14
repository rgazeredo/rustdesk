# AZSign Remote consolidated source

The AZSign product line is `main`; `master` is retained as upstream history.
Consolidated desktop/Store 1.5.3 (`a108f216c`), Android v27 (`78f4f3aa6`)
and Store capture tooling (`e8ca3a24e`). Existing branches/worktrees are retained.

Android still builds upstream tag `1.4.9` using support files from the selected
AZSign commit (`github.sha`). Desktop builds the integrated tree. This preserves
the established platform toolchains without maintaining divergent product branches.
Do not build a stock RustDesk APK and assume it contains the AZSign patches.

`apply.mjs` selects desktop-specific hooks only with `--desktop`. Common transport
keeps desktop blocking work off Tokio and preserves Android relay ALPN/scope
enforcement. These are the regression surfaces of the integration: build-time
patch selection and native authenticated transport. No new white-label behavior.

Validation: 17 Flutter tests; Java identity and autonomous renewal/recovery suites;
2 Rust alias tests; 2 real-source patch application/reapplication tests. Run the
last checks with `node --test .github/azsign-access-poc/apply-platforms.test.mjs`
after initializing `libs/hbb_common` and fetching tag `1.4.9`.

No APK, DMG or MSIX rebuilt/published; no hardware remote session performed.
Provider Android compilation was not run without ANDROID_TEST_JAR. Existing
modified worktrees remain untouched; generated submodule changes in the new test
worktree were restored after verifying the versioned patches reproduce them.

Next development branch: `feat/whitelabel-independent-installations`.
Detailed integration record lives in the AZSign repository at
`docs/maintenance/setup-remote-consolidation-20261014.md`.
