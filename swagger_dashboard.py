#!/usr/bin/env python3
"""Add a module's swagger.json operations to the dashboard as jobs.

For every operation (path + method) in the swagger file this inserts:
  * a job entry at the top of ``jobsData`` in ``static/script.js``, and
  * a run-form modal (one input per request property) in ``templates/index.html``.

Re-running is safe: jobs already in ``jobsData`` are not duplicated and their forms are refreshed.

Usage::

    python3 swagger_dashboard.py <swagger.json> <module_name> <script.js> <index.html>
"""

from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path
from typing import Any

HTTP_METHODS = ("get", "post", "put", "patch", "delete")
QUERY_STRING_METHODS = ("get", "delete")
CONTENT_TYPE_PREFERENCE = (
    "multipart/form-data",
    "application/x-www-form-urlencoded",
    "application/json",
)
JOBS_ANCHOR = "let jobsData = ["
HTML_ANCHOR = "</body>"
MODAL_ID_PREFIX = "runModal-"
INPUT_CLASS = (
    "w-full px-4 py-2.5 bg-slate-100 dark:bg-slate-800 border-0 rounded-xl text-sm "
    "focus:outline-none focus:ring-2 focus:ring-brand-500"
)
LABEL_CLASS = "block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400 mb-1"


# ── swagger parsing ---------------------------------------------------------
def resolve_ref(spec: dict[str, Any], node: dict[str, Any]) -> dict[str, Any]:
    """Follow local ``$ref`` pointers (e.g. ``#/components/schemas/X``) to a concrete node."""
    while "$ref" in node:
        target: Any = spec
        for part in node["$ref"].removeprefix("#/").split("/"):
            target = target[part]
        node = target
    return node


def field_from_schema(name: str, schema: dict[str, Any], required: bool) -> dict[str, Any]:
    """Map one schema property to a form field description."""
    multiple = schema.get("type") == "array"
    if multiple:
        schema = {**schema.get("items", {}), **{k: v for k, v in schema.items() if k != "items"}}
    if schema.get("format") == "binary":
        field_type = "file"
    elif schema.get("format") == "password":
        field_type = "password"
    elif "enum" in schema:
        field_type = "select"
    elif schema.get("type") in ("integer", "number"):
        field_type = "number"
    elif schema.get("type") == "boolean":
        field_type = "checkbox"
    else:
        field_type = "text"

    field: dict[str, Any] = {"name": name, "type": field_type, "required": required}
    if multiple and field_type == "file":
        field["multiple"] = True
    for key in ("description", "default", "example", "enum"):
        if key in schema:
            field[key] = schema[key]
    return field


def extract_request(spec: dict[str, Any], method: str, operation: dict[str, Any]) -> tuple[str | None, list[dict[str, Any]]]:
    """Return ``(content_type, fields)`` describing how to call the operation."""
    if method in QUERY_STRING_METHODS:
        params = (resolve_ref(spec, p) for p in operation.get("parameters", []))
        return None, [
            field_from_schema(p["name"], resolve_ref(spec, p.get("schema", {})), p.get("required", False))
            for p in params
            if p.get("in") == "query"
        ]

    content = resolve_ref(spec, operation.get("requestBody", {})).get("content", {})
    if not content:
        return None, []
    content_type = next((ct for ct in CONTENT_TYPE_PREFERENCE if ct in content), next(iter(content)))
    schema = resolve_ref(spec, content[content_type].get("schema", {}))
    required = set(schema.get("required", []))
    fields = [
        field_from_schema(name, resolve_ref(spec, prop), name in required)
        for name, prop in schema.get("properties", {}).items()
    ]
    return content_type, fields


def extract_jobs(spec: dict[str, Any], module_name: str) -> list[dict[str, Any]]:
    """Return one job definition per operation in the swagger spec."""
    description = spec.get("info", {}).get("description", "")
    jobs: list[dict[str, Any]] = []
    for endpoint, path_item in spec.get("paths", {}).items():
        for method in HTTP_METHODS:
            operation = path_item.get(method)
            if operation is None:
                continue
            content_type, fields = extract_request(spec, method, operation)
            job_id = f"{module_name}-{method}-{re.sub(r'\W+', '-', endpoint).strip('-')}"
            jobs.append({
                "id": job_id,
                "name": operation.get("summary") or operation.get("operationId") or f"{method.upper()} {endpoint}",
                "description": description or operation.get("description", ""),
                "method": method.upper(),
                "endpoint": endpoint,
                "contentType": content_type,
                "formModalId": MODAL_ID_PREFIX + job_id,
                "fields": fields,
            })
    return jobs


# ── rendering ---------------------------------------------------------------
def esc(value: Any) -> str:
    """HTML-escape a value; braces are encoded too so Jinja never sees ``{{`` / ``{%``."""
    return html.escape(str(value)).replace("{", "&#123;").replace("}", "&#125;")


