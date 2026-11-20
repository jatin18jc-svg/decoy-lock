#!/bin/bash
# Builds a disk image to share: dist/Decoy-Lock-<version>.dmg
# It holds the app, a shortcut to Applications, and a note on getting past
# macOS's warning (the app is signed ad hoc, not notarized by Apple).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh"

APP="$ROOT/build.noindex/Decoy Lock.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build.noindex/dmg"
OUT="$ROOT/dist/Decoy-Lock-$VERSION.dmg"

echo "==> Staging"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
ditto "$APP" "$STAGE/Decoy Lock.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<'EOF'
Decoy Lock
==========
Made by Jatin Chutani.

Locks .xlsx, .docx, .pptx and .pdf files with two passwords: a real one that
opens the file, and a decoy word that opens a blank copy.

Needs macOS 14 or later. Works on Apple silicon and Intel Macs.

INSTALL
1. Drag "Decoy Lock" onto the Applications folder in this window.
2. Open Decoy Lock from Applications. macOS will say it can't check the app
   for malicious software, because it isn't notarized by Apple. Click Done.
3. Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to the message about Decoy Lock. Confirm with your
   password or Touch ID.
4. Open Decoy Lock again. Setup asks for your real password and decoy word.

To lock a file: right-click it in Finder > Services > Lock with Decoy Lock,
or drop it on the menu bar icon. Only files you lock open through Decoy Lock.

THINGS TO KNOW
- Forgot your password? Decoy Lock's Settings > Show Pair displays your usual
  pair after Touch ID or your Mac password. Files locked with a one-off pair
  can't be recovered.
- On a Mac without Decoy Lock, a locked file looks damaged and won't open.
- It stops someone looking over your shoulder, not a forensic investigation.
- Backups made before you locked a file still have it unlocked.
EOF

echo "==> Making disk image"
rm -f "$OUT"
hdiutil create -volname "Decoy Lock" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
# The staged copy is only for the disk image; don't leave a second app lying around.
rm -rf "$STAGE"

# A checksum lets the person you send it to confirm the download wasn't changed on the way.
( cd "$ROOT/dist" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

echo "==> $OUT ($(du -h "$OUT" | cut -f1))"
echo "    SHA-256: $(cut -d' ' -f1 "$OUT.sha256")"
