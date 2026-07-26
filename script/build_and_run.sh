#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Vitals"
BUNDLE_ID="com.eli.Vitals"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

stop_running_app() {
  local pids
  pids="$(pgrep -x "$APP_NAME" || true)"
  if [[ -z "$pids" ]]; then
    return
  fi

  kill $pids
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.25
  done

  echo "$APP_NAME did not exit" >&2
  exit 1
}

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/Vitals.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    build
  test -x "$APP_BINARY"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_running_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
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
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
