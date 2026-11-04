#!/bin/sh
# Gera dist/Correpetidor.app (release, com ícone .icns desenhado por appIcon()).
set -e
cd "$(dirname "$0")/.."
APP=dist/Correpetidor.app
TMP=$(mktemp -d)
# versão = última tag git (v1.2.3 → 1.2.3); build = nº de commits
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); VERSION=${VERSION:-0.0.0}
BUILD=$(git rev-list --count HEAD)

swift build -c release
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Correpetidor "$APP/Contents/MacOS/"

# ícone: reaproveita appIcon() do app e exporta o iconset
{ echo 'import AppKit'; sed -n '/^func appIcon/,/^}$/p' Sources/Correpetidor/CorrepetidorApp.swift; cat <<'SWIFT'
let img = appIcon(), out = CommandLine.arguments[1]
for s in [16, 32, 128, 256, 512] { for k in [1, 2] {
    let px = s * k
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(s)x\(s)" + (k == 2 ? "@2x" : "") + ".png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
} }
SWIFT
} > "$TMP/icon.swift"
mkdir -p "$TMP/AppIcon.iconset"
swift "$TMP/icon.swift" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Correpetidor</string>
  <key>CFBundleDisplayName</key><string>Correpetidor</string>
  <key>CFBundleIdentifier</key><string>dev.maykbrito.correpetidor</string>
  <key>CFBundleExecutable</key><string>Correpetidor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"   # assinatura ad-hoc (uso local)
rm -rf "$TMP"
echo "ok: $APP ($VERSION build $BUILD)"
