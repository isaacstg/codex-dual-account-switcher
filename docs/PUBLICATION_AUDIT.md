# Public-source publication audit

Reviewed on September 18, 2026.

## Scope and result

Pre-ship verdict: **SHIP IT for public source publication**. This is not authorization to describe an ad-hoc binary as notarized or to mark unperformed account/session acceptance cases complete.

- Fetched full remote history, including `main` and the older `v1-current-secondary-refactor` branch. No remote tags were present.
- Gitleaks scanned all 46 remotely reachable commits before publication preparation, with no leaks found. An additional scan of 92 unique historical file blobs and commit metadata found no credential patterns, account stores, signing material, real personal home paths, or private email addresses. Matches were synthetic `/Users/test` fixtures and GitHub no-reply commit addresses.
- No account/profile data, installer backups, local previews, built bundles, or scratch diagnostics are tracked. Local `work/` and `dist/` remain excluded. Additional credential/signing-file ignores reduce accidental future additions.
- Reviewed ownership, isolation, pending-launch, confirmation, and graceful-termination paths. Current remains outside switcher ownership; uncertain Second states remain blocked. Publication preparation changes only stale error guidance in these paths, not their policy.
- Clean-checkout audit, all 47 tests, and release build passed in a regular directory. A checkout under macOS `/tmp` fails the intentional symlink-ancestry guard; the contributor instructions now explain this restriction.
- Both macOS 14/15 jobs passed for `cbe5369`. Downloaded both retained artifacts and verified archive SHA-256 against `SHA256SUMS.txt` and commit against `BUILD_INFO.txt`.
- MIT license, unofficial affiliation statement, privacy/threat model, build instructions, compatibility requirements, reporting guidance, issue template, validation limitations, and internal documentation links were reviewed.
- Repository description now reflects Current plus one isolated Second, with relevant discovery topics. Issues are enabled and discussions remain disabled.

## Release boundary

Signed-in persistence, physical global shortcut dispatch, startup-at-login, and the remaining update/recovery/upgrade acceptance matrix are still distinct from this source review. See [VALIDATION.md](../VALIDATION.md). Developer ID signing and notarization remain future binary-release work.

Private vulnerability reporting and anonymous public access are verified after changing repository visibility. See [PUBLIC_RELEASE_CHECKLIST.md](PUBLIC_RELEASE_CHECKLIST.md) for the publication record.
