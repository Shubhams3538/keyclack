#!/usr/bin/env bash
# Start/stop KeyClack from anywhere.
#   scripts/keyclack.sh start   build if the code changed since the last build, then launch
#   scripts/keyclack.sh stop    quit it
#
# Only rebuilds when needed: every rebuild of an ad-hoc signed app makes macOS ask for the
# Input Monitoring permission again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/KeyClack.app"
BIN="$APP/Contents/MacOS/KeyClack"

case "${1:-}" in
  start)
    if pgrep -x KeyClack >/dev/null; then
      echo "KeyClack is already running."
      exit 0
    fi
    if [[ ! -x "$BIN" ]] || [[ -n "$(find "$ROOT/Sources" "$ROOT/Resources" "$ROOT/Package.swift" -newer "$BIN" -print -quit)" ]]; then
      echo "Code changed, building KeyClack…"
      "$ROOT/scripts/build-app.sh" >/dev/null
      # The new build has a new code signature, so the old approval no longer applies but still
      # shows as "on" in System Settings. Clear it so macOS prompts again for this build.
      tccutil reset ListenEvent dev.keyclack.KeyClack >/dev/null 2>&1 || true
      echo "Rebuilt: macOS will ask for Input Monitoring permission again. Allow it."
    fi
    open "$APP"
    echo "KeyClack started. faaa."
    ;;
  stop)
    if pkill -x KeyClack; then
      echo "KeyClack stopped."
    else
      echo "KeyClack isn't running."
    fi
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
