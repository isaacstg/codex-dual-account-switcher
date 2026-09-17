# Implementation Status

Last reconciled against `main` after the Current + Second live smoke validation.

## 1.3 menu-bar revision

Implemented and locally validated:

- Native Accounts/Settings/Help popover; no detached settings or diagnostic windows.
- Two account cards, Open Both, and a verified-Second-only More menu.
- Automatic app checking with plain-language setup/update confirmation.
- Label-only saves, inline errors, close-after-switch callbacks, recovery guidance, and grouped diagnostics/data/uninstall tools.
- Version 1.3.0 (13), native keyboard back navigation, accessibility labels, and compact/long-label layouts.
- Source audit, 47 passing unit tests, native scratch preview, release build, and extracted-bundle signature verification.

Native preview exercised first run, ready state, saved/invalid names, Help details, keyboard back, Escape dismissal/reopen, long labels, simulated pending recovery, and a simulated changed fingerprint. Preview never launched an account or changed login items. The original 1.2 daily workflow was reported by the user as working perfectly; the detailed signed-in release matrix is still distinct from that report.

See `docs/UX_IMPROVEMENT_PLAN.md` for the implemented scope and prioritized proposals. CI evidence for the new revision must be recorded only after its jobs complete.

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

GitHub Actions runs #42 and #43 passed every configured job on both supported runner versions. Run #43 also retained the ZIP, SHA-256, and build-provenance artifacts for each runner. This validates compilation and static checks; it does not validate real accounts.

## Locally validated, but not a signed-in acceptance test

- Source-policy audit and all 41 unit tests passed.
- Official `/Applications/ChatGPT.app` passed read-only identity and isolation compatibility inspection.
- Release archive built, extracted into a fresh directory, and passed strict app-bundle verification.
- The live smoke test passed with one preserved normal Current process and one disposable Second process. It verified separate storage, simultaneous processes, graceful Second termination, and Current preservation.

The disposable smoke profile remains in an ignored local `work/` directory. It was never signed in and was not read by the test.

## Implemented but requires live validation

- Signed-in dual-account persistence and OAuth behavior.
- Hotkeys, repeated Open Both, graceful Second quit/restart, and switcher restart with both processes alive.
- Interrupted launch, stale receipt, changed fingerprint, moved app, reset/archive, login-item, uninstall/reinstall, and legacy-data upgrade acceptance.

## Deliberately deferred

- More than one isolated extra account.
- Account identity/email scraping, token copying, Keychain or browser-store access.
- Custom shortcuts, updater, browser automation, and project quick actions.

## Next validation sequence

1. Ensure exactly one normal Current instance is running, then run the disposable one-Current/one-Second smoke test.
2. Validate the real two-account workflow without relaxing any ownership invariant.
3. Record only performed evidence in `VALIDATION.md`.
4. Tag/release only after that acceptance work; notarize only if distributing outside this Mac.
