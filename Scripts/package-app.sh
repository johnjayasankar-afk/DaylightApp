#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/release/Daylight"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/out/Products/Release/Daylight"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Build the Daylight executable first: make build" >&2
  exit 1
fi

VERSION_LINE="$(python3 - <<PY
import pathlib, re
text = pathlib.Path("$ROOT/Sources/DaylightCore/Brand.swift").read_text()
version = re.search(r'marketingVersion = "([^"]+)"', text).group(1)
build = re.search(r'buildNumber = "([^"]+)"', text).group(1)
year = re.search(r'copyrightYear = "([^"]+)"', text).group(1)
print(f"{version}\t{build}\t{year}")
PY
)"
VERSION="${VERSION_LINE%%$'\t'*}"
REST="${VERSION_LINE#*$'\t'}"
BUILD="${REST%%$'\t'*}"
YEAR="${REST##*$'\t'}"

APP="$ROOT/dist/Daylight.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/Daylight"
chmod +x "$MACOS/Daylight"
printf 'APPL????' > "$CONTENTS/PkgInfo"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Daylight</string>
  <key>CFBundleExecutable</key>
  <string>Daylight</string>
  <key>CFBundleGetInfoString</key>
  <string>Daylight ${VERSION} (${BUILD}), © ${YEAR}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>app.daylight.Daylight</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Daylight</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>© ${YEAR} Daylight</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
</dict>
</plist>
PLIST

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  "$ROOT/Scripts/generate-icon.sh" || true
fi
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
fi

echo "Built $APP ($VERSION $BUILD)"
echo "The app is not signed or notarized."
