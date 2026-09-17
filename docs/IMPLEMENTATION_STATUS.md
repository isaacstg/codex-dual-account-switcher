# Implementation Status

This file is the persistent orchestration ledger for the Current + Second account redesign. Do not mark validation as passed unless it was actually executed.

## Current objective

Ship a robust v1 where the user's existing/default ChatGPT/Codex profile is **Current account**, while **Second account** is an isolated official ChatGPT instance with separate Electron storage and `CODEX_HOME`.

## Invariants

- Current account uses normal ChatGPT storage and normal `~/.codex`.
- Second account alone uses switcher-private Electron/Codex directories.
- No credential/token/cookie/Keychain scraping or copying.
- No modification of official `ChatGPT.app`.
- No process argv/environment inspection.
- No force kill.
- Never destructively control an ambiguous Current account process.
- Never destructively control Second account unless ownership is strongly verified.

## Progress

### Planning — COMPLETE

- [x] Detailed technical implementation plan added in `docs/IMPLEMENTATION_PLAN.md`.
- [x] Persistent status ledger created.

### Baseline Current + Second migration — PARTIAL / REQUIRES VALIDATION

- [x] `LaunchPlan` changed so Current account receives no isolation overrides while Second account receives isolated Electron + `CODEX_HOME` paths.
- [x] Controller changed so only Second account receipts are retained/owned.
- [x] Current account discovery excludes only a positively verified Second account process and refuses to guess when multiple default candidates exist.
- [x] Current account open/focus path changed to default official app behavior.
- [x] Current account destructive quit is blocked.
- [ ] Compile current repository after these changes.
- [ ] Run unit tests.
- [ ] Run source/security audit.
- [ ] Inspect/update tests that still assume symmetric A/B isolation.
- [ ] Update UI so it no longer exposes misleading Quit/Restart for Current account.
- [ ] Update docs from symmetric A/B model.

### State architecture — TODO
- [ ] Explicit typed Current/Second states.
- [ ] Extract process/state resolver behind testable interfaces.
- [ ] Serialize/idempotently gate account actions.

### Recovery/metadata — TODO
- [ ] Version metadata.
- [ ] Deterministic legacy A receipt/pending migration.
- [ ] Safe stale receipt reconciliation.
- [ ] Improved interrupted-launch recovery.

### Compatibility/update behavior — TODO
- [ ] Distinguish Current's normal launch from Second's isolation compatibility dependency.
- [ ] Refine changed-fingerprint approval UX without weakening security.

### UX — TODO
- [ ] Current account / Second account terminology.
- [ ] Simplified menu.
- [ ] First-run flow focused on signing into Second account.
- [ ] Settings cleanup.
- [ ] Diagnostics copy/recovery improvements.

### Test expansion — TODO
See `docs/IMPLEMENTATION_PLAN.md` for full matrix.

### Refactor — TODO
- [ ] `AccountStateResolver.swift`
- [ ] `OfficialAppLauncher.swift`
- [ ] `SecondaryOwnership.swift`
- [ ] `MetadataMigration.swift`

### CI/release/docs — TODO
- [ ] Update CI for new architecture/tests.
- [ ] Update README.
- [ ] Update SECURITY.md.
- [ ] Update VALIDATION.md.
- [ ] Build/sign/archive new ZIP after validation.
- [ ] Local safe two-instance smoke test.

## Validation evidence

The earlier symmetric-profile build had local test/build/signature/smoke validation. Those results **do not validate the new Current + Second code**. The redesign must be recompiled and retested before release.

## Next action

Inspect the current repository/test suite and implement Phase 0/1: repair baseline assumptions, introduce explicit account-state resolution, add migration tests, then run the complete test/audit suite.