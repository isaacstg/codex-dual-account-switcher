# Security model

The switcher is a local controller for two copies of the unchanged, OpenAI-signed Electron-based ChatGPT/Codex application. It is not an identity provider, a token manager, an app sandbox, or an official OpenAI product.

## Assets and trust boundaries

Protect account credentials, profile storage, existing default ChatGPT/Codex sessions, unfinished account work, and the integrity of the official application. Trust macOS, the user's account, Apple's local signing validation, and the official application to honor its profile configuration. The official app, its extensions, app server, shell configuration and browser sign-in are outside this utility's trust boundary.

An attacker who already controls the same macOS user can read their files, alter switcher metadata, replace this unsigned-development utility, and control their processes. Directory permissions and safe metadata handling reduce accidents and attacks from other users; they cannot contain same-user malware or a root attacker.

## Invariants

1. No runtime networking, telemetry, updater, embedded web view, remote command input, or downloaded code. Security.framework is used **only** for static signature checks with `SecCSFlags.noNetworkAccess`: online revocation/notarization queries are disabled for those checks. macOS's normal Gatekeeper policy remains in force. The official ChatGPT app uses the network normally.
2. No Keychain credential API, token file access, credential migration, browser-store access, password prompt, process argv inspection, or process environment inspection. The controller does not know which email is signed in. Labels are user-defined descriptions.
3. Both profiles receive a distinct `CODEX_HOME`, a distinct `CODEX_ELECTRON_USER_DATA_PATH`, and the same explicit Electron path through `--user-data-dir`. Neither shares `~/.codex` or default Electron storage. `HOME` remains the user's real home: projects, shell configuration, OS Keychain namespace and user permissions are not isolated.
4. Launch configuration uses an explicit environment allowlist. No current process environment is read or copied. OpenAI's app can subsequently load its own shell environment; this utility cannot stop upstream code or user shell scripts from reading credentials. Static checks do not establish complete runtime isolation.
5. Only the official `com.openai.codex` application signed by team `2DC432GLL2` may launch. Full static signature validation is required; invalid signatures or missing expected Electron bootstrap indicators block launch. Legitimate signing or packaging changes require a reviewed code update; there is no bypass toggle.
6. Process ownership comes from a newly launched NSWorkspace instance, not a name match. Its receipt binds profile, UID, PID, exact executable path, and kernel start time (seconds and microseconds). A normal/default instance is never adopted. BSD metadata is checked before and after executable-path retrieval. Restoring a receipt requires the same snapshot and fixed profile paths.
7. The writer holds a nonblocking `flock` across its lifetime. Metadata is limited to settings, receipts, and pending attempts, saved atomically with mode 0600. The profile root and created subdirectories have mode 0700. Existing symlink ancestors, redirected profile directories, non-regular metadata, foreign-owned metadata, and hardlinked metadata are rejected. Paths are not a configurable per-profile feature. Same-user concurrent filesystem tampering remains out of scope; the checks are not a filesystem sandbox.
8. Intent is persisted before launch. A crash, ambiguous response, timeout, failed receipt save, or app replacement during launch leaves a pending marker. It blocks retries across controller restarts. Recovery requires an explicit Diagnostics action after ALL official instances are closed. An updater-created replacement process is not silently adopted.
9. Quit uses `NSRunningApplication.terminate()` for a currently verified owned app. There is no force-kill, name-based kill, helper-process kill, or admin escalation. A rejected or slow quit cancels restart. Native termination is not guaranteed to save unfinished work; the menu warns before quit/restart.
10. Login startup uses `SMAppService.mainApp`, only after the user opts in from an installed app bundle. No LaunchAgent plist, daemon, admin helper, Accessibility permission, Full Disk Access, or Input Monitoring permission is requested. Carbon registers only two fixed shortcuts.
11. Official app bundles and Dock preferences are never written, copied, re-signed, or patched. The build script ad-hoc signs only our newly built controller bundle.
12. Diagnostics contain bounded memory-only switcher events and process metadata. No official app stdout/stderr or profile logs are read. Diagnostic display can reveal local paths and PIDs; sharing it is the user's choice. There is no automatic upload.
13. Safe uninstall unregisters the login item and removes only the controller through Finder's Trash. Profile data remains. There is no automatic data purge in the app.

## Update policy and limits

The build fingerprint is SHA-256 over Info.plist, the main executable, and app.asar. Every new launch revalidates the full signature, indicators and fingerprint. A changed build requires user review in Setup & Compatibility. Signature and fingerprint are rechecked after launch to detect replacement during launch. Focus and graceful quit remain available for an already verified process after a disk update; a respawned process without a receipt is unmanaged.

The indicator checks look for the profile override in the packaged Electron bootstrap and CODEX_HOME support in the archive. They are conservative compatibility heuristics, not a proof that an upstream update implements isolation correctly. They may block a compatible packaging change or accept a behavior change that still contains those strings. Multi-instance behavior, external OAuth callbacks, deep links, OS-level Keychain use, shared shell settings and auto-update interactions need manual validation. Absolute containment requires separate macOS user accounts or virtual machines.

The local app build is ad-hoc signed, not Developer ID notarized. Wider distribution requires an authorized Developer ID certificate and Apple's notarization process. No signing credentials are bundled or requested by this repository. Never disable Gatekeeper to run an unknown download.

## Verification

`python3 scripts/audit.py` guards against prohibited source APIs. Unit tests cover disjoint profile configuration, environment allowlist, stale/PID-reused/default process rejection, private file permissions, writer locking, metadata corruption, path traversal and symlink/hardlink rejection. CI builds and tests on two macOS runners with read-only GitHub permissions. Manual review must additionally trace every filesystem read, launch and termination path. Opt-in smoke testing launches only fresh temporary official profiles and verifies that an existing normal instance survives.

Report suspected defects privately to the repository owner through the private repository. Do not post tokens, profile databases, session logs, or full environment dumps. Provide the switcher version, official app version, a redacted diagnostic excerpt, and reproduction steps.
