#!/usr/bin/env bash
# register_module.sh — Register or remove a blueprint module in blueprints.json and modules.txt.
#
# Usage:
#   ./register_module.sh                              # register (interactive prompts)
#   ./register_module.sh --name my_bp --path path/to  # register (non-interactive)
#   ./register_module.sh --delete pdfDecryptor_bp     # delete a module by name or path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINTS_FILE="$SCRIPT_DIR/blueprints.json"
MODULES_TXT="$SCRIPT_DIR/modules.txt"

PYTHON="${PYTHON:-python3}"

# ── Argument parsing ───────────────────────────────────────────────────────

MOD_NAME=""
MOD_PATH=""
URL_PREFIX=""
DELETE_TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     MOD_NAME="$2";   shift 2 ;;
    --path)     MOD_PATH="$2";   shift 2 ;;
    --prefix)   URL_PREFIX="$2"; shift 2 ;;
    --delete)
      DELETE_TARGET="$2"; shift 2 ;;
    --help|-h)
      echo "Usage:"
      echo "  $0 [--name NAME] [--path PATH] [--prefix PREFIX]   Register a module"
      echo "  $0 --delete TARGET                                  Remove a module"
      echo ""
      echo "Register:"
      echo "  All three flags are optional — omitting one triggers an interactive prompt."
      echo ""
      echo "Delete:"
      echo "  TARGET can be the module name, its path, or 'all' to remove every module."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Read / create blueprints.json ─────────────────────────────────────────

if [ ! -f "$BLUEPRINTS_FILE" ]; then
  echo '{"blueprints": []}' > "$BLUEPRINTS_FILE"
fi

# ── Delete flow ────────────────────────────────────────────────────────────

if [ -n "$DELETE_TARGET" ]; then
  python3 - "$BLUEPRINTS_FILE" "$MODULES_TXT" "$DELETE_TARGET" <<'PYEOF'
import json, sys, os

file_path, txt_path, target = sys.argv[1], sys.argv[2], sys.argv[3].strip().lower()

with open(file_path) as f:
    data = json.load(f)

original_count = len(data["blueprints"])

if target == "all":
    if original_count == 0:
        print("Nothing to delete — no modules are registered.")
        sys.exit(0)
    removed = data["blueprints"]
    data["blueprints"] = []
else:
    matched = [e for e in data["blueprints"]
               if e["name"].lower() == target or e.get("path", "").lower() == target]
    if not matched:
        print(f"No module found matching '{target}'.")
        sys.exit(1)
    removed = matched
    data["blueprints"] = [e for e in data["blueprints"] if e not in removed]

if len(data["blueprints"]) == original_count:
    print(f"No module found matching '{target}'.")
    sys.exit(1)

with open(file_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Deleted {len(removed)} module(s):")
for e in removed:
    print(f"  - {e['name']} ({e.get('path', 'N/A')})")

# Re-sync txt registry from blueprints.json (source of truth)
with open(txt_path, "w") as f:
    f.write("# Registered modules\n")
    for e in data["blueprints"]:
        f.write(f"name={e['name']}\n")
        f.write(f"path={e['path']}\n")
        if e.get("url_prefix"):
            f.write(f"url_prefix={e['url_prefix']}\n")
        f.write("---\n")

print(f"Remaining: {len(data['blueprints'])} module(s).")
PYEOF

  exit 0
fi

# ── Interactive prompts (register flow) ────────────────────────────────────

if [ -z "$MOD_NAME" ] || [ -z "$MOD_PATH" ] || [ -z "$URL_PREFIX" ]; then
  [ -z "$MOD_NAME" ] && read -rp "Module name (blueprint variable, e.g. my_plugin_bp): " MOD_NAME
  [ -z "$MOD_PATH" ]   && read -rp "Module path (relative to this script's dir, e.g. modules/my_plugin): " MOD_PATH
  [ -z "$URL_PREFIX" ] && read -rp "URL prefix (e.g. /my_plugin): " URL_PREFIX
fi

# ── Validate: normalize relative path if needed ─────────────────────────────

case "$MOD_PATH" in
  ./*) MOD_PATH="${MOD_PATH#./}" ;;
  /*)  # Absolute paths are fine — app.py resolves them via BASE_DIR / path
    ;;
  *)   # Bare name, assume modules/<name>
    MOD_PATH="modules/$MOD_PATH"
    ;;
esac

# ── Duplicate check (before anything else) ─────────────────────────────────

python3 - "$BLUEPRINTS_FILE" "$MOD_NAME" "$MOD_PATH" <<'PYEOF'
import json, sys
from pathlib import Path

file_path, mod_name, mod_path = sys.argv[1], sys.argv[2], sys.argv[3]
BASE_DIR = Path(file_path).parent.resolve()

with open(file_path) as f:
    data = json.load(f)

for entry in data["blueprints"]:
    # Normalize both paths to absolute for reliable comparison
    a = (Path(BASE_DIR) / entry["path"]).resolve().as_posix()
    b = (Path(BASE_DIR) / mod_path).resolve().as_posix()
    if entry["name"] == mod_name or a == b:
        print(f"Already registered: '{entry['name']}' / '{entry['path']}'.")
        sys.exit(1)
PYEOF


# ── Create module directory if needed ───────────────────────────────────────

MODULE_DIR="$SCRIPT_DIR/$MOD_PATH"

if [ ! -d "$MODULE_DIR" ]; then
  echo "Module path does not exist: $MOD_PATH"
  read -rp "  Create it now? [y/N] " CREATE_DIR
  if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
    mkdir -p "$MODULE_DIR"
    cat > "$MODULE_DIR/__init__.py" <<PYEOF
#!/usr/bin/env python3
\"\"\"$MOD_NAME — blueprint module.\"\"\"

from __future__ import annotations

from flask import Blueprint

bp = Blueprint("$MOD_NAME", __name__, url_prefix="$URL_PREFIX")
PYEOF

    cat > "$MODULE_DIR/routes.py" <<PYEOF
#!/usr/bin/env python3
\"\"\"Routes for $MOD_NAME.\"\"\"

from . import bp

@bp.route("/")
def index():
    return "Hello from $MOD_NAME"
PYEOF
    echo "Scaffolded module at $MOD_PATH."
  else
    echo "Aborted — directory not created."
    exit 1
  fi
fi

# ── Register in blueprints.json (pure Python for safety) ───────────────────

python3 - "$BLUEPRINTS_FILE" "$MOD_NAME" "$MOD_PATH" "$URL_PREFIX" <<'PYEOF'
import json, sys

file_path, mod_name, mod_path, url_prefix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(file_path) as f:
    data = json.load(f)

# Double-check (defense in depth — the bash block did the first pass above)
for entry in data["blueprints"]:
    if entry["name"] == mod_name or entry.get("path") == mod_path:
        print(f"Already registered: '{mod_name}' / '{mod_path}'.")
        sys.exit(1)

data["blueprints"].append({
    "path": mod_path,
    "name": mod_name,
    "url_prefix": url_prefix,
})

with open(file_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

# ── Sync txt registry from blueprints.json (single source of truth) ───────

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

echo "Registered $MOD_NAME (prefix=$URL_PREFIX) → blueprints.json, modules.txt."
