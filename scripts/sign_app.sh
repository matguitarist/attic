#!/bin/zsh
# Signs a built Attic.app with your Developer ID (see signing_identity.sh)
# and Apple's secure timestamp, ready for notarize.sh:
#
#   scripts/sign_app.sh <Attic.app>      (SIGNING_IDENTITY overrides)
#
# Signs inside out, as Sparkle's documentation describes: its helpers, the
# framework, then the app with its own entitlements.
set -euo pipefail

APP="${1:?usage: sign_app.sh <Attic.app>}"
IDENTITY="${SIGNING_IDENTITY:-$("${0:A:h}/signing_identity.sh")}"
[[ -n "$IDENTITY" ]] || { print -u2 "sign_app: no Developer ID Application certificate in the Keychain"; exit 1; }

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@" }

# Extended attributes (Finder info, iCloud) make codesign fail.
xattr -cr "$APP"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE" ]]; then
    sign "$SPARKLE/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Autoupdate"
    sign "$SPARKLE/Updater.app"
    sign "$APP/Contents/Frameworks/Sparkle.framework"
fi

# The app keeps the entitlements it was built with (Attic.entitlements),
# never get-task-allow: a release shouldn't let other processes attach to it.
ENTITLEMENTS=$(mktemp -t attic-entitlements).plist
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENTITLEMENTS" >/dev/null 2>&1 || true
sign --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"

codesign --verify --deep --strict "$APP"
print "Signed ${APP:t} with “$IDENTITY”"
