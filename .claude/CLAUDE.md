# CLAUDE.md

Instructions for Claude Code when working on this project.

## Project Overview

This is a modular Flask dashboard for task automation with PDF decryption capabilities. New features are added as pluggable blueprint modules registered in `blueprints.json`.

## Key Files

| File | Purpose |
|---|---|
| `app.py` | App factory (`create_app()`), dynamic blueprint loader, root route serving the dashboard UI |
| `blueprints.json` | Registry of all active feature modules (path → Blueprint symbol → URL prefix) |
| `requirements.txt` | Runtime dependencies: Flask 3+, pypdf 5+, cryptography 3.1+ |
| `templates/index.html` | Dashboard layout with stat cards, task grid, and modal dialogs |
| `static/script.js` | Frontend logic: modal toggling, form submission via fetch, log rendering |
| `static/style.css` | Dark-themed dashboard stylesheet using CSS custom properties |

## Commands

```bash
# Run the app
python app.py

# Install dependencies
pip install -r requirements.txt

# Start virtual environment
source .venv/bin/activate
```

The app serves on `http://0.0.0.0:5005`.

## Adding a Blueprint Module

Every new feature follows the same pattern — no changes to `app.py` are required:

1. Create `modules/<name>/__init__.py` that exports a Flask Blueprint variable.
2. Add an entry to `blueprints.json` with path, export name, and URL prefix.
3. Restart the server.

## Coding Conventions

- **Type hints**: All files use `from __future__ import annotations`. Use them consistently.
- **Docstrings**: Public functions get module-level docstrings explaining purpose and parameters.
- **Naming**: Variable names match the existing style — `snake_case` for functions/vars, `PascalCase` for classes.
- **Path handling**: Use `pathlib.Path`, never string concatenation. Resolve paths with `.resolve()`.
- **No magic numbers**: Use CSS custom properties in `style.css`; use named constants in Python.
- **Blueprint routes**: Each blueprint owns its own subdirectory (`modules/<name>/routes.py` etc.).

## Architecture Notes

- Blueprints are loaded at app creation time via `importlib.util.spec_from_file_location`. They cannot be hot-reloaded without a restart.
- The `blueprints.json` paths are absolute; when the project moves, these must be updated or switched to relative paths.
- The dashboard frontend is static — no backend API for stats, filters, or task status. These are hardcoded in `index.html`.
- Frontend state (logs) is kept in a single JS variable (`cachedLogs`) rather than persisted anywhere.
