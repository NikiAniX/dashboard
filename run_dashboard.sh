#!/usr/bin/env bash
# run_dashboard.sh — Install each registered module's requirements, then start the dashboard.
# Refuses to start when blueprints.json has no registered modules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINTS_FILE="$SCRIPT_DIR/blueprints.json"

PYTHON="${PYTHON:-python3}"
APP_PORT="${APP_PORT:-5005}"
APP_HOST="${APP_HOST:-0.0.0.0}"

command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
[ -f "$BLUEPRINTS_FILE" ] || { echo "blueprints.json not found. Run ./register_module.sh first."; exit 1; }

MODULE_COUNT="$(jq '.blueprints | length' "$BLUEPRINTS_FILE")"
if [ "$MODULE_COUNT" -eq 0 ]; then
  echo "No modules registered in blueprints.json. Run ./register_module.sh first."
  exit 1
fi

# Install requirements for each registered module (project_path may be absolute or relative to this dir)
while IFS= read -r PROJECT_PATH; do
  case "$PROJECT_PATH" in
    /*) MODULE_DIR="$PROJECT_PATH" ;;
    *)  MODULE_DIR="$SCRIPT_DIR/$PROJECT_PATH" ;;
  esac

  REQ_FILE="$MODULE_DIR/requirement.txt"
  [ -f "$REQ_FILE" ] || REQ_FILE="$MODULE_DIR/requirements.txt"

  if [ -f "$REQ_FILE" ]; then
    echo "Installing requirements for $PROJECT_PATH ..."
    "$PYTHON" -m pip install -r "$REQ_FILE"
  else
    echo "No requirements file in $PROJECT_PATH — skipping."
  fi
done < <(jq -r '.blueprints[].project_path' "$BLUEPRINTS_FILE")

# Install the dashboard's own requirements
echo "Installing requirements for dashboard ..."
"$PYTHON" -m pip install -r "$SCRIPT_DIR/requirements.txt"

echo ""
echo "Starting dashboard on http://${APP_HOST}:${APP_PORT} ..."
export APP_HOST APP_PORT
exec "$PYTHON" "$SCRIPT_DIR/app.py"
