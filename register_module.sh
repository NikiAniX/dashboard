#!/usr/bin/env bash
# register_module.sh — Register or remove a blueprint module in blueprints.json and modules.txt.
# Also manages dashboard UI cards (task-grid divs + modals).
#
# Usage:
#   ./register_module.sh                              # register (interactive prompts)
#   ./register_module.sh --name my_bp --path path/to  # register (non-interactive)
#   ./register_module.sh --delete pdfDecryptor_bp     # delete a module by name or path
#   ./register_module.sh --sync                       # regenerate task-grid cards for all registered modules
#   ./register_module.sh --name gdDownloader_bp ... --dashboard                    # also add to task-grid
#   ./register_module.sh --dashboard-delete gdDownloader_bp                        # remove from task-grid

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
SYNC=false
DASHBOARD=false
DASHBOARD_DELETE=""

# Dashboard task-grid injection flags (used with --dashboard or standalone)
DS_TITLE=""
DS_TAG=""
DS_ICON=""       # emoji character, e.g. "📥"
DS_DESC=""       # brief description
DS_MODAL_FIELDS=""  # pipe-delimited: label|type|id[;...]; repeat per field

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     MOD_NAME="$2";   shift 2 ;;
    --path)     MOD_PATH="$2";   shift 2 ;;
    --prefix)   URL_PREFIX="$2"; shift 2 ;;
    --delete)
      DELETE_TARGET="$2"; shift 2 ;;
    --sync)
      SYNC=true; shift ;;
    --dashboard)
      DASHBOARD=true; shift ;;
    --dashboard-fields)
      DS_MODAL_FIELDS="$2"; shift 2 ;;
    --dashboard-delete)
      DASHBOARD_DELETE="$2"; shift 2 ;;
    --title)   DS_TITLE="$2"; shift 2 ;;
    --tag)     DS_TAG="$2"; shift 2 ;;
    --icon)    DS_ICON="$2"; shift 2 ;;
    --desc)    DS_DESC="$2"; shift 2 ;;
    --help|-h)
      echo "Usage:"
      echo "  $0 [--name NAME] [--path PATH] [--prefix PREFIX]   Register a module"
      echo "  $0 --delete TARGET                                  Remove a module"
      echo "  $0 --sync                                         Regenerate all task-grid cards"
      echo "  $0 --dashboard --name N --path P --prefix U         Register + add to task-grid"
      echo "  $0 --dashboard-delete TARGET                        Remove from task-grid"
      echo ""
      echo "Task-grid fields (with --dashboard):"
      echo "  --title 'Task Name'    Card title (required)"
      echo "  --tag 'GDRIVE'         Type label shown on tag badge (required)"
      echo "  --icon '📥'            Emoji icon for the card (required)"
      echo "  --desc 'Description'   Brief task description (required)"
      echo "  --prefix '/gdDown'     URL prefix for the module route (required)"
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

# ── Dashboard task-grid delete flow ──────────────────────────────────────────

if [ -n "$DASHBOARD_DELETE" ]; then
  DASHBOARD_DIR="$SCRIPT_DIR"
  if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "Dashboard directory not found at $DASHBOARD_DIR — is the ecosystem layout intact?"
    exit 1
  fi
  INDEX_HTML="$DASHBOARD_DIR/templates/index.html"
  CSS_FILE="$DASHBOARD_DIR/static/style.css"
  JS_FILE="$DASHBOARD_DIR/static/script.js"

  for f in "$INDEX_HTML" "$CSS_FILE" "$JS_FILE"; do
    [ -f "$f" ] || { echo "File not found: $f"; exit 1; }
  done

  # Escape the name for use in Python string
  SAFE_NAME=$(printf '%s' "$DASHBOARD_DELETE" | sed 's/\\/\\\\/g; s/"/\\"/g')

  python3 - "$INDEX_HTML" "$CSS_FILE" "$JS_FILE" "$SAFE_NAME" <<'PYEOF'
import sys, re

html_path, css_path, js_path, name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# 1. Remove the task card from HTML (the div starting with the class + containing the name)
with open(html_path) as f:
    html = f.read()

