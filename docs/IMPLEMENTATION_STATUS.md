# Implementation Status

Last reconciled against `main` at `c4425023c6bfa531970146d0183de8b0af249d65`.

## Product invariant

Current Account is the user's normal official ChatGPT/Codex profile. It is never switcher-owned or destructively controlled. Second Account is the sole isolated profile and may be controlled only with a verified receipt.

## Implemented and CI-validated

- Current/Second typed account state resolver and menu capability policy.
- Current candidate selection that excludes only a positively verified Second PID and fails closed on ambiguity or uncertain Second recovery.
- Secondary-only launch environment, storage, ownership receipts, graceful termination, restart, stale-receipt handling, pending-launch recovery, and conservative reset/archive.
- Metadata-only migration: legacy A receipts and pending markers are discarded; legacy A storage remains untouched; valid B metadata remains usable.
- Backward-compatible settings migration and future-schema downgrade protection.
- Separate official-app identity checks for Current and strict isolation compatibility/fingerprint checks for Second.
- Update-race quarantine, private-store path/permission protections, diagnostics, safe uninstall text, and opt-in startup at login.
- Current/Second UX, fixed global shortcuts, source-policy audit, expanded unit tests, macOS 14/15 CI, release build, and strict bundle verification.

Run #42 on GitHub Actions passed every configured job on both supported runner versions. This validates compilation and static checks; it does not validate real accounts.

## Locally validated, but not a signed-in acceptance test

- Source-policy audit and all 41 unit tests passed.
- Official `/Applications/ChatGPT.app` passed read-only identity and isolation compatibility inspection.
- Release archive built, extracted into a fresh directory, and passed strict app-bundle verification.

The live smoke test was intentionally not run because two normal official ChatGPT processes were present. The test requires exactly one and refuses to guess which one is Current.

## Implemented but requires live validation

- Current + Second smoke test with one existing normal Current process.
- Signed-in dual-account persistence and OAuth behavior.
- Hotkeys, repeated Open Both, graceful Second quit/restart, and switcher restart with both processes alive.
- Interrupted launch, stale receipt, changed fingerprint, moved app, reset/archive, login-item, uninstall/reinstall, and legacy-data upgrade acceptance.
- Final archive extraction and signature verification.

## Deliberately deferred

- More than one isolated extra account.
- Account identity/email scraping, token copying, Keychain or browser-store access.
- Custom shortcuts, updater, browser automation, and project quick actions.

## Next validation sequence

1. Ensure exactly one normal Current instance is running, then run the disposable one-Current/one-Second smoke test.
2. Validate the real two-account workflow without relaxing any ownership invariant.
3. Record only performed evidence in `VALIDATION.md`.
4. Tag/release only after that acceptance work; notarize only if distributing outside this Mac.
