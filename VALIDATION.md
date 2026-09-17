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

GitHub Actions run #43 repeated those checks on both macOS versions and successfully retained a personal-build ZIP, SHA-256 checksum, and build-provenance artifact for each runner.

The audit rejects networking, credential and browser-store APIs, process argv/environment inspection, subprocess control, force-kill behavior, Dock mutation, and private Current/A storage or ownership patterns.

The build stages the app in `/private/tmp`, ad-hoc signs only the switcher bundle, verifies it, then packages it without resource-fork or extended-attribute metadata. This is suitable for a personal local build. It is not Developer ID notarization.

On this Mac, the Current + Second source revision also passed:

- `python3 scripts/audit.py`;
- all 41 unit tests;
- read-only inspection of `/Applications/ChatGPT.app` (OpenAI identity, Electron override markers, and fingerprint `d327e421c63f1bf5ee9648ec99c84c292d01da08cd3d1bfd6adb65c435c9ea73`);
- release build, fresh ZIP extraction, and strict verification of the extracted app bundle.

The opt-in live smoke test also passed on this Mac with exactly one pre-existing normal Current process:

- Current remained the same verified process (PID `38754`) throughout;
- the tool launched a different verified official Second process (PID `61410`);
- the Second process initialized its separate Electron and Codex directories;
- both processes ran simultaneously;
- only the verified disposable Second process received a graceful termination request; and
- the normal Current process remained intact after the test.

The scratch Second data was retained at `work/live-smoke-20260917` for local inspection. It contains no test login because the smoke test never signs in or reads profile contents.

The historical 1.2 archive checksum was `57172428fbb03e87e63a533e4abb5e7b9f44a0716136a292534554c1632726af`.

## Current-architecture validation still required

The following have not yet been claimed as complete for the Current + Second revision:

1. Signed-in two-account acceptance: persistence, focus, repeated shortcuts/Open Both, graceful Second quit/restart, and switcher restart.
2. Launch-at-login, update/fingerprint, interrupted-launch recovery, reset/archive, uninstall/reinstall, and legacy-data upgrade acceptance.

CI cannot prove OAuth behavior, session persistence, or account isolation at runtime.

## Version 1.3 menu-bar revision

The user reported the installed 1.2 workflow works perfectly. This is user acceptance feedback, not an independently observed completion of every release case.

For 1.3.0 (13), local verification passed:

- the unchanged network/credential/process-control source-policy audit;
- all 47 unit tests, including label saves preserving approval/setup and update confirmation refusing recovery/in-flight lifecycle states;
- release compilation and strict verification of a freshly extracted ZIP;
- native popover first-run and ready layouts, Settings, saving names without setup approval, inline invalid-name errors, and Help disclosures;
- native Shift-Command-B back navigation, Escape dismissal, and app reopening;
- long labels, simulated pending recovery with disabled account controls, and explicit changed-fingerprint confirmation.

UI tests used only ignored scratch metadata with preview mode enabled. They never launched/focused/quit a live account, registered shortcuts, changed startup settings, or read profile contents. Unavailable-build confirmation gating was unit-tested; the actual installed official app passed its checks, so an unavailable-build native UI case was not claimed.

The redesigned quit/restart confirmations, global-shortcut error presentation, and startup option still require normal installed-app acceptance. The lifecycle and isolation implementation is unchanged except for stricter update-confirmation guards.

The verified local 1.3 ZIP SHA-256 is `5f62a513a08bd935f9e4acbcf8df76f4d50259f9de8c30748f35826c70cb72b6`.

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

The smoke test refuses zero or multiple Current candidates. It launches one fresh isolated Second, verifies only storage metadata, confirms Current and Second coexist, gracefully terminates only the verified Second process, and preserves Current. It never signs in or reads profile, authentication, cookie, Keychain, argv, or environment data. Scratch Second data is retained for inspection. Use a new path with no symbolic links in its ancestry; macOS exposes `/tmp` and `/var` through symbolic links, which the private-store guard rejects.

## Release boundary

The CI artifact is an ad-hoc personal-build archive with checksum and build information. Do not represent it as a notarized public release. A public distribution requires an authorized Developer ID signature, notarization, and fresh acceptance evidence.
