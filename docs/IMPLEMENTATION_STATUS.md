# Implementation Status

Persistent orchestration ledger for the Current + Second account redesign. **Code-complete does not mean validated.** Do not mark validation passed unless it was actually executed on macOS.

## Current objective

Ship a robust v1 where the user's existing/default ChatGPT/Codex profile is **Current account**, while **Second account** is an isolated official ChatGPT instance with separate Electron storage and `CODEX_HOME`.

## Invariants

- Current uses normal ChatGPT storage and normal `~/.codex`.
- Second alone uses switcher-private Electron/Codex directories.
- No credential/token/cookie/Keychain scraping or copying.
- No modification of official `ChatGPT.app`.
- No process argv/environment inspection.
- No force kill.
- Never destructively control Current.
- Never destructively control Second unless ownership is strongly verified.
- Ambiguity fails closed rather than guessing.

## Implementation progress

### Planning — IMPLEMENTED
- [x] Detailed plan in `docs/IMPLEMENTATION_PLAN.md`.
- [x] Persistent status ledger.

### Current + Second architecture — IMPLEMENTED / UNVALIDATED
- [x] Current launches normally with no private Electron/Codex overrides.
- [x] Second alone receives isolated Electron + `CODEX_HOME` paths.
- [x] Current discovery excludes only a positively verified Second PID.
- [x] 0/1/multiple Current-candidate behavior is explicit; multiple candidates are never guessed.
- [x] Current open/focus implemented.
- [x] Current destructive quit/restart blocked by design and removed from normal menu UX.
- [x] Second launch/focus/verified graceful quit/restart retained.
- [x] `LaunchReceipt.owns` now refuses legacy A ownership by construction.

### State architecture — IMPLEMENTED / UNVALIDATED
- [x] `CurrentAccountState` and `SecondaryAccountState` domain types.
- [x] Pure `AccountStateResolver` for Current candidate selection and Second ownership state.
- [x] Controller rendering now consumes the explicit resolver instead of hand-building all status strings.
- [x] Per-account in-flight gates make repeated open calls idempotent while launch is active.
- [ ] Further service/protocol extraction is optional after compile validation; avoid churn before knowing compiler/runtime behavior.

### Recovery/metadata — IMPLEMENTED / UNVALIDATED
- [x] Deterministic metadata-only legacy migration drops A receipts/pending markers and retains at most one B receipt.
- [x] Duplicate B receipts are rejected rather than guessed through.
- [x] Legacy A profile directories are deliberately left untouched.
- [x] Clearly dead stale Second receipts can be reconciled without deleting profile data.
- [x] Interrupted Second launch remains blocked until explicit recovery.
- [x] Recovery requires all official ChatGPT instances closed and clears only switcher receipt/pending metadata.
- [ ] Formal schema-version envelope deferred; current Codable legacy format remains intentionally readable for migration.

### Compatibility/update behavior — IMPLEMENTED / UNVALIDATED
- [x] Second remains gated on the explicitly approved compatibility fingerprint.
- [x] Changed build messaging now specifically explains that isolated Second launching is blocked pending review.
- [x] Bundle is re-inspected after Second launch to catch an update/replacement race.
- [x] Current normal launch no longer requires the approved isolation fingerprint; it does not depend on private profile overrides.

### UX — IMPLEMENTED / UNVALIDATED
- [x] Normal UI terminology changed from A/B implementation language to Current account / Second account.
- [x] Simplified menu: Current open/focus only; Second open/focus/restart/quit.
- [x] First-run copy explains existing profile is untouched and focuses next step on signing into Second.
- [x] Setup provides direct `Open Second Account` action after approval.
- [x] Diagnostics copy button added.
- [x] Recovery/uninstall copy rewritten for asymmetric ownership.
- [x] Menu-bar tooltip uses Current/Second terminology.

### Tests — WRITTEN / NOT RUN
- [x] Replaced old symmetric-isolation core assumptions with Second-only isolation tests.
- [x] Added pure tests for Current absent/running/ambiguous behavior.
- [x] Added verified-Second exclusion tests.
- [x] Added PID reuse/unverified-live/stale receipt state tests.
- [x] Added legacy A receipt/pending migration tests.
- [x] Added duplicate B metadata rejection test.
- [x] Existing private-store, permissions, symlink/hardlink, lock, unsigned-app, completion-gate and kernel snapshot tests retained.
- [ ] Controller concurrency/integration cases require macOS execution/refactor if failures expose gaps.

### Live smoke tool — REWRITTEN / NOT RUN
- [x] No longer creates two fresh isolated profiles.
- [x] Requires exactly one pre-existing normal Current instance.
- [x] Launches exactly one isolated scratch Second instance.
- [x] Verifies Current + Second coexist as distinct processes.
- [x] Checks only metadata-level Second storage initialization, never auth contents.
- [x] Gracefully quits only the verified scratch Second process.
- [x] Verifies pre-existing Current process was preserved.

### Documentation/security — IMPLEMENTED
- [x] README rewritten for Current + Second model.
- [x] SECURITY.md rewritten around asymmetric discovery/ownership and fail-closed rules.
- [x] Implementation plan/status maintained.
- [ ] VALIDATION.md must be rewritten after actual validation so it contains evidence rather than predictions.

### CI/release — EXISTING PIPELINE, NEW CODE UNVALIDATED
- [x] CI already runs source audit, plist/shell validation, `swift test`, release build and bundle signature verification on macOS 14/15.
- [x] Build script stages/signs outside sync-prone directories and archives without resource-fork/xattr metadata.
- [ ] Observe CI on the redesigned HEAD and fix failures.
- [ ] Run local installed-app compatibility check.
- [ ] Build/sign/archive final ZIP after all fixes.
- [ ] Run local safe Current + Second smoke test.
- [ ] Rewrite VALIDATION.md with exact final evidence.

## Important validation status

**No compile/test/build/smoke claim is made for the redesigned code yet.** The earlier symmetric-profile build had successful validation, but those results do not transfer to this architecture.

The source changes were intentionally written first because no macOS execution environment is currently available in this session.

## Next action when execution is available

1. Run `python3 scripts/audit.py`.
2. Run `swift test` and fix all compiler/test failures.
3. Run `bash scripts/build.sh` and strict signature verification.
4. Run the read-only compatibility check against installed official ChatGPT.
5. With exactly one normal Current instance open, run the opt-in smoke test using a brand-new scratch root.
6. Fix any runtime issues, rerun the full suite, then update `VALIDATION.md` and package the final ZIP.
