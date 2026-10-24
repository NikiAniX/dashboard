"""Finance dashboard — reads credit-card statement JSON files and serves them as normalized data.

Routes:
    /finance      HTML dashboard page
    /api/finance  JSON with normalized transactions and per-card statement summaries
"""

from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path

from flask import Blueprint, jsonify, render_template

DEFAULT_DATA_DIR = "/Users/ani/projectX/ecosystem/target/ccDataExtractor/output"
DATA_DIR = Path(os.environ.get("FINANCE_DATA_DIR", DEFAULT_DATA_DIR)).resolve()
DATE_FORMAT = "%d/%m/%Y"
UNCATEGORIZED = "Other"
DEBIT = "Dr"
CARD_SUFFIX_LENGTH = 4

BANK_KEYWORDS = {
    "hdfc": "HDFC",
    "indusind": "IndusInd",
    "flipkart": "Flipkart Axis",
    "amazon": "Amazon Pay",
    "slice": "Slice",
}

# Used only when a statement has no merchant_category of its own.
CATEGORY_KEYWORDS = {
    "Food & Dining": ("zomato", "swiggy", "chai", "bhel", "food", "chats", "restaurant", "cafe", "chalukya"),
    "Groceries": ("grocery", "zepto", "bigbasket", "blinkit", "supermarket"),
    "Utilities": ("utility", "utilities", "airtel", "electric", "recharge"),
    "Shopping": ("amazon", "flipkart", "daiso", "retail", "mart"),
    "Entertainment": ("youtube", "netflix", "spotify", "movie"),
}

finance_bp = Blueprint("finance", __name__)


def parse_amount(value: object) -> float:
    """Convert strings like ``'1,224.00 DR'`` to a float; return 0.0 when unparseable."""
    match = re.search(r"\d[\d,]*\.?\d*", str(value or ""))
    return float(match.group().replace(",", "")) if match else 0.0


def detect_bank(*texts: str) -> str:
    """Return a friendly bank name by scanning *texts* for known keywords."""
    haystack = " ".join(texts).lower()
    return next((name for key, name in BANK_KEYWORDS.items() if key in haystack), "Card")


def card_suffix(summary: dict, source_file: str) -> str:
    """Trailing visible digits of the (masked) card number, falling back to the file name."""
    number = summary.get("credit_card_number") or ""
    if not number:
        match = re.match(r"^[\dX*]{8,}", source_file)
        number = match.group() if match else ""
    trailing = re.search(r"\d+$", number.strip())
    return trailing.group()[-CARD_SUFFIX_LENGTH:] if trailing else "----"


def infer_category(details: str) -> str:
    """Guess a spending category from merchant text."""
    text = details.lower()
    return next((cat for cat, words in CATEGORY_KEYWORDS.items() if any(w in text for w in words)), UNCATEGORIZED)


def normalize_category(raw: str | None, details: str) -> str:
    """Prefer the statement's merchant_category; otherwise infer from the description."""
    return raw.strip().title() if raw else infer_category(details)


def load_statement(path: Path) -> tuple[dict, list[dict]] | None:
    """Parse one statement file into (card summary, transactions); None if unreadable."""
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    summary = data.get("summary") or {}
    title = (data.get("extras") or {}).get("statement_title") or ""
    source = data.get("source_file") or path.name
    bank = detect_bank(title, source)
    suffix = card_suffix(summary, source)
    card = f"{bank} ••{suffix}"

    statement_points = (data.get("extras") or {}).get("points_summary", {}).get("total")
    transactions = []
    for raw in data.get("transactions", []):
        try:
            when = datetime.strptime(raw["date"], DATE_FORMAT)
        except (KeyError, ValueError):
            continue
        details = raw.get("details") or ""
        transactions.append({
            "date": when.strftime("%Y-%m-%d"),
            "details": details,
            "card": card,
            "category": normalize_category(raw.get("merchant_category"), details),
            "amount": parse_amount(raw.get("amount")),
            "type": raw.get("amount_type") or DEBIT,
            "reward_points": parse_amount(raw.get("reward_points")),
            "cashback": parse_amount(raw.get("cashback")),
            "source": path.name,
        })

    statement_iso = None
    try:
        statement_iso = datetime.strptime(summary.get("statement_generation_date"), DATE_FORMAT).strftime("%Y-%m-%d")
    except (TypeError, ValueError):
        pass

    card_summary = {
        "card": card,
        "bank": bank,
        "source": path.name,
        "statement_date": summary.get("statement_generation_date"),
        "statement_iso": statement_iso,
        "due_date": summary.get("payment_due_date"),
        "total_due": parse_amount(summary.get("total_payment_due")),
        "minimum_due": parse_amount(summary.get("minimum_payment_due")),
        "credit_limit": parse_amount(summary.get("credit_limit")),
        "available_credit": parse_amount(summary.get("available_credit_limit")),
        "statement_points": parse_amount(statement_points),
    }
    return card_summary, transactions


def load_all() -> dict:
    """Load every statement in DATA_DIR."""
    cards, transactions = [], []
    for path in sorted(DATA_DIR.glob("*.json")):
        loaded = load_statement(path)
        if loaded:
            cards.append(loaded[0])
            transactions.extend(loaded[1])
    transactions.sort(key=lambda t: t["date"])
    return {"cards": cards, "transactions": transactions, "data_dir": str(DATA_DIR)}


@finance_bp.route("/finance")
def finance_page():
    return render_template("finance.html")


@finance_bp.route("/api/finance")
def finance_data():
    return jsonify(load_all())
