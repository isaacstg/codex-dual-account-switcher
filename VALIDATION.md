# Validation and release status

## Current architecture

The v1 model is asymmetric:

- **Current Account** is the user's ordinary official ChatGPT/Codex process and existing storage. The switcher may discover, focus, or normally open it. It never owns, quits, restarts, or migrates Current.
- **Second Account** alone receives private Electron storage and a private `CODEX_HOME`. It may be gracefully quit or restarted only when a verified receipt proves ownership.

The older symmetric A+B smoke result is historical only. It does **not** validate this architecture.

## Evidence at `c4425023c6bfa531970146d0183de8b0af249d65` plus local validation

GitHub Actions run #42 passed on both macOS 14 and macOS 15:

- source-policy audit;
- shell and plist validation;
- unit tests;
- release build;
- strict bundle signature verification.

The audit rejects networking, credential and browser-store APIs, process argv/environment inspection, subprocess control, force-kill behavior, Dock mutation, and private Current/A storage or ownership patterns.

The build stages the app in `/private/tmp`, ad-hoc signs only the switcher bundle, verifies it, then packages it without resource-fork or extended-attribute metadata. This is suitable for a personal local build. It is not Developer ID notarization.

On this Mac, the Current + Second source revision also passed:

- `python3 scripts/audit.py`;
- all 41 unit tests;
- read-only inspection of `/Applications/ChatGPT.app` (OpenAI identity, Electron override markers, and fingerprint `d327e421c63f1bf5ee9648ec99c84c292d01da08cd3d1bfd6adb65c435c9ea73`);
- release build, fresh ZIP extraction, and strict verification of the extracted app bundle.

The local archive checksum was `2d806aa26cc9f35dd64d3e4c2b69644f91553dd8f3615c47d63a92ec0b86b089`.

## Current-architecture validation still required

The following have not yet been claimed as complete for the Current + Second revision:

1. Live smoke test with exactly one existing normal Current instance and one disposable isolated Second instance.
2. Signed-in two-account acceptance: persistence, focus, repeated shortcuts/Open Both, graceful Second quit/restart, and switcher restart.
3. Launch-at-login, update/fingerprint, interrupted-launch recovery, reset/archive, uninstall/reinstall, and legacy-data upgrade acceptance.

CI cannot prove OAuth behavior, session persistence, or account isolation at runtime.

## Reproduce static validation

```sh
python3 scripts/audit.py
swift test
scripts/build.sh
```

In a restricted execution sandbox, use `SWITCHER_SWIFTPM_DISABLE_SANDBOX=1 scripts/build.sh` only when SwiftPM's nested sandbox is the blocker. This changes build isolation, not the switcher's runtime privileges.

## Opt-in live smoke test

Open exactly one normal official ChatGPT instance first. Then run with a new scratch root:

```sh
swift run SwitcherSmokeTest /Applications/ChatGPT.app /absolute/new/scratch-root
```

The smoke test refuses zero or multiple Current candidates. It launches one fresh isolated Second, verifies only storage metadata, confirms Current and Second coexist, gracefully terminates only the verified Second process, and preserves Current. It never signs in or reads profile, authentication, cookie, Keychain, argv, or environment data. Scratch Second data is retained for inspection.

## Release boundary

The CI artifact is an ad-hoc personal-build archive with checksum and build information. Do not represent it as a notarized public release. A public distribution requires an authorized Developer ID signature, notarization, and fresh acceptance evidence.