# Match a task-card-item block whose description contains the module name
card_pattern = re.compile(
    r'\n        <div class="task-card-item">.*?'
    r'<p class="task-description">.*?' + re.escape(name) + r'.*?</p>.*?'
    r'</div>\n',
    re.DOTALL,
)
html = card_pattern.sub('', html, count=1)

# 2. Remove the modal div for this module (id="{name}Modal")
modal_pattern = re.compile(
    r'\n    <div id="' + re.escape(name) + r'Modal" class="modal">.*?</div>\n',
    re.DOTALL,
)
html = modal_pattern.sub('', html, count=1)

with open(html_path, 'w') as f:
    f.write(html)

# 3. Remove JS functions for this module
with open(js_path) as f:
    js = f.read()

# Remove the open{Name}Modal function
js = re.sub(r'\n\nfunction open' + re.escape(name) + r'Modal\(\).*?\n}', '', js, count=1)
# Remove the close{Name}Modal function
js = re.sub(r'\n\nfunction close' + re.escape(name) + r'Modal\(\).*?\n}', '', js, count=1)
# Remove viewLogs entry references for this module
js = re.sub(r"[']" + re.escape(name) + r"[']", '"__REMOVED__', js)

with open(js_path, 'w') as f:
    f.write(js)

# 4. Clean up CSS icon/tag classes (safe to leave orphan classes — they won't match anything)

print(f"Removed task-grid card and modal for '{name}'.")
PYEOF

  echo "Dashboard task-grid cleaned."
  exit 0
fi

# ── Sync mode: regenerate task-grid cards for all registered modules ──────────

if [ "$SYNC" = true ]; then
  DASHBOARD_DIR="$SCRIPT_DIR"
  if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "Dashboard directory not found at $DASHBOARD_DIR — is the ecosystem layout intact?"
    exit 1
  fi
  INDEX_HTML="$DASHBOARD_DIR/templates/index.html"
  CSS_FILE="$DASHBOARD_DIR/static/style.css"
  JS_FILE="$DASHBOARD_DIR/static/script.js"

  for f in "$INDEX_HTML" "$CSS_FILE" "$JS_FILE"; do
    [ -f "$f" ] || { echo "File not found: $f"; exit 1; }
  done

  # Load optional dashboard field overrides (if the user has a fields file)
  FIELDS_FILE="$SCRIPT_DIR/dashboard_fields.json"
  FIELDS_JSON=""
  if [ -f "$FIELDS_FILE" ]; then
    FIELDS_JSON=$(cat "$FIELDS_FILE")
    echo "Loaded dashboard field overrides from $FIELDS_FILE."
  fi

  python3 - "$BLUEPRINTS_FILE" "$INDEX_HTML" "$CSS_FILE" "$JS_FILE" "$FIELDS_JSON" <<'PYEOF'
import json, sys, re

def infer_title(mod_name):
    """Best-effort human-readable title from a module name."""
    clean = re.sub(r'[_-]bp$', '', mod_name)
    words = re.sub(r'([a-z])([A-Z])', r'\1 \2', clean).split()
    return ' '.join(w.capitalize() for w in words) if words else clean.capitalize()

def infer_tag(safe_name):
    """Infer a tag badge from the module name."""
    tag_map = {
        'pdf': 'PDF', 'drive': 'GDRIVE', 'gdrive': 'GDRIVE',
        'download': 'DL', 'sync': 'ETL', 'import': 'IMPORT',
        'export': 'EXPORT', 'encrypt': 'CRYPTO', 'decrypt': 'CRYPTO',
    }
    for key, tag in tag_map.items():
        if key in safe_name:
            return tag
    return safe_name.upper()[:6]

def infer_desc(mod_name, path):
    """Generate a generic description when none is provided."""
    title = infer_title(mod_name) or mod_name
    return f"Automated task for {title} ({path or 'route not configured'})."

blueprints_path, html_path, css_path, js_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
fields_json = sys.argv[5] if len(sys.argv) > 5 else ""

with open(blueprints_path) as f:
    data = json.load(f)

# Load optional field overrides by module name
overrides = {}
if fields_json:
    try:
        overrides = json.loads(fields_json)
    except json.JSONDecodeError:
        pass  # ignore invalid JSON, proceed without overrides

