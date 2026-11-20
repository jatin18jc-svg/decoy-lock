#!/bin/bash
# Builds Decoy Lock, signs it ad hoc, puts it in /Applications and registers it
# with Launch Services and the Services menu. Run it again to update.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/Decoy Lock.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT/build.sh"

if pgrep -xq DecoyLock; then
  echo "==> Quitting the running copy"
  osascript -e 'tell application id "com.decoylock.app" to quit' >/dev/null 2>&1 || pkill -x DecoyLock || true
  # Wait for it to exit, so the launch below starts the new copy and isn't sent to the old one.
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq DecoyLock || break; sleep 0.5; done
  pkill -x DecoyLock 2>/dev/null || true
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto "$ROOT/build.noindex/Decoy Lock.app" "$DEST"
codesign --force --sign - --options runtime --timestamp=none "$DEST"

echo "==> Registering with Launch Services"
"$LSREGISTER" -f "$DEST"
# Only the copy in /Applications should ever answer for files.
"$LSREGISTER" -u "$ROOT/build.noindex/Decoy Lock.app" 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "==> Opening Decoy Lock"
open "$DEST"
echo "Done. Setup opens on first launch."
