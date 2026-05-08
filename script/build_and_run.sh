#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ZuTun"
BUNDLE_ID="dev.jonaslaux.ZuTun"
WIDGET_NAME="ZuTunWidgetExtension"
WIDGET_BUNDLE_ID="$BUNDLE_ID.WidgetExtension"
CONFIGURATION="${ZUTUN_CONFIGURATION:-Release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALL_DIR="${ZUTUN_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
INSTALLED_WIDGET_BUNDLE="$INSTALLED_APP_BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodegen generate >/dev/null
xcodebuild \
  -project "$ROOT_DIR/ZuTun.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP_BUNDLE"
ditto "$BUILT_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/pluginkit -a "$INSTALLED_WIDGET_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/pluginkit -e use -i "$WIDGET_BUNDLE_ID" >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify-widget|verify-widget)
    /usr/bin/pluginkit -m -p com.apple.widgetkit-extension -i "$WIDGET_BUNDLE_ID" | grep -q "$WIDGET_BUNDLE_ID"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-widget]" >&2
    exit 2
    ;;
esac