# Collect already-present module names from task-grid and modal sections
with open(html_path) as f:
    html = f.read()

def extract_module_names_from_cards(html):
    """Return set of safe-name tokens present in task-card-items."""
    names = set()
    for m in re.finditer(r'id="lastRun-([\w]+)"', html):
        names.add(m.group(1))
    return names

def extract_modal_names(html):
    """Return set of safe-name tokens present in modal IDs."""
    names = set()
    for m in re.finditer(r'id="([\w]+)Modal"', html):
        names.add(m.group(1))
    return names

existing_cards = extract_module_names_from_cards(html)
existing_modals = extract_modal_names(html)
existing_ui = existing_cards | existing_modals

added = 0
missing = 0

for entry in data["blueprints"]:
    mod_name = entry.get("name", "")
    # Derive safe name (strip _bp suffix if present)
    safe_name = re.sub(r'[_-]bp$', '', mod_name).lower()

    if safe_name not in existing_ui:
        # Check overrides first, then infer
        meta = overrides.get(safe_name, {})

        title = meta.get("title") or infer_title(mod_name)
        tag = meta.get("tag") or infer_tag(safe_name)
        icon_emoji = meta.get("icon") or "📋"
        desc = meta.get("desc") or infer_desc(mod_name, entry.get("path", ""))

        # If title wasn't provided and can't be inferred, skip with a note
        if not title:
            print(f"  ⏭  Skipped '{mod_name}': no display metadata available — "
                  f"add to dashboard_fields.json or register with --dashboard")
            missing += 1
            continue

        icon_class = f"{tag.lower().replace(' ', '-')}-icon".replace('_', '-')
        tag_class = f"{tag.lower().replace(' ', '-')}-tag".replace('_', '-')

        # 1. Inject task card into HTML (after first task-card-item)
        card_block = f'''
        <!-- Task Item: {title} -->
        <div class="task-card-item">
            <div class="task-header-row">
                <div class="task-info-main">
                    <div class="task-type-icon {icon_class}"></div>
                    <div class="task-titles">
                        <span class="task-tag {tag_class}">{title}</span>
                        <h3>{title}</h3>
                    </div>
                </div>
                <div class="task-status-badge status-idle">Idle</div>
            </div>
            <p class="task-description">{desc}</p>
            <div class="task-footer">
                <div class="task-meta-left">
                    <span class="clock-icon">&#x1F552;</span> Last run: <span id="lastRun-{safe_name}">Never</span>
                </div>
                <div class="task-actions-right">
                    <button class="icon-btn-secondary" onclick="viewLogs('{safe_name}')" title="View Logs">&#x1F4C4;</button>
                    <button class="action-btn btn-primary run-task-btn" onclick="open{safe_name.capitalize()}Modal()">&#x25B6; Run</button>
                </div>
            </div>
        </div>
'''

        insert_after = '<div class="task-card-item">'
        first_match = html.find(insert_after)
        if first_match == -1:
            print(f"  ⚠  No task-card-item found in HTML — cannot inject for '{title}'.")
            continue

        depth = 0
        i = first_match
        while i < len(html):
            if html[i:i+len('<div ')] == '<div ':
                depth += 1
            elif html[i:i+len('</div>')] == '</div>':
                depth -= 1
                if depth == 0:
                    insert_pos = i + len('</div>')
                    html = html[:insert_pos] + card_block + html[insert_pos:]
                    break
            i += 1

        # 2. Inject CSS icon class and tag colors
        with open(css_path) as f:
            css = f.read()

        if f'.{icon_class}' not in css:
            css += f'\n.{icon_class}::after {{ content: "{icon_emoji}"; }}\n'
        if f'.{tag_class}' not in css:
            css += f'\n.{tag_class} {{ color: var(--color-success); background-color: var(--color-success-bg); border: 1px solid var(--color-success); }}\n'

        with open(css_path, 'w') as f:
            f.write(css)

        # 3. Inject modal div and JS functions
        modal_div = f'''
    <div id="{safe_name}Modal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3>Run: {title}</h3>
                <button class="close-btn" onclick="close{safe_name.capitalize()}Modal()">&#x00D7;</button>
            </div>
            <form id="{safe_name}Form">
                <p><em>Add your form fields here, or re-run with --dashboard to configure interactively.</em></p>
                <button type="submit" class="action-btn btn-primary" style="width:100%; justify-content:center;">Execute Task</button>
            </form>
        </div>
    </div>
'''

        if f'id="{safe_name}Modal"' not in html:
            html = html.replace('</body>', modal_div + '\n</body>')

        open_fn = f'''

function open{safe_name.capitalize()}Modal() {{
    document.getElementById('{safe_name}Modal').style.display = 'flex';
}}

function close{safe_name.capitalize()}Modal() {{
    document.getElementById('{safe_name}Modal').style.display = 'none';
}}
'''

        with open(js_path) as f:
            js = f.read()
        if f'function open{safe_name.capitalize()}Modal()' not in js:
            js += open_fn

        with open(html_path, 'w') as f:
            f.write(html)
        with open(js_path, 'w') as f:
            f.write(js)

        print(f"  + Added task-card for '{title}' ({safe_name})")
        added += 1

