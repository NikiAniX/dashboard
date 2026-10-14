# Progress Log

Summary of work done so far, derived from the git history (most recent last).

## Completed

| Commit | Change |
|---|---|
| `4ef6506` | Added `swagger_dashboard.py`: reads a module's `swagger.json` and generates a dashboard job entry (in `static/script.js` `jobsData`) plus a run-form modal (in `templates/index.html`) for every operation. Safe to re-run: existing jobs are not duplicated, their forms are refreshed. |
| `f02dcd3` | Registered two modules in `blueprints.json`: `pdfDecryptor` and `gdDownloader`. |
| `dec514e` | Rewrote `register_module.sh` (814 → ~80 lines). It prompts for module name, project path and URL prefix, derives the blueprint path and `<name>_bp` symbol, calls `swagger_dashboard.py`, appends to `blueprints.json`, and refuses duplicate URL prefixes. |
| `5afa9b2` | Rewrote `run_dashboard.sh`. It installs each registered module's `requirement(s).txt`, then starts the dashboard, and refuses to start when no modules are registered. Honors `PYTHON`, `APP_HOST`, `APP_PORT`. |
| `dff4f4c` | Expanded `static/script.js` with the job-driven frontend logic. |
| `25ee02b` | Condensed `static/style.css`. |
| `10dc83f` | Reworked `templates/index.html` (dashboard layout and generated run-form modals). |
| `a6f7325` | Removed the unused `modules.txt`. |

## Current Workflow

1. `./register_module.sh` — register a module (needs `jq`; module project must have `swagger.json` and `modules/<name>` exporting `<name>_bp`).
2. `./run_dashboard.sh` — install module requirements and start on port 5005.

## Notes / Known Gaps

- Modules live in sibling projects (e.g. `../pdfDecryptor`, `../gdDownloader`), not in a local `modules/` directory.
- `blueprints.json` stores absolute paths; they break if the projects move.
- `credentials.json` and `token.pickle` (Google Drive auth) are git-ignored; keep them out of version control.
- Stats and task status are still static, with no backend API.
- Tasks run synchronously; consider a job queue for long-running work.
