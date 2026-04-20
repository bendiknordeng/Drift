#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Drift}"
BUNDLE_ID="${BUNDLE_ID:-ai.edda.drift}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
ARCH="${ARCH:-arm64}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
PKG_ROOT="$DIST_DIR/pkgroot"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PKG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH.pkg"

cd "$REPO_ROOT"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Building $APP_NAME $VERSION for $ARCH..."
swift build -c release --arch "$ARCH" --product "$APP_NAME"
BIN_DIR="$(swift build -c release --arch "$ARCH" --product "$APP_NAME" --show-bin-path)"
BINARY_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
    echo "Expected executable at $BINARY_PATH" >&2
    exit 1
fi

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if command -v lipo >/dev/null 2>&1; then
    if ! lipo -archs "$MACOS_DIR/$APP_NAME" | grep -qw "$ARCH"; then
        echo "Built executable does not contain $ARCH:" >&2
        lipo -archs "$MACOS_DIR/$APP_NAME" >&2
        exit 1
    fi
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -d "$REPO_ROOT/Sources/Assets.xcassets" ]]; then
    echo "Compiling asset catalog..."
    xcrun actool "$REPO_ROOT/Sources/Assets.xcassets" \
        --compile "$RESOURCES_DIR" \
        --platform macosx \
        --minimum-deployment-target "$MIN_MACOS_VERSION" \
        --app-icon AppIcon \
        --output-partial-info-plist "$DIST_DIR/assetcatalog-info.plist" \
        --output-format human-readable-text
fi

find "$APP_DIR" -name ".DS_Store" -delete
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "Ad-hoc signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
ditto --norsrc "$APP_DIR" "$PKG_ROOT/Applications/$APP_NAME.app"
xattr -cr "$PKG_ROOT" 2>/dev/null || true

echo "Building installer package..."
COPYFILE_DISABLE=1 pkgbuild \
    --root "$PKG_ROOT" \
    --install-location / \
    --identifier "$BUNDLE_ID.pkg" \
    --version "$VERSION" \
    --ownership recommended \
    --filter '(^|/)\.DS_Store$' \
    --filter '(^|/)\._[^/]*$' \
    --filter '(^|/)CVS($|/)' \
    --filter '(^|/)\.svn($|/)' \
    "$PKG_PATH"

echo "Created $PKG_PATH"
