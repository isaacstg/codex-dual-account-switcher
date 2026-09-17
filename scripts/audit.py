#!/usr/bin/env python3
"""Source policy guard, not a substitute for human review or dynamic validation."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[1]
forbidden = {
    'network API': r'\b(?:URLSession|URLRequest|NWConnection|NWListener|CFNetwork|WebKit|WKWebView)\b|import\s+Network\b|#include\s*[<"](?:sys/socket|netinet|curl)',
    'credential API': r'\b(?:SecItem\w*|SecKeychain\w*|LAContext|ASAuthorization\w*)\b',
    'environment/argv inspection': r'ProcessInfo[^\n]*\.environment|\b(?:getenv|KERN_PROCARGS2?|sysctl|proc_pidargs)\b',
    'shell/subprocess execution': r'\bProcess\s*\(|\bNSTask\b|(?<![.\w])(?:system|popen|execve)\s*\(',
    'credential file access': r'auth\.json|Cookies|Login Data|Local Storage|Session Storage',
    'privilege/destructive process API': r'\b(?:AuthorizationCreate|setuid|seteuid|kill|forceTerminate)\s*\(',
    'app/Dock mutation': r'com\.apple\.dock|persistent-apps|LSMultipleInstancesProhibited',
}
failures = []
for path in sorted([*(root/'Sources').rglob('*'), *(root/'Tools').rglob('*')]):
    if path.suffix not in {'.swift', '.c', '.h'}:
        continue
    text = path.read_text()
    for label, pattern in forbidden.items():
        for match in re.finditer(pattern, text):
            line = text.count('\n', 0, match.start())+1
            failures.append(f'{path.relative_to(root)}:{line}: {label}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print('Source policy guard passed: no prohibited network, credential, environment, shell, force-kill, or Dock APIs.')
