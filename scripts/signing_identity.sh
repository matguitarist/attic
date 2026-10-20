#!/bin/zsh
# Prints your "Developer ID Application" certificate (Xcode › Settings ›
# Accounts › Manage Certificates) if it's in the Keychain, else nothing:
# release.sh then signs ad hoc.
set -euo pipefail
security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true
