# Dashboard

A modular Flask-based task automation dashboard with PDF decryption capabilities. The app provides a dark-themed web UI for monitoring and executing background tasks, with a pluggable blueprint system designed to grow with new features.

---

## Architecture

```
dashboard/
├── app.py                # Flask app factory & dynamic blueprint loader
├── blueprints.json       # Declarative registry of registered feature modules
├── requirements.txt      # Python dependencies
├── register_module.sh    # Register a module + generate its dashboard job/form
├── run_dashboard.sh      # Install module requirements and start the app
├── swagger_dashboard.py  # swagger.json -> jobsData entry + run-form modal
├── PROGRESS.md           # Work log
├── templates/
│   └── index.html        # Dashboard UI (stat cards, task grid, modals)
└── static/
    ├── script.js         # Frontend: modal logic, fetch calls, log display
    └── style.css          # Dark-themed dashboard stylesheet
```

### Design Principles

- **Blueprint-first**: Every new feature lives in its own directory with an `__init__.py` that exports a Flask Blueprint. Registering it requires only two lines in `blueprints.json`.
- **App factory pattern**: `create_app()` in `app.py` builds the Flask instance, registers all blueprints, and mounts the dashboard root route.
- **Dynamic discovery**: Blueprints are loaded at import time from `blueprints.json` using `importlib.util.spec_from_file_location`, so no code changes are needed to add modules.
- **Single-route frontend**: The `/` route serves `index.html`; all task actions go through XHR/fetch calls to registered blueprint endpoints.

### Runtime Flow

```
Browser                    Flask App                    Blueprint Module
   │                          │                              │
   ├── GET / ───────────────>│  render_template("index")───>│
   │                          │                              │
   │     POST /pdfDecryptor       │                              │
   │  <──────────────────────────│  pdfDecryptor_bp.route("/pdfDecryptor")│
   │                          │      → pypdf decryption       │
   │  ← JSON {status, logs} ─│                              │
```

### Key Components

| File | Role |
|---|---|
| `app.py` | App factory, blueprint loader, root route |
| `blueprints.json` | Maps each feature to a filesystem path, exported symbol, and URL prefix |
| `templates/index.html` | Dashboard layout: stat cards, toolbar, task grid, modal dialogs |
| `static/script.js` | Modal open/close, form submission via `fetch`, log rendering |
| `static/style.css` | CSS custom properties, responsive grid layout, dark theme tokens |

---

## Setup

### Prerequisites

- Python 3.12+
- Virtual environment (recommended)

### Installation

```bash
# Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

Dependencies:

| Package | Purpose |
|---|---|
| `flask>=3.0` | Web framework & templating |
| `pypdf>=5.0` | Password-based PDF decryption |
| `cryptography>=3.1` | AES cipher support for encrypted PDFs |

### Running the App

```bash
python app.py
```

The server starts on **`http://0.0.0.0:5005`**.

Open a browser and navigate to `http://localhost:5005` to see the dashboard.

---

## Adding a New Feature Module

Modules live in their own project (e.g. `../pdfDecryptor`) with `modules/<name>/__init__.py` exporting `<name>_bp`, plus a `swagger.json` at the project root.

```bash
./register_module.sh   # prompts for module name, project path, URL prefix
./run_dashboard.sh     # installs module requirements, starts on port 5005
```

`register_module.sh` appends the entry to `blueprints.json` and runs `swagger_dashboard.py`, which generates a job in `static/script.js` and a run-form modal in `templates/index.html` for each swagger operation. Duplicate URL prefixes are rejected. Requires `jq`.

---

## Current Features

### Registered modules: `pdfDecryptor`, `gdDownloader`, `ccDataExtractor`

### PDF Decryption (`/pdfDecryptor`)

- Upload a password-protected PDF via the dashboard UI modal.
- Specify input (encrypted) and output (decrypted) folder paths.
- Executes decryption using `pypdf` and returns structured logs.
- Available as a task card in the dashboard grid with "Run" and "View Logs" actions.

### Credit-Card Statement Extraction (`/ccDataExtractor`)

- Upload a statement (`.png`, `.jpg`, `.jpeg`, `.pdf`) and an output directory via the dashboard run form (generated from the module's `swagger.json`).
- Runs offline OCR (RapidOCR + PyMuPDF) and saves summary, transactions and a reconciliation block as JSON.
- Needs the module's heavy requirements (`rapidocr-onnxruntime`, `pymupdf`, ...); `run_dashboard.sh` installs them.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3.14, Flask 3.x |
| Frontend | Vanilla JavaScript, CSS custom properties |
| PDF Library | pypdf 5.x |
| Packaging | Virtual environment (no containerization) |

---

## Future Considerations

- **Async execution**: Decryption runs synchronously; consider Celery or asyncio for long-running tasks.
- **Dynamic stats**: Stat cards show hardcoded values; wire them to blueprint status endpoints.
- **Template data**: Pass task registry from `blueprints.json` into the template to render cards dynamically.
- **File storage**: Paths are passed as strings; add upload handling or local file management for portability.