def render_field(field: dict[str, Any]) -> str:
    """Render one swagger property as a labelled form control."""
    name, field_type = esc(field["name"]), field["type"]
    label_text = esc(field["name"]) + (" *" if field["required"] else "")
    title = f' title="{esc(field["description"])}"' if "description" in field else ""
    required = " required" if field["required"] and field_type != "checkbox" else ""
    default = field.get("default", "")

    if field_type == "select":
        options = "".join(
            f'<option value="{esc(v)}"{" selected" if str(v) == str(default) else ""}>{esc(v)}</option>'
            for v in field["enum"]
        )
        control = f'<select name="{name}"{required} class="{INPUT_CLASS}">{options}</select>'
    elif field_type == "checkbox":
        checked = " checked" if str(default).lower() == "true" else ""
        control = f'<input type="checkbox" name="{name}"{checked} class="w-4 h-4 accent-brand-600">'
    elif field_type == "file":
        multiple = " multiple" if field.get("multiple") else ""
        control = f'<input type="file" name="{name}"{multiple}{required} class="{INPUT_CLASS}">'
    else:
        placeholder = esc(field.get("example", field.get("description", "")))
        control = (
            f'<input type="{field_type}" name="{name}" value="{esc(default)}" '
            f'placeholder="{placeholder}"{required} class="{INPUT_CLASS}">'
        )
    return f'                <div>\n                    <label class="{LABEL_CLASS}"{title}>{label_text}</label>\n                    {control}\n                </div>'


def render_modal(job: dict[str, Any]) -> str:
    """Render the run-form modal shown before executing a job."""
    modal_id, job_id = esc(job["formModalId"]), esc(job["id"])
    fields = "\n".join(render_field(f) for f in job["fields"])
    return f'''
    <!-- RUN FORM: {esc(job["id"])} ({esc(job["method"])} {esc(job["endpoint"])}) -->
    <div id="{modal_id}" class="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-sm hidden items-center justify-center p-4">
        <div class="bg-white dark:bg-slate-900 w-full max-w-lg rounded-2xl border border-slate-200 dark:border-slate-800 shadow-2xl overflow-hidden">
            <div class="p-6 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between">
                <h3 class="text-lg font-bold">{esc(job["name"])}</h3>
                <button type="button" onclick="closeSwaggerJobModal('{modal_id}')" class="w-8 h-8 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-500 hover:text-slate-700 flex items-center justify-center">
                    <i class="fa-solid fa-xmark"></i>
                </button>
            </div>
            <form onsubmit="handleSwaggerJobSubmit(event, '{job_id}')" class="p-6 space-y-4">
{fields}
                <div class="pt-4 flex items-center justify-end space-x-3">
                    <button type="button" onclick="closeSwaggerJobModal('{modal_id}')" class="px-4 py-2.5 bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 font-medium rounded-xl text-sm hover:bg-slate-200 transition-colors">Cancel</button>
                    <button type="reset" class="px-4 py-2.5 bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 font-medium rounded-xl text-sm hover:bg-slate-200 transition-colors">Reset</button>
                    <button type="submit" class="px-5 py-2.5 bg-brand-600 text-white font-medium rounded-xl text-sm hover:bg-brand-700 shadow-lg shadow-brand-500/20 transition-all"><i class="fa-solid fa-paper-plane mr-1.5 text-xs"></i> Send</button>
                </div>
            </form>
        </div>
    </div>
'''


def render_job_entry(job: dict[str, Any]) -> str:
    """Render the ``jobsData`` array element for a job."""
    lines = [
        f"        id: {json.dumps(job['id'])},",
        f"        name: {json.dumps(job['name'])},",
        f"        description: {json.dumps(job['description'])},",
        "        status: 'completed',",
        "        progress: 0,",
        "        lastRun: 'Never',",
        f"        method: {json.dumps(job['method'])},",
        f"        endpoint: {json.dumps(job['endpoint'])},",
        f"        contentType: {json.dumps(job['contentType'])},",
        f"        formModalId: {json.dumps(job['formModalId'])},",
        f"        logs: [{json.dumps('Registered ' + job['method'] + ' ' + job['endpoint'] + ' from swagger.json.')}]",
    ]
    return "    {\n" + "\n".join(lines) + "\n    },\n"


# ── file updates ------------------------------------------------------------
def add_jobs(swagger_path: Path, module_name: str, script_path: Path, index_path: Path) -> list[str]:
    """Insert new jobs into script.js and index.html; return the ids that were added."""
    jobs = extract_jobs(json.loads(swagger_path.read_text()), module_name)
    script, index = script_path.read_text(), index_path.read_text()
    if JOBS_ANCHOR not in script or HTML_ANCHOR not in index:
        sys.exit(f"Could not find '{JOBS_ANCHOR}' in {script_path.name} or '{HTML_ANCHOR}' in {index_path.name}.")

    added: list[str] = []
    for job in reversed(jobs):
        existing_form = re.compile(rf"\n    <!-- RUN FORM: {re.escape(esc(job['id']))} .*?\n    </div>\n", re.DOTALL)
        if existing_form.search(index):
            index = existing_form.sub(lambda _: render_modal(job), index, count=1)  # refresh form markup
        else:
            index = index.replace(HTML_ANCHOR, render_modal(job) + HTML_ANCHOR, 1)
        if f"id: {json.dumps(job['id'])}" in script:
            continue
        script = script.replace(JOBS_ANCHOR, JOBS_ANCHOR + "\n" + render_job_entry(job).rstrip("\n"), 1)
        added.append(job["id"])

    script_path.write_text(script)
    index_path.write_text(index)
    return added[::-1]


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(f"Usage: {sys.argv[0]} <swagger.json> <module_name> <script.js> <index.html>")
    swagger, module_name, script, index = sys.argv[1], sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4])
    added = add_jobs(Path(swagger).resolve(), module_name, script.resolve(), index.resolve())
    print(f"Added {len(added)} job(s) to the dashboard: {', '.join(added) or 'none (already present)'}")


if __name__ == "__main__":
    main()
