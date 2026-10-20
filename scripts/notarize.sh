#!/bin/zsh
# Sends a Developer ID-signed app or disk image to Apple's notary service,
# waits for its approval, and staples the ticket to it, so macOS opens it
# without the "can't check for malicious software" warning, even offline:
#
#   scripts/notarize.sh <Attic.app | Attic.dmg>
#
# Needs the credentials saved once (shared with Starseed and Tadpole) with:
#   xcrun notarytool store-credentials ares-notary --apple-id <you> --team-id <TEAMID>
# (NOTARY_PROFILE picks another name.)
set -euo pipefail

TARGET="${1:?usage: notarize.sh <Attic.app | Attic.dmg>}"
PROFILE="${NOTARY_PROFILE:-ares-notary}"

# notarytool takes a zip, a disk image or a package: an app goes as a zip.
UPLOAD="$TARGET"
if [[ "$TARGET" == *.app ]]; then
    UPLOAD=$(mktemp -d)/"${TARGET:t:r}.zip"
    ditto -c -k --norsrc --noextattr --keepParent "$TARGET" "$UPLOAD"
fi

print "Notarizing ${TARGET:t} (Apple usually answers within a few minutes)"
RESULT=$(xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait --output-format json)
STATUS=$(print -r -- "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
ID=$(print -r -- "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
if [[ "$STATUS" != "Accepted" ]]; then
    print -u2 "Notarization: $STATUS. Apple's log:"
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
    exit 1
fi

xcrun stapler staple "$TARGET" >/dev/null
xcrun stapler validate "$TARGET" >/dev/null
if [[ "$TARGET" == *.dmg ]]; then
    spctl --assess --type open --context context:primary-signature "$TARGET"
else
    spctl --assess --type execute "$TARGET"
fi
print "Notarized and stapled ${TARGET:t}"
