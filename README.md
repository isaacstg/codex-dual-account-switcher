# Codex Account Switcher for macOS

A small native menu-bar utility for keeping **your normal ChatGPT/Codex account** and **one additional isolated account** open at the same time in the official OpenAI macOS app.

## The model

The switcher is intentionally asymmetric:

| | Current account | Second account |
|---|---|---|
| ChatGPT storage | Normal/default | Private isolated directory |
| Codex home | Normal `~/.codex` | Private isolated `CODEX_HOME` |
| Existing login | Kept as-is | Sign in once separately |
| Switcher may focus/open | Yes | Yes |
| Switcher may quit/restart | No | Yes, only with verified ownership |

Your current installation is not cloned, migrated, rewritten, or imported. If you remove the switcher tomorrow, normal ChatGPT continues to work exactly as before.

## Daily use

- **⌥⌘1** — open/focus Current account.
- **⌥⌘2** — open/focus Second account.
- **Open Both** — ensure both are open.
- The menu bar shows state for both accounts.

If Current is already open, the switcher focuses it. If it is closed, the official app is opened normally with no profile overrides.

If Second is already running and its ownership is verified, the switcher focuses it. Otherwise it launches a new official app instance with separate Electron and Codex directories.

## First run

1. Put `Codex Dual Account Switcher.app` in `/Applications` or `~/Applications`.
2. Open the switcher. It appears in the menu bar and has no Dock icon.
3. Confirm the official ChatGPT app location (normally `/Applications/ChatGPT.app`).
4. Run the compatibility check and approve the installed build.
5. Optionally rename the two menu labels.
6. Click **Open Second Account** and sign into your other ChatGPT account.
7. Verify the intended account is displayed in each official ChatGPT window.

Your Current account should not require another sign-in.

Browser OAuth may initially select the browser account most recently used. Choose the intended second account deliberately during sign-in.

## How isolation works

Only Second receives these overrides:

```text
--user-data-dir=~/Library/Application Support/Codex Dual Account Switcher/Profiles/b/electron
CODEX_ELECTRON_USER_DATA_PATH=~/Library/Application Support/Codex Dual Account Switcher/Profiles/b/electron
CODEX_HOME=~/Library/Application Support/Codex Dual Account Switcher/Profiles/b/codex
```

Current receives none of them.

The switcher launches the official app through macOS LaunchServices. It does not patch or copy `ChatGPT.app`.

## Process safety

Second-account ownership is accepted only when the switcher can verify the recorded PID, macOS user ID, process start time, executable path, and private profile paths. PID reuse or a mismatched live process is rejected.

Current is discovered conservatively. The switcher enumerates official ChatGPT application instances and excludes only a positively verified Second process. If exactly one process remains, it can be focused as Current. If multiple default candidates remain, the switcher refuses to guess and asks you to close the extras manually.

Current is never terminated or restarted by the switcher. That lifecycle stays with the official ChatGPT app.

Second quits gracefully. The switcher waits for it to exit and never sends a forced kill.

## Crash and interrupted-launch recovery

Before launching Second, the switcher persists a pending marker. It clears that marker only after a new process has been verified and ownership metadata saved.

If the switcher/macOS fails during this window, another Second launch is blocked rather than risking a duplicate or controlling the wrong process. Diagnostics provides a recovery action. Recovery requires all official ChatGPT instances to be closed first and clears switcher metadata only; account/profile contents are preserved.

Dead, strongly stale Second receipts can be cleared automatically without deleting isolated account data.

## Upgrading from the original two-isolated-profile build

Older versions created private A and B directories. The new design treats A as Current/default and B as Second/isolated.

On startup, legacy A process receipts and A pending-launch markers are discarded. **Legacy A profile directories are deliberately left untouched.** B metadata is retained when valid. No profile contents are read during migration.

## Compatibility gate

The isolated account relies on behavior in the official OpenAI app. The switcher validates the official bundle/signature and expected compatibility markers and stores a fingerprint of the approved build.

When that fingerprint changes, Second-account launching is blocked until the new build is reviewed and approved. This is intentionally conservative: an app update should never silently cause the switcher to launch Second without the isolation assumptions being rechecked.

## Privacy and security

The switcher does **not**:

- read, copy, parse, or migrate authentication tokens;
- inspect account emails or identities;
- read cookies, browser stores, Keychain credentials, or ChatGPT logs;
- inspect another process's command-line arguments or environment;
- make network requests;
- modify the official ChatGPT app;
- run shell commands to control ChatGPT;
- force-kill ChatGPT processes.

The private switcher root uses restrictive filesystem permissions and hardened metadata writes. See `SECURITY.md` for the full threat model.

This is **profile separation inside one macOS user account**, not an operating-system security boundary. Both ChatGPT instances still share the permissions/resources available to that macOS user.

## Diagnostics

Diagnostics shows switcher-owned state such as:

- Current/Second process status;
- compatibility result and fingerprint;
- app path;
- Second-account storage root;
- startup-at-login state;
- bounded in-memory switcher logs.

It deliberately does not collect account identity or authentication data. **Copy Diagnostics** copies only that switcher-owned diagnostic text.

## Startup at login

Startup at Login is opt-in. It starts the switcher itself, not both ChatGPT accounts automatically.

## Uninstall

1. Finish work in Second and quit it from the switcher.
2. Disable Startup at Login.
3. Quit the switcher.
4. Move the switcher app to Trash.

Current ChatGPT is unaffected. Second-account data is preserved by default at:

```text
~/Library/Application Support/Codex Dual Account Switcher
```

Delete that directory manually only if you explicitly want to purge the switcher's isolated data and after relevant ChatGPT processes are closed.

## Development

The project is a Swift Package containing:

- `SwitcherCore` — security-sensitive model, compatibility, state resolution and private storage;
- `DualAccountSwitcher` — native AppKit/SwiftUI menu-bar application;
- `ProcessIdentity` — minimal Darwin process identity snapshot helper;
- `SwitcherCoreTests` — unit/security tests;
- `SwitcherSmokeTest` — opt-in local live validation helper.

The implementation roadmap and current validation status live in:

- `docs/IMPLEMENTATION_PLAN.md`
- `docs/IMPLEMENTATION_STATUS.md`

Typical local validation after checking out the repository:

```text
python3 scripts/audit.py
swift test
bash scripts/build.sh
```

The live smoke test is separate and opt-in because it launches real official app instances. Static/unit tests do not prove account isolation.

## Distribution

Personal builds may be ad-hoc signed. Public distribution should use an authorized Apple Developer ID and notarization. Do not globally disable Gatekeeper to install this utility.

## Inspiration

The project was inspired by the general idea of multi-account Codex switchers, including `edihasaj/codex-account-switcher`. This implementation is independent and focuses on preserving one normal/default account while isolating only additional instances.

## License

MIT. See `LICENSE`.
