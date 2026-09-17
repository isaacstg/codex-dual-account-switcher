# Codex Dual Account Switcher

A personalized native macOS menu-bar app for Isaac's two ChatGPT/Codex accounts. Run and focus both accounts simultaneously using the **unchanged official app**, with independent Codex and Electron directories for **both** profiles.

Features: ⌥⌘1 / ⌥⌘2 global shortcuts, Open Both, per-profile status, graceful quit/restart, opt-in startup at login, first-run setup, app-location selection, update compatibility gate, diagnostics, and data-preserving uninstall. No runtime network or credential-management code, dependencies, privileged helper, Dock rewriting, or account import.

Independent Swift/AppKit/SwiftUI implementation. The idea was inspired by [edihasaj/codex-account-switcher](https://github.com/edihasaj/codex-account-switcher); no source code was copied. See [SECURITY.md](SECURITY.md) for the threat model and limitations.

## Build and install

Requirements: macOS 13+, Xcode or Command Line Tools with Swift 5.9+, and OpenAI's Electron-based ChatGPT/Codex app (`com.openai.codex`). The separate native ChatGPT client is not compatible.

```sh
swift test
python3 scripts/audit.py
scripts/build.sh
```

Extract `dist/Codex-Dual-Account-Switcher.zip` directly into `~/Applications` or `/Applications` using Finder, then open the extracted app. The app is signed in a temporary build directory to avoid synced Documents metadata; the ZIP contains the complete app bundle. The build is locally ad-hoc signed. Do not bypass a security warning for an unknown downloaded binary. To distribute a notarized build, supply your own authorized Developer ID identity using `SWITCHER_SIGNING_IDENTITY` and notarize outside this repository.

The controller is a menu-bar app and has no Dock icon. No existing ChatGPT session is quit, imported, or changed. Startup at login is disabled unless you enable it from the menu after installation; macOS may require approval in System Settings.

## First run

1. Select the official ChatGPT.app. Default: `/Applications/ChatGPT.app`. Use **Locate app…** if moved or installed under your own Applications directory.
2. Give profiles distinct names, such as Personal and Work. These labels do not identify or inspect signed-in accounts.
3. Check the installed build, review the compatibility notes, and complete setup.
4. Use **Open / Focus** for A, sign into its intended account in the official app, then do the same for B. Browser login may initially select the browser's current account; choose deliberately.
5. Confirm each official app window displays the correct account before doing work. Use **Open Both** to keep both running; switching focus leaves the other account running.

Quitting the switcher leaves both accounts running. Relaunching it recovers ownership from private launch receipts. A normally launched official app is shown as unmanaged and is never assumed to be Profile A. If a global shortcut is already registered elsewhere, Diagnostics shows a useful error and menu actions remain available. Shortcuts use the physical 1/2 key positions.

## Exactly how isolation works

Let `ROOT = ~/Library/Application Support/Codex Dual Account Switcher`.

| Setting | Profile A | Profile B |
|---|---|---|
| `CODEX_HOME` | `ROOT/Profiles/a/codex` | `ROOT/Profiles/b/codex` |
| `CODEX_ELECTRON_USER_DATA_PATH` | `ROOT/Profiles/a/electron` | `ROOT/Profiles/b/electron` |
| `--user-data-dir` | `ROOT/Profiles/a/electron` | `ROOT/Profiles/b/electron` |

NSWorkspace requests a **new application instance** for each profile with the explicit launch environment and argument. The installed app uses `CODEX_ELECTRON_USER_DATA_PATH` to choose Electron storage and preserve supplied CODEX_HOME during shell-environment loading. Both must be set: relying on the Chromium flag alone is insufficient for the inspected build.

The switcher records only PID, UID, executable path, process start time, and requested profile paths. It reads kernel BSD metadata and executable paths; it never reads process command lines, environments, tokens or profile file contents. Each action revalidates ownership. Reused or unverifiable PIDs, normally launched instances, and app-server/helper processes are left alone.

This is **profile separation within one macOS user**, not a security sandbox. Projects, browser OAuth, shell environment, OS Keychain namespace and user permissions remain shared. OpenAI's multi-instance behavior is not guaranteed. See SECURITY.md before relying on stronger isolation.

## App moves, updates and errors

A missing/moved app requires **Setup & Compatibility → Locate app…**. A new build is blocked until you review and approve compatibility again. No profile data is reset. Invalid OpenAI signatures, unsupported packaging or missing override indicators cannot be bypassed from the UI.

**Diagnostics & Log** shows per-profile ownership/status, unmanaged-instance count, version, fingerprint and login status. Logs are bounded, memory-only, and contain only switcher events. Clear or select text locally; no upload exists.

A timed-out/crashed/ambiguous launch retains a private pending marker and blocks retries. Close **all** official ChatGPT/Codex instances yourself after saving their work, then choose **Resolve interrupted launches** in Diagnostics. The switcher will not guess which untracked process belongs to a profile. If a graceful quit takes longer than 20 seconds or is rejected, restart is cancelled; finish work in the official app and retry.

Read-only compatibility check (no profile state is created):

```sh
.build/release/DualAccountSwitcher --check-app /Applications/ChatGPT.app
```

## Safe uninstall and optional data removal

1. Finish work and quit A/B through the menu.
2. Open **Uninstall Instructions…** and disable startup at login.
3. Quit the switcher; move its controller app to Trash in Finder.

All profile data is retained at ROOT. The official app and your default `~/.codex` remain untouched. Reinstalling the controller can reuse these profiles. Do not remove the source repository if it is your only auditable copy.

**Explicit data purge:** only if you intend to erase BOTH isolated account sessions and their Codex histories, first quit all relevant processes and uninstall. In Finder, use Go to Folder to open `~/Library/Application Support/`, select only `Codex Dual Account Switcher`, and move it to Trash. Inspect before emptying Trash; emptying permanently deletes the retained profiles. No purge is performed by this app or its build scripts.

## Validation

For a native UI preview that cannot launch/quit accounts, register shortcuts, or change login items, run `.build/release/DualAccountSwitcher --preview-ui /absolute/scratch/ui-state`. The explicit scratch root is used only for switcher metadata; normal launches always use the fixed profile root.

The opt-in `swift run SwitcherSmokeTest /Applications/ChatGPT.app /absolute/NEW/scratch/root` integration test launches two fresh official app instances and gracefully quits only verified new processes. It never signs in or reads credentials. Its scratch data is retained. This tool is not bundled in the controller.


14 unit tests and macOS CI are included. CI does not launch the official app or use accounts. See [VALIDATION.md](VALIDATION.md) for local results and manual checks. The source policy guard is a review aid, not a security proof.

Runtime uses Apple's native [new-instance launch option](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance) and [main-app login service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp). No third-party Swift packages are fetched. GitHub Actions networking is build infrastructure, separate from the switcher's runtime.

MIT license. No warranty or affiliation with OpenAI.
