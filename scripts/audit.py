#!/usr/bin/env python3
"""Static source-policy guard. This complements, but never replaces, tests and manual review."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
source_files = sorted([*(root / 'Sources').rglob('*'), *(root / 'Tools').rglob('*')])
source_files = [p for p in source_files if p.suffix in {'.swift', '.c', '.h'}]

forbidden = {
    'network API': r'\b(?:URLSession|URLRequest|NWConnection|NWListener|CFNetwork|WebKit|WKWebView)\b|import\s+Network\b|#include\s*[<"](?:sys/socket|netinet|curl)',
    'credential API': r'\b(?:SecItem\w*|SecKeychain\w*|LAContext|ASAuthorization\w*)\b',
    'environment/argv inspection': r'ProcessInfo[^\n]*\.environment|\b(?:getenv|KERN_PROCARGS2?|sysctl|proc_pidargs)\b',
    'shell/subprocess execution': r'\bProcess\s*\(|\bNSTask\b|(?<![.\w])(?:system|popen|execve)\s*\(',
    'credential file access': r'auth\.json|Cookies|Login Data|Local Storage|Session Storage',
    'privilege/destructive process API': r'\b(?:AuthorizationCreate|setuid|seteuid|kill|forceTerminate)\s*\(',
    'app/Dock mutation': r'com\.apple\.dock|persistent-apps|LSMultipleInstancesProhibited',
}

# These are architectural invariants, not just API bans. Current Account (.a) is discovery/focus
# only and must never get switcher-private storage or a switcher-owned launch receipt.
architecture_forbidden = {
    'private Current Account storage creation': r'\bprepare\s*\(\s*\.a\s*\)',
    'Current Account ownership receipt creation': r'LaunchReceipt\s*\(\s*profile\s*:\s*\.a\b',
}

failures = []
for path in source_files:
    text = path.read_text()
    for label, pattern in forbidden.items():
        for match in re.finditer(pattern, text):
            line = text.count('\n', 0, match.start()) + 1
            failures.append(f'{path.relative_to(root)}:{line}: {label}')

    # Legacy model types may mention `.a`, but executable source must not construct ownership or
    # private storage for it. Tests intentionally construct old receipts to prove migration safety.
    if 'Sources' in path.parts:
        for label, pattern in architecture_forbidden.items():
            for match in re.finditer(pattern, text):
                line = text.count('\n', 0, match.start()) + 1
                failures.append(f'{path.relative_to(root)}:{line}: {label}')

if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)

print('Source policy guard passed: no prohibited network, credential, environment, shell, force-kill, Dock mutation, Current-storage, or Current-ownership patterns.')
