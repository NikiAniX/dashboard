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
| `register_module.sh` / `run_dashboard.sh` / `swagger_dashboard.py` | Register modules, start the app, generate job + form from swagger |
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

Modules live in sibling projects (`<project_path>/modules/<name>` exporting `<name>_bp`, plus `swagger.json`). Run `./register_module.sh` (needs `jq`) to update `blueprints.json` and generate the dashboard job/form via `swagger_dashboard.py`, then `./run_dashboard.sh`. See `PROGRESS.md` for history.

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
- Jobs and run forms are generated into `static/script.js` (`jobsData`) and `templates/index.html` by `swagger_dashboard.py`. There is still no backend API for stats or task status.
- Frontend state (logs) is kept in a single JS variable (`cachedLogs`) rather than persisted anywhere.
