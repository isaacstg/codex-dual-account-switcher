# Security Model

## Scope

Codex Account Switcher provides **profile separation**, not a macOS security sandbox.

The design has two different trust/ownership roles:

- **Current account:** the user's ordinary official ChatGPT/Codex profile. The switcher may discover, open and focus it, but intentionally does not own its lifecycle.
- **Second account:** an official ChatGPT instance launched with separate Electron and Codex directories. The switcher may focus, gracefully quit or restart it only while strong process ownership can be proven.

Both instances still execute as the same macOS user and therefore share that user's OS-level permissions, Keychain namespace, shell configuration, browser/OAuth environment and other resources. The switcher does not claim to protect one account from a malicious application running as the same user.

## Security invariants

1. The official `ChatGPT.app` is never modified, patched, copied, re-signed, injected into, or rewritten.
2. Current uses normal/default ChatGPT storage and normal `~/.codex`.
3. Only Second receives private Electron/Codex storage overrides.
4. Authentication tokens, cookies, browser stores, account identities and Keychain credentials are never copied, parsed, migrated or inspected.
5. The switcher does not inspect another process's argv or environment.
6. The switcher does not use networking.
7. The switcher does not execute a shell/subprocess to control ChatGPT.
8. Current is never destructively controlled by the switcher.
9. Second is never destructively controlled unless ownership is positively verified.
10. ChatGPT is never force-killed.
11. Ambiguity fails closed: the switcher blocks/asks for manual resolution rather than guessing.

## Current-account discovery

The switcher enumerates running applications with the official ChatGPT bundle identifier. It does not inspect credentials or private profile contents to identify accounts.

If Second ownership is positively verified, only that exact PID is excluded from the set of default candidates.

- 0 remaining candidates: Current is considered not running.
- 1 remaining candidate: it may be focused as Current.
- More than 1: Current is ambiguous and focus-by-discovery is blocked.

This means the switcher can occasionally require manual cleanup when multiple normal ChatGPT instances exist. That inconvenience is intentional; choosing a process heuristically would weaken the ownership boundary.

## Second-account isolation

Second uses switcher-private paths under:

```text
~/Library/Application Support/Codex Dual Account Switcher/Profiles/b/
```

Its launch receives an allowlisted environment plus:

```text
CODEX_HOME=<private>/Profiles/b/codex
CODEX_ELECTRON_USER_DATA_PATH=<private>/Profiles/b/electron
--user-data-dir=<private>/Profiles/b/electron
```

The switcher does not forward arbitrary environment variables. In particular, inherited API keys/tokens, `NODE_OPTIONS`, `DYLD_*` and Electron debugging variables are not intentionally forwarded.

## Process ownership

A Second launch receipt records only switcher-owned process metadata:

- profile role (`b`);
- PID;
- UID;
- kernel process start time;
- executable path;
- expected private Codex/Electron paths.

Ownership requires the current kernel snapshot to exactly match the receipt and the current macOS user. This rejects stale PIDs, PID reuse, wrong users, wrong executable paths and receipts for different private paths.

A launch is adopted only when it is a newly observed process, starts after the launch request, runs as the current user and has the expected official executable path.

The receipt does not prove that the application internally honored every storage override. That is why compatibility validation and the separate opt-in smoke test remain necessary.

## Interrupted launches

Before Second is launched, a pending marker is persisted. If launch completion cannot be safely proven, that marker remains and another launch is blocked.

Recovery requires all official ChatGPT instances to be closed manually. The recovery operation clears switcher ownership/pending metadata only; it does not delete account/profile contents.

A clearly dead stale receipt may be removed automatically. A live process whose identity no longer matches the receipt is not terminated or adopted.

## Legacy migration

Older builds treated both A and B as isolated profiles. New builds discard A process receipts and A pending markers because A now means Current/default.

Migration is metadata-only. Legacy A directories are deliberately left on disk and their contents are not read. Valid B metadata is retained. Duplicate B ownership receipts are treated as invalid metadata rather than guessed through.

## Private filesystem storage

Switcher metadata and isolated Second directories use restrictive POSIX permissions. Metadata writes use the existing hardened `PrivateStore` behavior to reject unsafe names and redirected/symlinked paths and to avoid following unsafe metadata links.

The controller lock prevents two switcher controllers from concurrently managing the same private root.

These defenses reduce accidental/cross-process corruption but are not a defense against a fully malicious process running with the same macOS user privileges.

## Compatibility validation

The switcher validates the selected official app before approving isolated-account operation. The compatibility layer checks the expected official bundle/signature properties and the markers required by the isolation mechanism, then fingerprints relevant installed-app material.

If the approved fingerprint changes, Second launching is blocked until the changed build is reviewed and explicitly approved.

Compatibility checks are evidence that the expected mechanism still appears to exist; they are not proof of runtime account isolation.

## Graceful termination only

The switcher calls the normal application termination request only for a verified Second process. It waits for graceful exit and cancels restart after timeout. It never escalates to a forced kill.

Current must be quit/restarted from the official ChatGPT app itself.

## Logging and diagnostics

Logs are bounded and memory-only. Diagnostic output contains switcher state, app/compatibility metadata, process status and private-root location.

It must not contain:

- account email/name/identity discovered from ChatGPT;
- auth tokens;
- cookies/browser stores;
- Keychain credential values;
- ChatGPT application logs;
- another process's environment or command-line arguments.

`Copy Diagnostics` copies only this switcher-generated text.

## Source policy audit

`scripts/audit.py` is a guardrail that rejects source patterns associated with networking, credential APIs/files, process environment/argv inspection, shell execution, destructive/privileged process APIs and app/Dock mutation.

It is intentionally not presented as a formal security proof. Human review, unit tests, app-signature validation and runtime smoke validation are separate layers.

## Threats deliberately not solved

The switcher does not attempt to defend against:

- malware or a malicious account with the same macOS user privileges;
- the official app intentionally reading shared OS resources;
- browser OAuth choosing the wrong browser account;
- upstream changes that defeat isolation despite retaining static markers;
- compromise of the user's macOS account;
- a malicious replacement application explicitly approved by the user outside the switcher's intended workflow.

Users should verify the displayed ChatGPT account before sensitive work, especially immediately after signing in or after an app update.

## Reporting

Do not include real authentication tokens, cookies, account exports or other secrets in bug reports. Prefer the switcher's generated diagnostics and a description of the observed behavior.
