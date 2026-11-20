#!/bin/bash
# Builds "Decoy Lock.app" into ./build.noindex (the suffix keeps Spotlight from
# indexing it, so macOS never offers this copy in Open With), universal (Apple silicon + Intel), ad-hoc signed.
# Works with just the Xcode Command Line Tools; full Xcode isn't needed.
#
#   ./build.sh            release build
#   ./build.sh --test     build, then run the self-test (add --large for the 100 MB case)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build.noindex"
APP="$BUILD/Decoy Lock.app"
SDK="$(xcrun --show-sdk-path)"
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' -print0 | sort -z)

echo "==> Compiling ${#SOURCES[@]} files"
mkdir -p "$BUILD/obj"
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -wmo -swift-version 5 \
    -target "$ARCH-apple-macos14.0" -sdk "$SDK" \
    -module-name DecoyLock \
    -o "$BUILD/obj/DecoyLock-$ARCH" \
    "${SOURCES[@]}"
done

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Decoys"
lipo -create "$BUILD/obj/DecoyLock-arm64" "$BUILD/obj/DecoyLock-x86_64" -output "$APP/Contents/MacOS/DecoyLock"
printf 'APPL????' > "$APP/Contents/PkgInfo"

python3 -I "$ROOT/tools/make_decoys.py" "$APP/Contents/Resources/Decoys" > /dev/null
"$APP/Contents/MacOS/DecoyLock" --info-plist "$APP/Contents/Info.plist"

ICONSET="$BUILD/obj/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/DecoyLock" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad hoc)"
# Hardened runtime: blocks code injection and debugger attach, as notarized apps require.
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict "$APP"

# Launch Services notices new apps on disk. Keep this copy out of it, so only the
# one in /Applications ever answers for file types.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true

echo "==> Built $APP"

if [[ "${1:-}" == "--test" ]]; then
  shift
  echo "==> Self-test"
  "$APP/Contents/MacOS/DecoyLock" --selftest "$@"
fi
