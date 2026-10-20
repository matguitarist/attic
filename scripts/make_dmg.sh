#!/bin/zsh
# Packs an Attic.app into a drag-to-install disk image:
#
#   scripts/make_dmg.sh <Attic.app> <out.dmg>
#
# The window shows the app, an Applications shortcut, and (unless
# NOTARIZED is set) a note about macOS's warning for apps that aren't
# notarized.
set -euo pipefail

APP="${1:?usage: make_dmg.sh <Attic.app> <out.dmg>}"
OUT="${2:?usage: make_dmg.sh <Attic.app> <out.dmg>}"
[[ -d "$APP" ]] || { print -u2 "No app at $APP"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# No extended attributes: they break the app's code signature check.
ditto --noextattr --norsrc "$APP" "$STAGE/Attic.app"
xattr -cr "$STAGE/Attic.app"
ln -s /Applications "$STAGE/Applications"
# Notarized apps open without a warning: the note is for the others.
[[ -n "${NOTARIZED:-}" ]] || cat > "$STAGE/If macOS blocks Attic.txt" <<'NOTE'
Install: drag Attic onto the Applications folder.

The first time you open it, macOS may say it can't check Attic for
malicious software, because it isn't signed with a paid Apple Developer ID.
To open it anyway:

  1. Try to open Attic once, then click Done.
  2. Open System Settings > Privacy & Security.
  3. Scroll down and click "Open Anyway" next to Attic, then confirm.

You only do this once; updates install without asking again.

---

Installation : glissez Attic sur le dossier Applications.

À la première ouverture, macOS peut dire qu'il ne peut pas vérifier
Attic, car l'app n'est pas signée avec un identifiant de développeur
Apple payant. Pour l'ouvrir quand même :

  1. Essayez d'ouvrir Attic une fois, puis cliquez sur Terminé.
  2. Ouvrez Réglages Système > Confidentialité et sécurité.
  3. Faites défiler et cliquez sur « Ouvrir quand même » à côté
     d'Attic, puis confirmez.

Une seule fois suffit : les mises à jour s'installent ensuite sans
redemander.
NOTE

mkdir -p "${OUT:h}"
rm -f "$OUT"
hdiutil create -volname "Attic" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
echo "Created $OUT"
