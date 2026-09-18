# Public repository and release checklist

This project may be made public as source code once the repository settings and checks below are complete. A public source repository is different from publishing a broadly installable release.

## Before changing repository visibility

- [x] Review every remotely reachable Git commit for secrets and private diagnostics, including historical branches and tags (46 commits before publication preparation; Gitleaks and additional blob/metadata checks).
- [x] Confirm no unintended tracked or untracked files; publication changes are committed before changing visibility.
- [x] Run `python3 scripts/audit.py`, `swift test`, and `scripts/build.sh` from a clean checkout in a non-symlink location.
- [x] Confirm macOS 14/15 CI is green for final preparation source/workflow `c4fa88a`, run `35336196581`; download both CI artifacts and verify ZIP checksums and commit provenance.
- [x] Review `README.md`, `SECURITY.md`, `VALIDATION.md`, `CONTRIBUTING.md`, and this checklist for accurate claims.
- [x] Enable GitHub private vulnerability reporting in the repository security settings; API verified `enabled: true` after publication.
- [x] Set the repository description and topics; state clearly that it is an independent, unofficial utility.
- [x] Issues enabled for maintainer triage; discussions disabled. Bug template prohibits sharing account data.

The repository became public on September 18, 2026. Private vulnerability reporting was enabled immediately afterward; secret scanning and secret push protection are also enabled. Anonymous repository and README access were verified. Source publication does not claim that the pending binary-release acceptance matrix is complete.

## Before publishing a binary release

- [ ] Complete the signed-in two-account acceptance cases in `VALIDATION.md`.
- [ ] Re-run the live Current + Second smoke test after any ChatGPT app update or launch-process change.
- [ ] Build from a clean checkout and verify the extracted ZIP with `codesign --verify --strict`.
- [ ] Publish the ZIP SHA-256 and build commit in the release notes.
- [ ] Sign with the maintainer's Apple Developer ID and submit the release archive for notarization.
- [ ] Verify the notarized archive on a separate macOS user or machine without bypassing Gatekeeper.
- [ ] Create an annotated version tag and release notes that name known limitations, especially that OpenAI can change Electron isolation behavior.

Do not call an ad-hoc local build or a GitHub Actions artifact a notarized release.

## After making the repository public

- [x] Verify anonymous README access and validate the public-facing documentation's internal file links.
- [x] Verify the latest green default-branch CI run is accessible after publication and both artifacts have correct checksums/provenance. Continue monitoring subsequent public runs.
- [ ] Triage public reports without asking reporters to share credentials, cookies, account exports, or unredacted logs.
- [ ] Keep the isolation compatibility gate conservative when the official app changes; Current should stay normal and usable while Second awaits review.
