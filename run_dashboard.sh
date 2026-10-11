#!/usr/bin/env bash
# run_dashboard.sh — Install dependencies and start the Flask dashboard.
#
# Automatically finds and installs each module's requirements.txt (walking up
# from the package directory registered in blueprints.json), then installs
# the project-level requirements and starts the app.
#
# Usage:
#   ./run_dashboard.sh                              # run with defaults
#   APP_PORT=8080 ./run_dashboard.sh                # custom port

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINTS_FILE="$SCRIPT_DIR/blueprints.json"
MODULES_TXT="$SCRIPT_DIR/modules.txt"
PYTHON="${PYTHON:-python3}"

# ── Runtime config ----------------------------------------------------------
APP_PORT="${APP_PORT:-5005}"
APP_HOST="${APP_HOST:-0.0.0.0}"

# ── Helpers ────────────────────────────────────────────────────────────────

json_module_count() {
  python3 -c "import json; print(len(json.load(open('$BLUEPRINTS_FILE'))['blueprints']))" 2>/dev/null || echo "0"
}

# ── Check modules / scaffold first run (only when empty) ───────────────────

count="$(json_module_count)"

if [ "$count" -eq 0 ]; then
  echo "No modules registered. Add one now."
  echo ""
  read -rp "Module name (blueprint variable, e.g. my_plugin_bp): " MOD_NAME
  read -rp "Module path (relative to this script's dir, e.g. modules/my_plugin): " MOD_PATH
  read -rp "URL prefix (e.g. /my_plugin): " URL_PREFIX

  python3 - "$BLUEPRINTS_FILE" "$MOD_NAME" "$MOD_PATH" "$URL_PREFIX" <<'PYEOF'
import json, sys
file, name, path, prefix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(file) as f:
    data = json.load(f)
data["blueprints"].append({"path": path, "name": name, "url_prefix": prefix})
with open(file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

  echo ""
  echo "Module registered in $BLUEPRINTS_FILE."
fi

# ── Write txt registry (synced from blueprints.json — source of truth) ─────

{
  echo "# Registered modules"
  python3 - "$BLUEPRINTS_FILE" <<'PYEOF' | sed 's/^/  /'
import json, sys
for e in json.load(open(sys.argv[1]))["blueprints"]:
    print(f"name={e['name']}")
    print(f"path={e['path']}")
    print(f"url_prefix={e.get('url_prefix', '')}")
    print("---")
PYEOF
} > "$MODULES_TXT"

# ── Install dependencies ───────────────────────────────────────────────────

python3 -c "
import json, os, subprocess, sys

script_dir = sys.argv[1]
blueprints_file = os.path.join(script_dir, 'blueprints.json')

with open(blueprints_file) as f:
    entries = json.load(f)['blueprints']

installed = set()  # avoid installing the same dir twice

for entry in entries:
    raw = entry['path']
    abs_dir = raw if os.path.isabs(raw) else os.path.join(script_dir, raw)

    # Walk up to 5 levels looking for requirements.txt
    for _ in range(6):
        req_file = os.path.join(abs_dir, 'requirements.txt')
        if os.path.isfile(req_file) and abs_dir not in installed:
            print(f'Installing module dependencies from {req_file} ...')
            subprocess.run(['pip', 'install', '-r', req_file], check=True)
            installed.add(abs_dir)
            break
        parent = os.path.dirname(abs_dir)
        if parent == abs_dir:
            break
        abs_dir = parent
" "$SCRIPT_DIR"

echo "Installing project dependencies..."
pip install -r "$SCRIPT_DIR/requirements.txt"

# ── Start the application ──────────────────────────────────────────────────

echo ""
echo "Starting dashboard on http://${APP_HOST}:${APP_PORT} ..."
export APP_HOST APP_PORT
exec "$PYTHON" "$SCRIPT_DIR/app.py"
