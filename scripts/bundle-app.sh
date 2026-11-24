#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="XMPro"
BUNDLE_ID="studio.teikeng.xmpro.mac"
VERSION="1.0.0"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
TMP_ICONSET="$ROOT_DIR/.build/AppIcon.iconset"

cd "$ROOT_DIR"

echo "==> 1/4 编译 Release 原生二进制..."
swift build -c release
BIN_PATH="$ROOT_DIR/.build/release/XMProMac"

echo "==> 2/4 生成原生高清应用图标 (AppIcon.icns)..."
rm -rf "$TMP_ICONSET"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$TMP_ICONSET"

echo "==> 3/4 组装 $APP_NAME.app 目录结构..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/XMProMac"
chmod +x "$APP_BUNDLE/Contents/MacOS/XMProMac"
iconutil -c icns "$TMP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$TMP_ICONSET"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>XMPro</string>
    <key>CFBundleExecutable</key>
    <string>XMProMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>XMPro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
EOF

echo "==> 4/4 执行本地 ad-hoc 代码签名..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ 打包完成: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
