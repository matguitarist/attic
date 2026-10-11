#!/bin/zsh
# Refreshes the String Catalogs (Localizable.xcstrings) from the source code,
# the way Xcode does when building in the IDE — `xcodebuild` extracts the
# strings but never writes them back to the catalogs. Run after changing any
# user-visible text, then commit the updated catalogs for translators.
#
#   scripts/sync-strings.sh
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED="$ROOT/.build-xcode-strings"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild \
    -project RomsBox.xcodeproj \
    -scheme RomsBox \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    build

# Unregister the throwaway app this build produced, so Launch Services
# (Spotlight, `open -a RomsBox`, AppleScript) never picks it over dist/.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$DERIVED/Build/Products/Debug/RomsBox.app" 2>/dev/null || true

INTERMEDIATES="$DERIVED/Build/Intermediates.noindex"

# catalog → the build folder holding that target's extracted strings
sync() {
    local catalog="$1" target_dir="$2"
    local -a files
    files=("${(@f)$(find "$INTERMEDIATES/$target_dir" -name '*.stringsdata')}")
    xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
    echo "$(xcrun xcstringstool print "$catalog" | grep -c '^') keys in ${catalog#$ROOT/}"
}

sync "$ROOT/RomsBox/Localizable.xcstrings" "RomsBox.build"
sync "$ROOT/RomsBoxKit/Sources/RomsBoxEmulation/Resources/Localizable.xcstrings" "RomsBoxKit.build/Debug/RomsBoxEmulation-t.build"
