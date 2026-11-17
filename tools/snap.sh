#!/bin/zsh
# Pictures of Cabinet Mode from a made-up library in /tmp, one PNG per
# built-in theme and Game Art, without opening the real library.
# Usage: tools/snap.sh
#        ATTIC_SNAPSHOT_THEMES=unboxed,shelf ATTIC_SNAPSHOT_ARTS=mix tools/snap.sh
#        SHOTS=/tmp/elsewhere tools/snap.sh
set -euo pipefail
ROOT="${0:A:h:h}"
shots=${SHOTS:-/tmp/Attic-shots}
rm -rf $shots
ATTIC_SNAPSHOT=$shots "$ROOT/dist/Attic.app/Contents/MacOS/Attic" -ApplePersistenceIgnoreState YES
