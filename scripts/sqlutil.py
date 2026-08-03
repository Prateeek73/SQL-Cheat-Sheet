"""
Shared helpers for the SQL practice build.

The most important piece here is `split_sql`, which replaces the broken
`sql_content.split('\\n--Q')` in the original master_orchestrator.py. That split
never matched anything (the query files use "-- Q1:" with a space), so the whole
file was handed to cursor.execute() as a single statement and always failed.
"""

from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = PROJECT_ROOT / "data" / "raw"
DATA_INCOMING = PROJECT_ROOT / "data" / "_incoming"
DB_DIR = PROJECT_ROOT / "db"
QUERY_DIR = PROJECT_ROOT / "queries"
DOCS_DIR = PROJECT_ROOT / "docs"

# project key -> (kaggle dataset id, human label)
PROJECTS: dict[str, tuple[str, str]] = {
    "project_1_ecommerce": (
        "thedevastator/unlock-profits-with-e-commerce-sales-data",
        "E-Commerce Sales Analysis",
    ),
    "project_2_churn": (
        "blastchar/telco-customer-churn",
        "Customer Churn (Telecom)",
    ),
    "project_3_hr": (
        "nadeemajeedch/employee-performance-and-salary-dataset",
        "Employee Performance",
    ),
    "project_4_food": (
        "varshinipallerla/food-delivery",
        "Food Delivery",
    ),
    "project_5_fraud": (
        "mlg-ulb/creditcardfraud",
        "Credit Card Fraud Detection",
    ),
}

# Header lines look like:  -- Q12: Some description here
Q_HEADER = re.compile(r"^\s*--\s*Q(\d+)\s*:\s*(.*)$", re.MULTILINE)


@dataclass
class Statement:
    """One executable SQL statement plus the -- Qn: label that introduced it."""

    number: int | None
    title: str
    sql: str
    line: int

    @property
    def label(self) -> str:
        return f"Q{self.number}" if self.number is not None else f"line {self.line}"


def split_sql(text: str) -> list[Statement]:
    """Split a .sql file into executable statements.

    Walks the text character by character so that semicolons inside string
    literals, quoted identifiers, line comments and /* block comments */ do not
    cause a split. Each statement is then matched back to the nearest preceding
    "-- Qn:" header so failures can be reported per question.
    """
    spans: list[tuple[int, int]] = []
    start = 0
    i = 0
    n = len(text)
    in_line_comment = False
    in_block_comment = False
    quote: str | None = None

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif quote is not None:
            if ch == quote:
                # '' and "" are escaped quotes, not terminators
                if nxt == quote:
                    i += 1
                else:
                    quote = None
        elif ch == "-" and nxt == "-":
            in_line_comment = True
            i += 1
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            i += 1
        elif ch in ("'", '"', "`"):
            quote = ch
        elif ch == ";":
            spans.append((start, i))
            start = i + 1
        i += 1

    if text[start:].strip():
        spans.append((start, n))

    statements: list[Statement] = []
    prev_end = 0
    for s, e in spans:
        body = text[s:e]
        if not _strip_comments(body).strip():
            prev_end = e
            continue
        # find the last "-- Qn:" header appearing before this statement
        number, title = None, ""
        for m in Q_HEADER.finditer(text, prev_end, s + len(body)):
            number, title = int(m.group(1)), m.group(2).strip()
        statements.append(
            Statement(
                number=number,
                title=title,
                sql=body.strip(),
                line=text.count("\n", 0, s) + 1,
            )
        )
        prev_end = e
    return statements


def _strip_comments(sql: str) -> str:
    """Remove comments so we can tell whether a chunk has real SQL in it."""
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql


def connect(db_path: Path) -> sqlite3.Connection:
    """Open a SQLite connection with sane defaults for analytics work."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def clean_identifier(name: str) -> str:
    """Turn an arbitrary CSV header / filename into a safe snake_case identifier."""
    name = name.strip().replace("%", "_pct").replace("&", "_and_")
    name = re.sub(r"[^0-9a-zA-Z]+", "_", name)
    name = re.sub(r"_+", "_", name).strip("_").lower()
    if not name:
        name = "col"
    if name[0].isdigit():
        name = f"c_{name}"
    return name


def human(n: int) -> str:
    return f"{n:,}"