print(f"\nSync complete: {added} card(s) added, {missing} skipped.")

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
DUP_EXIT=0
python3 - "$BLUEPRINTS_FILE" "$MOD_NAME" "$MOD_PATH" <<'PYEOF' || DUP_EXIT=$?
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

if [ $DUP_EXIT -ne 0 ] && [ "$DASHBOARD" = false ]; then
  echo "Cannot register — module already in blueprints.json. Use --dashboard to add it to task-grid anyway."
  exit 1
fi


# ── Create module directory if needed (skip in --dashboard mode) ──────────────

MODULE_DIR="$SCRIPT_DIR/$MOD_PATH"

if [ "$DASHBOARD" = true ]; then
  : # skip module scaffolding — the module exists at its own location
elif [ ! -d "$MODULE_DIR" ]; then
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

# ── Register in blueprints.json (skip silently if already registered when --dashboard) ──

ALREADY_REGISTERED=false
REG_OUTPUT=$(python3 - "$BLUEPRINTS_FILE" "$MOD_NAME" "$MOD_PATH" "$URL_PREFIX" <<PYEOF 2>&1
import json, sys

file_path, mod_name, mod_path, url_prefix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(file_path) as f:
    data = json.load(f)

# Double-check (defense in depth — the bash block did the first pass above)
for entry in data["blueprints"]:
    if entry["name"] == mod_name or entry.get("path") == mod_path:
        print("ALREADY_REGISTERED")
        sys.exit(0)

data["blueprints"].append({
    "path": mod_path,
    "name": mod_name,
    "url_prefix": url_prefix,
})

with open(file_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\\n")
PYEOF
)
if echo "$REG_OUTPUT" | grep -q "ALREADY_REGISTERED"; then
  ALREADY_REGISTERED=true
fi

# ── Sync txt registry from blueprints.json (single source of truth) ───────

if [ "$ALREADY_REGISTERED" = false ]; then
  python3 - "$BLUEPRINTS_FILE" "$MODULES_TXT" <<'PYEOF'
import json, sys

blueprints_path, txt_path = sys.argv[1], sys.argv[2]
data = json.load(open(blueprints_path))

with open(txt_path, "w") as f:
    f.write("# Registered modules\n")
    for e in data["blueprints"]:
        f.write(f"name={e['name']}\n")
        f.write(f"path={e['path']}\n")
        if e.get("url_prefix"):
            f.write(f"url_prefix={e['url_prefix']}\n")
        f.write("---\n")
PYEOF

  echo "Registered $MOD_NAME (prefix=$URL_PREFIX) → blueprints.json, modules.txt."
else
  echo "$MOD_NAME is already registered in blueprints.json — skipping duplicate registration."
fi

# ── Dashboard task-grid injection (optional, triggered with --dashboard) ──────

if [ "$DASHBOARD" = true ]; then
  # Validate required dashboard fields
  for var in DS_TITLE DS_TAG DS_ICON; do
    if [ -z "${!var}" ]; then
      echo "Missing required flag: --$var (lowercase)"
      exit 1
    fi
  done

  DASHBOARD_DIR="$SCRIPT_DIR"
  if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "Dashboard directory not found at $DASHBOARD_DIR — is the ecosystem layout intact?"
    exit 1
  fi
  INDEX_HTML="$DASHBOARD_DIR/templates/index.html"
  CSS_FILE="$DASHBOARD_DIR/static/style.css"
  JS_FILE="$DASHBOARD_DIR/static/script.js"

  for f in "$INDEX_HTML" "$CSS_FILE" "$JS_FILE"; do
    [ -f "$f" ] || { echo "File not found: $f"; exit 1; }
  done

  # Build the modal HTML from --dashboard-fields if provided (via python to avoid quoting hell)
  MODAL_HTML=""
  if [ -n "$DS_MODAL_FIELDS" ]; then
    SAFE_NAME=$(printf '%s' "$MOD_NAME" | sed 's/[^a-zA-Z0-9]//g')
    MODAL_HTML=$(python3 -c "
import sys, html as h

fields_raw = sys.argv[1].split(';')
result = []
for field in fields_raw:
    parts = field.split('|')
    if len(parts) < 3:
        continue
    label, ftype, fid = parts[0], parts[1], parts[2]
    extra = '|'.join(parts[3:])
    extra_parts = extra.split(',') if extra else []
    placeholder = None
    style = ''
    for ep in extra_parts:
        k, v = ep.strip().split(':', 1)
        if k == 'ph': placeholder = v
        elif k == 'full': style = 'style=\"width:100%\"'

    if ftype == 'password':
        ph = f'placeholder=\"{placeholder}\"' if placeholder else ''
        result.append(f'                <input type=\"password\" id=\"{fid}\" {ph}>')
    elif ftype == 'file':
        result.append(f'                <input type=\"file\" id=\"{fid}\" required>')
    elif ftype == 'checkbox':
        result.append(f'                <label class=\"checkbox-label\"><input type=\"checkbox\" id=\"{fid}\"> {h.escape(label)}</label>')
    else:
        ph = f'placeholder=\"{placeholder}\"' if placeholder else ''
        sty = style if style else ''
        vals = [v for v in [ph, sty] if v]
        attrs = ' '.join(vals)
        result.append(f'                <input type=\"{ftype}\" id=\"{fid}\" {attrs}>')

# Build final output: label + input per row (checkbox has label inline)
out_lines = []
for i, line in enumerate(fields_raw):
    parts = line.split('|')
    ltype = parts[1] if len(parts) > 1 else 'text'
    if ltype == 'checkbox':
        out_lines.append(line)  # will be handled inline
    else:
        out_lines.append(('LABEL', line))

final = []
for item in fields_raw.split(';'):
    parts = item.split('|')
    label = parts[0]
    ftype = parts[1] if len(parts) > 1 else 'text'
    if ftype == 'checkbox':
        final.append(result[[f.split('|')[1] for f in fields_raw.split(';')].index(ftype)])
    else:
        final.append(f'                <label>{h.escape(label)}:</label>')
        idx = [f.split('|')[0] for f in fields_raw.split(';')].index(parts[0])
        final.append(result[idx])

print('\\n'.join(final))
" "$DS_MODAL_FIELDS") || MODAL_HTML=""
  fi

  SAFE_NAME=$(printf '%s' "$MOD_NAME" | sed 's/[^a-zA-Z0-9]//g')
  ICON_CLASS="${DS_TAG,,}-icon"          # e.g. "gdrive-icon"
  TAG_CLASS="${DS_TAG,,}-tag"            # e.g. "gdrive-tag"

  python3 - "$INDEX_HTML" "$CSS_FILE" "$JS_FILE" "$ICON_CLASS" "$TAG_CLASS" \
    "$DS_TITLE" "$DS_ICON" "$DS_DESC" "$URL_PREFIX" "$SAFE_NAME" "$MODAL_HTML" <<'PYEOF'
import sys, re

(html_path, css_path, js_path,
 icon_class, tag_class,
 title, icon_emoji, desc, prefix,
 safe_name, modal_html) = sys.argv[1], sys.argv[2], sys.argv[3], \
    sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], \
    sys.argv[8], sys.argv[9], sys.argv[10]

# ── 1. Inject task card into HTML, right after the first task-card-item ──
with open(html_path) as f:
    html = f.read()

# Find the closing </div> of the last task-card-item and insert after it
card_block = f'''
        <!-- Task Item: {title} -->
        <div class="task-card-item">
            <div class="task-header-row">
                <div class="task-info-main">
                    <div class="task-type-icon {icon_class}"></div>
                    <div class="task-titles">
                        <span class="task-tag {tag_class}">{title}</span>
                        <h3>{title}</h3>
                    </div>
                </div>
                <div class="task-status-badge status-idle">Idle</div>
            </div>
            <p class="task-description">{desc}</p>
            <div class="task-footer">
                <div class="task-meta-left">
                    <span class="clock-icon">&#x1F552;</span> Last run: <span id="lastRun-{safe_name}">Never</span>
                </div>
                <div class="task-actions-right">
                    <button class="icon-btn-secondary" onclick="viewLogs('{safe_name}')" title="View Logs">&#x1F4C4;</button>
                    <button class="action-btn btn-primary run-task-btn" onclick="open{safe_name}Modal()">&#x25B6; Run</button>
                </div>
            </div>
        </div>
'''

# Insert after the first task-card-item's closing tag
insert_after = '<div class="task-card-item">'
first_match = html.find(insert_after)
if first_match == -1:
    print("No task-card-item found in HTML — cannot inject.")
    sys.exit(1)

# Find the matching </div> after this <div class="task-card-item">
depth = 0
start = first_match
body_start = None
i = start
while i < len(html):
    if html[i:i+len('<div ')] == '<div ':
        if depth == 0:
            body_start = i + len('<div class="task-card-item">')
            depth += 1
        else:
            depth += 1
    elif html[i:i+len('</div>')] == '</div>':
        depth -= 1
        if depth == 0 and body_start is not None:
            insert_pos = i + len('</div>')
            html = html[:insert_pos] + card_block + html[insert_pos:]
            break
    i += 1

with open(html_path, 'w') as f:
    f.write(html)

# ── 2. Inject CSS icon class and tag colors ───────────────────────────────
with open(css_path) as f:
    css = f.read()

if f'.{icon_class}' not in css:
    icon_rule = f'\n.{icon_class}::after {{ content: "{icon_emoji}"; }}\n'
    # Append after the existing icon rules
    css = css.rstrip() + '\n' if not css.endswith('\n') else css + '\n'
    css += icon_rule

if f'.{tag_class}' not in css:
    tag_rule = f'\n.{tag_class} {{ color: var(--color-success); background-color: var(--color-success-bg); border: 1px solid var(--color-success); }}\n'
    css += tag_rule

with open(css_path, 'w') as f:
    f.write(css)

# ── 3. Inject JS functions and modal HTML ────────────────────────────────
with open(js_path) as f:
    js = f.read()

modal_div = f'''
    <div id="{safe_name}Modal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3>Run: {title}</h3>
                <button class="close-btn" onclick="close{safe_name}Modal()">&#x00D7;</button>
            </div>
            <form id="{safe_name}Form">
{modal_html}
                <button type="submit" class="action-btn btn-primary" style="width:100%; justify-content:center;">Execute Task</button>
            </form>
        </div>
    </div>
'''

open_fn = f'''
function open{safe_name}Modal() {{
    document.getElementById('{safe_name}Modal').style.display = 'flex';
}}

function close{safe_name}Modal() {{
    document.getElementById('{safe_name}Modal').style.display = 'none';
}}
'''

# Check if modal already exists (idempotent check)
if f'id="{safe_name}Modal"' not in js + html:
    # Insert modal before the closing </body> tag
    html = html.replace('</body>', modal_div + '\n</body>')
    with open(html_path, 'w') as f:
        f.write(html)

# Only add JS functions if they don't already exist
if f'function open{safe_name}Modal()' not in js:
    js += open_fn
    with open(js_path, 'w') as f:
        f.write(js)

print(f"Added task-grid card for '{title}' ({prefix}).")
PYEOF

  echo "Also injected into dashboard index.html / style.css / script.js."
fi
