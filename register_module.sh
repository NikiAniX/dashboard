#!/usr/bin/env bash
# register_module.sh — Register a blueprint module in blueprints.json.
# Prompts for module_name, project_path and url_prefix, derives the blueprint path and name,
# reads <project_path>/swagger.json to add the job + run form to the dashboard, and appends the entry to blueprints.json. Refuses to register if the url_prefix is already used.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINTS_FILE="$SCRIPT_DIR/blueprints.json"
PYTHON="${PYTHON:-python3}"

command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }

[ -f "$BLUEPRINTS_FILE" ] || echo '{"blueprints": []}' > "$BLUEPRINTS_FILE"

read -rp "Module name (e.g. pdfDecryptor): " MODULE_NAME
read -rp "Project path (e.g. /Users/me/projectX/ecosystem/pdfDecryptor): " PROJECT_PATH
read -rp "URL prefix [/${MODULE_NAME}]: " URL_PREFIX
URL_PREFIX="${URL_PREFIX:-/$MODULE_NAME}"

if [ -z "$MODULE_NAME" ] || [ -z "$PROJECT_PATH" ]; then
  echo "module_name and project_path are required."
  exit 1
fi

# Expand a leading ~ and make the project path absolute
PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
[ -d "$PROJECT_PATH" ] || { echo "Project path does not exist: $PROJECT_PATH"; exit 1; }
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# Derived values: <project_path>/modules/<module_name> exporting <module_name>_bp
MOD_PATH="$PROJECT_PATH/modules/$MODULE_NAME"
MOD_NAME="${MODULE_NAME}_bp"

# Normalise: ensure a leading slash, strip trailing slash (but keep a lone "/")
[[ "$URL_PREFIX" == /* ]] || URL_PREFIX="/$URL_PREFIX"
[ "$URL_PREFIX" = "/" ] || URL_PREFIX="${URL_PREFIX%/}"

if jq -e --arg prefix "$URL_PREFIX" \
     '.blueprints | any(.url_prefix == $prefix)' "$BLUEPRINTS_FILE" >/dev/null; then
  echo "url_prefix '$URL_PREFIX' is already registered — not adding."
  exit 1
fi

# Add the endpoint as a job (jobsData in static/script.js) with its run form (templates/index.html)
SWAGGER_FILE="$PROJECT_PATH/swagger.json"
if [ -f "$SWAGGER_FILE" ]; then
  "$PYTHON" "$SCRIPT_DIR/swagger_dashboard.py" "$SWAGGER_FILE" "$MODULE_NAME" \
    "$SCRIPT_DIR/static/script.js" "$SCRIPT_DIR/templates/index.html" \
    || { echo "Could not add $SWAGGER_FILE to the dashboard — not registering."; exit 1; }
else
  echo "Warning: $SWAGGER_FILE not found — registering without a dashboard job/form."
fi

TMP_FILE="$(mktemp)"
jq --arg module_name "$MODULE_NAME" --arg project_path "$PROJECT_PATH" \
   --arg path "$MOD_PATH" --arg name "$MOD_NAME" --arg prefix "$URL_PREFIX" \
   '.blueprints += [{module_name: $module_name, project_path: $project_path, path: $path, name: $name, url_prefix: $prefix}]' \
   "$BLUEPRINTS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$BLUEPRINTS_FILE"

echo "Registered $MODULE_NAME (path=$MOD_PATH, name=$MOD_NAME, url_prefix=$URL_PREFIX). Restart the server to load it."
