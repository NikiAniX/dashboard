#!/usr/bin/env python3
"""pdfDecryptor — app entry point.

Blueprints are loaded from blueprints.json at the project root, so adding a
new feature only requires writing a module directory and appending one JSON line.
"""

from __future__ import annotations

import json
import os
import sys
from importlib import util
from pathlib import Path
from flask import Flask

from finance import finance_bp
from job_state import register_job_tracking

# ── Paths -----------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
FLASK_TEMPLATE_DIR = BASE_DIR / "templates"
FLASK_STATIC_DIR = BASE_DIR / "static"


# ── Blueprint loading -----------------------------------------------------
def load_blueprint(path: str, name: str):
    """Import a feature module by filesystem path and return its blueprint.

    Each feature directory (e.g. ``modules/pdfDecryptor``) must contain an
    ``__init__.py`` that re-exports the blueprint under *name*.
    """
    pkg_dir = (BASE_DIR / path).resolve()

    # The dotted name lets Python infer __package__ so relative imports
    # like ``from .routes import bp`` resolve correctly.
    module_name = f"modules.{pkg_dir.name}"

    # Register a dummy parent package so relative imports (e.g. "from .routes import bp") resolve
    sys.modules["modules"] = util.module_from_spec(util.spec_from_loader("modules", []))

    spec = util.spec_from_file_location(
        module_name,
        str(pkg_dir / "__init__.py"),
        submodule_search_locations=[str(pkg_dir)],
    )
    module = util.module_from_spec(spec)
    sys.modules[module_name] = module          # full dotted name for relative imports (e.g. "from .routes import bp")
    sys.modules[pkg_dir.name] = module         # bare name so the top-level directory also resolves
    spec.loader.exec_module(module)
    return getattr(module, name)


def register_blueprints(app: Flask, config_file: str = "blueprints.json") -> set[str]:
    """Register every blueprint in blueprints.json; return their URL prefixes."""
    with open(BASE_DIR / config_file) as f:
        entries = json.load(f)["blueprints"]
    for e in entries:
        bp = load_blueprint(e["path"], e["name"])
        app.register_blueprint(bp, url_prefix=e.get("url_prefix"))
    return {e["url_prefix"] for e in entries if e.get("url_prefix")}


# ── App factory -----------------------------------------------------------
def create_app() -> Flask:
    """Build the Flask application and register all blueprints."""
    app = Flask(
        __name__,
        template_folder=str(FLASK_TEMPLATE_DIR),
        static_folder=str(FLASK_STATIC_DIR),
    )
    job_endpoints = register_blueprints(app)
    register_job_tracking(app, job_endpoints)
    app.register_blueprint(finance_bp)

    @app.route("/")
    def index():
        from flask import render_template
        return render_template("index.html")

    return app


# ── Runtime config ----------------------------------------------------------
APP_HOST = os.environ.get("APP_HOST", "0.0.0.0")
APP_PORT = int(os.environ.get("APP_PORT", "5005"))


app = create_app()

if __name__ == "__main__":
    app.run(host=APP_HOST, port=APP_PORT)
