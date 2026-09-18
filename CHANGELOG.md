# Changelog

## Public project presentation

- Introduce Pairbar as the public project identity, with an original vector mark, banner, and social-preview asset.
- Make the README focus on the workflow, setup, security boundaries, and accurate validation evidence; move the detailed manual to `docs/USER_GUIDE.md`.
- Add an engineering case study documenting product decisions, implementation trade-offs, and AI-assisted development for portfolio readers.
- Rename the public repository to `isaacstg/pairbar`; update badges, clone instructions, documentation links, and the project homepage. The old GitHub URL redirects.
- Retain compatibility-sensitive installed 1.3 names and identifiers.

## 1.3.0 — Menu-bar experience

- Replace the long menu and detached settings/diagnostics windows with a native menu-bar popover.
- Keep Accounts focused on two account cards and Open Both; move Second quit/restart into its ownership-gated More menu.
- Introduce clear Set Up Second Account and Confirm ChatGPT Update actions, with automatic app checking and technical details kept in Help.
- Separate Save Names from app-version confirmation; validate labels without modifying approval or setup.
- Show errors inline, reopen the popover after shortcut errors, and dismiss it after successful account activation.
- Group startup at login, diagnostics, recovery, archive/reset, uninstall, and version information into Settings/Help.
- Add keyboard dismissal, native Shift-Command-B back navigation, accessibility labels, long-label support, and safe scratch-preview validation.
- Refuse app-version confirmation during recovery or an account lifecycle action; recheck state after asynchronous inspection.
- Preserve the bundle identifier, private root, settings schema, existing sign-ins, storage isolation, hotkeys, and graceful-only process ownership policy.

## 1.2.0 — Current + Second architecture

- Preserve the user's normal Current account and isolate only Second.
- Add typed account state, conservative Current discovery, verified Second receipts, pending-launch quarantine, update fingerprint checks, metadata-only migration, and archive/reset.
- Expand static policy audit and unit tests; validate builds on macOS 14 and 15.
- Keep the switcher local-only and independent of credentials, cookies, Keychain data, process arguments/environments, and official-app modifications.
