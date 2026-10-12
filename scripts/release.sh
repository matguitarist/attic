#!/bin/zsh
# Publishes the version in project.yml as a GitHub release that Sparkle
# offers to everyone running an older Attic:
#
#   scripts/release.sh
#
# Builds a universal app signed ad-hoc (no paid Developer ID, so no
# notarization), packs a disk image for new installs and a zip for Sparkle,
# uploads both as release v<version>, then adds the zip to appcast.xml and
# pushes that to main (the feed in Info.plist). Sparkle checks every update
# against the EdDSA key, so it doesn't need an Apple signature.
#
# The release notes are the last commit's message body, so commit the
# version bump as "Release x.y.z: summary" with notes as "- item" lines.
#
# Needs `gh` logged in, and Sparkle's EdDSA key in the login Keychain under
# the account "attic" (`generate_keys --account attic`, from the Sparkle
# tools this script downloads to .sparkle/). Its public half is
# SUPublicEDKey in Attic/Info.plist. Back the private half up with
# `.sparkle/bin/generate_keys --account attic -x <file>` and keep it safe:
# without it, no installed copy will ever accept an update again.
set -euo pipefail

ROOT="${0:A:h:h}"
REPO="matguitarist/attic"
SPARKLE_VERSION="2.10.0"   # keep in step with project.yml
SPARKLE="$ROOT/.sparkle"
WORK="$ROOT/.build-release"
RELEASES="$ROOT/dist/releases"

cd "$ROOT"

fail() { print -u2 "release: $*"; exit 1; }

# --- Preconditions ----------------------------------------------------------

[[ "$(git branch --show-current)" == "main" ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "uncommitted changes; commit the release first"

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" && -n "$BUILD" ]] || fail "couldn't read the version from project.yml"
TAG="v$VERSION"
git fetch --quiet --tags origin
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists; bump MARKETING_VERSION"

# Sparkle's command-line tools, from its official release.
if [[ ! -x "$SPARKLE/bin/generate_appcast" || "$(cat "$SPARKLE/VERSION" 2>/dev/null)" != "$SPARKLE_VERSION" ]]; then
    rm -rf "$SPARKLE" && mkdir -p "$SPARKLE"
    gh release download "$SPARKLE_VERSION" -R sparkle-project/Sparkle -p "Sparkle-$SPARKLE_VERSION.tar.xz" -D "$SPARKLE"
    tar -xf "$SPARKLE/Sparkle-$SPARKLE_VERSION.tar.xz" -C "$SPARKLE" bin
    echo "$SPARKLE_VERSION" > "$SPARKLE/VERSION"
fi

print "Releasing Attic $VERSION ($BUILD)"

# --- Build --------------------------------------------------------------------

rm -rf "$WORK" && mkdir -p "$WORK" "$RELEASES"
xcodegen generate --quiet
xcodebuild build \
    -project Attic.xcodeproj \
    -scheme Attic \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$WORK/derived" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    -quiet

APP="$WORK/Attic.app"
# No extended attributes: they break the code signature check.
ditto --noextattr --norsrc "$WORK/derived/Build/Products/Release/Attic.app" "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

# --- Sparkle archive and appcast --------------------------------------------

ZIP="$RELEASES/Attic-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Release notes from the commit message body: "- item" lines become a list.
NOTES_MD="$WORK/notes.md"
git log -1 --format=%b | grep -v '^Co-Authored-By:' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$NOTES_MD"
python3 - "$NOTES_MD" "$RELEASES/Attic-$VERSION.html" <<'EOF'
import html, sys
lines = open(sys.argv[1]).read().splitlines()
out, in_list = [], False
for line in lines:
    if line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{html.escape(line[2:])}</li>")
    else:
        if in_list: out.append("</ul>"); in_list = False
        if line.strip(): out.append(f"<p>{html.escape(line)}</p>")
if in_list: out.append("</ul>")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
EOF

# generate_appcast keeps every item already in the feed and adds the new
# archive, signed with the EdDSA key from the Keychain. It works on its own
# folder so older zips in dist/releases can't be picked up again under this
# release's download URL.
FEED="$WORK/feed"
mkdir -p "$FEED"
cp "$ZIP" "$RELEASES/Attic-$VERSION.html" "$FEED/"
[[ -f appcast.xml ]] && cp appcast.xml "$FEED/appcast.xml"
"$SPARKLE/bin/generate_appcast" \
    --account attic \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --maximum-versions 0 \
    --maximum-deltas 0 \
    "$FEED"
cp "$FEED/appcast.xml" "$RELEASES/appcast.xml"
grep -q "Attic-$VERSION.zip" "$RELEASES/appcast.xml" || fail "the appcast doesn't list Attic-$VERSION.zip"

# The disk image is for first installs. A fixed name keeps the README's
# ".../releases/latest/download/Attic.dmg" link working.
DMG="$RELEASES/Attic.dmg"
scripts/make_dmg.sh "$APP" "$DMG"

# --- Publish ----------------------------------------------------------------

git push origin main
gh release create "$TAG" "$DMG" "$ZIP" \
    -R "$REPO" \
    --target main \
    --title "Attic $VERSION" \
    --notes-file "$NOTES_MD"

# Last, so the feed never points at a download that doesn't exist yet.
cp "$RELEASES/appcast.xml" appcast.xml
git add appcast.xml
git commit -q -m "Appcast: Attic $VERSION"
git push origin main

print "Published https://github.com/$REPO/releases/tag/$TAG"
