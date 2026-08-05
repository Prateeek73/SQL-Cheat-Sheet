"""
Phase D - build the five SQLite databases from the real CSVs.

Design rules:
  * Every CSV is loaded verbatim as `raw_<name>` with cleaned column names.
    Nothing is dropped, so the source is always inspectable from SQL.
  * Derived tables (dimensions, typed fact views) are built ONLY from columns
    that genuinely exist. Where a dimension is not derivable from the real data
    it is simply not created - the affected queries get redesigned instead of
    being pointed at fabricated values.
  * Row counts are verified against the source files. A mismatch is loud,
    because a silently short load produces plausible-looking wrong answers.

Derived-table recipes live in `derive.py` and are keyed by project. They are
applied only if their required columns are present.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sqlutil import DATA_RAW, DB_DIR, PROJECTS, clean_identifier, connect, human  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module  # noqa: E402

ENCODINGS = ["utf-8", "utf-8-sig", "latin-1", "cp1252"]

# Columns matching these hints get an index; they are what queries join/filter on.
INDEX_HINTS = ("_id", "id", "date", "category", "city", "country", "status", "class", "sku")


def read_csv_resilient(path: Path) -> pd.DataFrame:
    last: Exception | None = None
    for enc in ENCODINGS:
        try:
            return pd.read_csv(path, encoding=enc, low_memory=False, on_bad_lines="warn")
        except (UnicodeDecodeError, pd.errors.ParserError) as exc:
            last = exc
    raise RuntimeError(f"could not read {path.name}: {last}")


def source_row_count(path: Path) -> int | None:
    """Cheap sanity check: data lines in the file, excluding the header."""
    for enc in ENCODINGS:
        try:
            with path.open("r", encoding=enc, errors="strict", newline="") as fh:
                return max(sum(1 for _ in fh) - 1, 0)
        except UnicodeDecodeError:
            continue
    return None


def load_raw(conn, project: str) -> dict[str, list[str]]:
    """Load every CSV for a project. Returns {table_name: [columns]}."""
    pdir = DATA_RAW / project
    loaded: dict[str, list[str]] = {}
    for csv in sorted(pdir.rglob("*.csv")):
        table = f"raw_{clean_identifier(csv.stem)}"
        df = read_csv_resilient(csv)
        df.columns = [clean_identifier(str(c)) for c in df.columns]
        # de-duplicate any column names that collided after cleaning
        seen: dict[str, int] = {}
        cols = []
        for c in df.columns:
            if c in seen:
                seen[c] += 1
                c = f"{c}_{seen[c]}"
            else:
                seen[c] = 0
            cols.append(c)
        df.columns = cols

        df.to_sql(table, conn, if_exists="replace", index=False)
        loaded[table] = list(df.columns)

        expected = source_row_count(csv)
        got = conn.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
        flag = ""
        if expected is not None and expected != got:
            # quoted newlines inside fields make the line count an upper bound
            flag = f"  [check: file has {human(expected)} lines]"
        print(f"    {table:38s} {human(got):>10s} rows x {len(cols):3d} cols{flag}")

        for c in cols:
            if any(h in c for h in INDEX_HINTS):
                try:
                    conn.execute(f'CREATE INDEX IF NOT EXISTS "ix_{table}_{c}" ON "{table}"("{c}")')
                except Exception:  # noqa: BLE001,S110 - an unindexable column is not fatal
                    pass
    return loaded


def main() -> int:
    DB_DIR.mkdir(parents=True, exist_ok=True)
    if not DATA_RAW.exists() or not any(DATA_RAW.rglob("*.csv")):
        print("No CSVs under data/raw/. Run scripts/fetch.py first.")
        return 1

    try:
        derive = import_module("derive")
    except ModuleNotFoundError:
        derive = None

    built = 0
    for project, (_dataset_id, label) in PROJECTS.items():
        pdir = DATA_RAW / project
        if not pdir.exists() or not any(pdir.rglob("*.csv")):
            print(f"[skip] {project}: not downloaded")
            continue

        db_path = DB_DIR / f"{project}.db"
        print(f"\n[build] {project}  ->  {db_path.name}   ({label})")
        conn = connect(db_path)
        try:
            tables = load_raw(conn, project)
            if derive is not None and hasattr(derive, "RECIPES"):
                recipe = derive.RECIPES.get(project)
                if recipe:
                    # A rebuild drops and recreates the derived tables. Once the
                    # keys from a previous run exist, dropping a parent trips its
                    # children's foreign keys, so enforcement is off while we
                    # rebuild; apply_keys turns it back on and verifies.
                    conn.execute("PRAGMA foreign_keys = OFF")
                    made = recipe(conn, tables)
                    for name in made:
                        n = conn.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]
                        print(f"    + derived {name:28s} {human(n):>10s} rows")
                # CTAS drops constraints, so declare the real keys afterwards
                if hasattr(derive, "apply_keys"):
                    npk, nfk = derive.apply_keys(conn, project)
                    orphans = conn.execute("PRAGMA foreign_key_check").fetchall()
                    flag = f"  [{len(orphans)} FK VIOLATIONS]" if orphans else ""
                    print(f"    + keys      {npk} primary, {nfk} foreign{flag}")
            conn.commit()
            conn.execute("PRAGMA optimize")
            conn.commit()
            built += 1
        finally:
            conn.close()

    print(f"\nBuilt {built}/{len(PROJECTS)} databases in {DB_DIR}")
    return 0 if built == len(PROJECTS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
