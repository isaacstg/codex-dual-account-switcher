# Validation and release status

Local validation on 2026-09-17: Apple Silicon, macOS 26.6.2, Xcode's Swift 6.3.2; official ChatGPT/Codex version 26.908.70816 (9275), bundle ID `com.openai.codex`, signing team `2DC432GLL2`.

- 14 XCTest cases passed: profile separation/allowlisted environment; process adoption/ownership; PID reuse and incorrect UID/executable/path rejection; live self-process snapshot; 0700/0600 permissions; controller lock contention; corrupted metadata; unsafe metadata names; symlink/hardlink rejection; persistent pending-launch marker; exactly-once concurrent completion gate; unsigned app rejection.
- Source policy audit passed. Manual read-path review: packaged official program code and signature, Info.plist, and only switcher's three metadata filenames. No profile contents, authentication files, Keychain credentials, process argv/environment, browser stores or official logs are read by the controller.
- Static compatibility check passed against the installed official app. Offline full signature validation and fingerprint generation work outside the Codex execution sandbox. The sandbox itself prevents certificate-validation services, so a sandboxed diagnostic can fail even with a healthy official app; signature validation was independently confirmed with macOS codesign.
- Opt-in live smoke test passed: Profile A and B were distinct new official processes, both remained alive simultaneously, and each initialized its own Electron Local State and nonempty Codex directory. The test checked storage metadata, never read file contents. Both new processes quit gracefully; the existing normal official instance retained its PID/start-time snapshot. Fresh scratch data was retained outside the repository.
- Release app built successfully, ad-hoc signature verified, and packaged as a ZIP. Synced Documents storage attaches FinderInfo to `.app` folders, so the build signs in a temporary directory and archives without extended attributes. Extract directly into Applications.
- Native first-run UI visually inspected and preview setup saved; layout clipping was corrected with scrollable content. Preview mode cannot launch or quit accounts, register shortcuts, or mutate login items.
- No accounts were signed into, imported, or migrated during tests. The official app bundle was not modified.
- GitHub CI is configured for two macOS runner images. Its eventual result must be checked separately; local success is not a claim about CI.

## Reproduce

```sh
swift test
python3 scripts/audit.py
scripts/build.sh
.build/release/DualAccountSwitcher --check-app /Applications/ChatGPT.app
```

Inside a restricted execution sandbox, put compiler caches inside `work/` and, where the outer sandbox prevents SwiftPM's nested sandbox, explicitly set `SWITCHER_SWIFTPM_DISABLE_SANDBOX=1` for the build script. This affects only the source build, not runtime privileges.

Native layout preview, using a new scratch directory (launch, quit, hotkeys and login mutations are disabled):

```sh
.build/release/DualAccountSwitcher --preview-ui /absolute/scratch/ui-state
```

Opt-in integration test (launches the official app, which uses the network normally):

```sh
swift run SwitcherSmokeTest /Applications/ChatGPT.app /absolute/NEW/scratch/profile-root
```

Use a new path. The smoke tool does not sign in or delete scratch data. It terminates only exact verified new instances and preserves normal instances. Review scratch directories yourself before deleting them. The smoke tool is not bundled inside the controller app.

## Manual acceptance with the user's two accounts

1. Install the locally built controller and complete first-run setup; verify the app location and distinct labels.
2. Sign into A and B separately. Verify their actual account identities in each official window. Relaunch each and confirm account persistence and separation, including browser OAuth callbacks.
3. Press ⌥⌘1 and ⌥⌘2 while another app is focused. Confirm both still run. Test shortcut conflict reporting by letting another app register one shortcut first.
4. Test Open Both, menu status, cancel/confirm Quit and Restart, slow/rejected graceful quit, and ongoing background work in the other profile.
5. Quit/relaunch the controller with accounts running; confirm receipt recovery and that the default official instance remains unmanaged.
6. Enable/disable startup at login from an installed bundle; check System Settings and verify after logout/login. Login startup should launch only the controller.
7. Move the official app after closing test profiles; confirm launch failure, Locate app recovery and no data reset. After an official update, confirm the changed-build gate and manually review profile behavior again.
8. Simulate an interrupted launch using a disposable scratch profile; confirm pending markers survive controller restart and recovery requires closing all official instances.
9. Follow safe uninstall: unregister startup, Trash only the controller, verify retained profiles, then reinstall and reuse them. Test any deliberate purge only with disposable test data.

Signed-in OAuth persistence, actual login/logout behavior, shortcut conflicts and future update behavior require user/environment acceptance. The local ad-hoc build is not Developer ID notarized; public binary distribution needs authorized signing and notarization.
