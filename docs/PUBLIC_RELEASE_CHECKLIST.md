# Public repository and release checklist

This project may be made public as source code once the repository settings and checks below are complete. A public source repository is different from publishing a broadly installable release.

## Before changing repository visibility

- [ ] Review every reachable Git commit for secrets and private diagnostics, including historical branches and tags.
- [ ] Confirm `git status --short` is clean and `git ls-files --others --exclude-standard` shows no unintended files.
- [ ] Run `python3 scripts/audit.py`, `swift test`, and `scripts/build.sh` from a clean checkout.
- [ ] Confirm CI is green on both configured macOS versions and its uploaded ZIP checksum matches the build provenance.
- [ ] Review `README.md`, `SECURITY.md`, `VALIDATION.md`, `CONTRIBUTING.md`, and this checklist for accurate claims.
- [ ] Enable GitHub private vulnerability reporting in the repository security settings.
- [ ] Set the repository description and topics; state clearly that it is an independent, unofficial utility.
- [ ] Decide whether repository issues and discussions should be enabled and who will triage them.

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

- [ ] Verify that the README renders correctly and that every internal link works.
- [ ] Watch the first CI run and artifact upload on the public default branch.
- [ ] Triage public reports without asking reporters to share credentials, cookies, account exports, or unredacted logs.
- [ ] Keep the isolation compatibility gate conservative when the official app changes; Current should stay normal and usable while Second awaits review.
