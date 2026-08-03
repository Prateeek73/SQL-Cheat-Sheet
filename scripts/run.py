"""
Phase F - execute every query and report per-question results.

Fixes three defects in the orchestrator this replaced:
  * query files are discovered by glob, not by building a filename from the
    project key - that approach looked for two files which did not exist, so two
    whole projects were silently skipped;
  * statements are separated with a real SQL-aware splitter, not split('\\n--Q'),
    which matched nothing;
  * a query that runs but returns zero rows is reported as WARN, not success.
    An empty result set almost always means the rewrite lost a filter or a join.

Usage:  python scripts/run.py [--project project_2_churn] [--verbose]
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sqlutil import DB_DIR, DOCS_DIR, PROJECT_ROOT, PROJECTS, QUERY_DIR, connect, split_sql  # noqa: E402

PREVIEW_ROWS = 5


def project_for(sql_file: Path) -> str | None:
    """Map a query file to its project by the ordinal that starts its name.

    01_ecommerce.sql -> 1 -> the 1st key of PROJECTS -> project_1_ecommerce

    Files are still discovered by glob, never by rebuilding a filename from the
    project key - that was the defect which silently skipped two whole projects
    in the original orchestrator, and it must not come back.
    """
    m = re.match(r"^(\d+)", sql_file.stem)
    if not m:
        return None
    idx = int(m.group(1))
    keys = list(PROJECTS)
    return keys[idx - 1] if 1 <= idx <= len(keys) else None


def run_file(sql_file: Path, project: str, verbose: bool) -> list[dict]:
    db_path = DB_DIR / f"{project}.db"
    results: list[dict] = []
    if not db_path.exists():
        return [{"label": "-", "title": "database missing", "status": "FAIL",
                 "rows": 0, "ms": 0.0, "error": f"{db_path.name} not built"}]

    conn = connect(db_path)
    try:
        for st in split_sql(sql_file.read_text(encoding="utf-8", errors="replace")):
            t0 = time.perf_counter()
            rec = {"label": st.label, "title": st.title, "ms": 0.0,
                   "rows": 0, "status": "OK", "error": ""}
            try:
                cur = conn.execute(st.sql)
                rows = cur.fetchall()
                rec["rows"] = len(rows)
                rec["ms"] = (time.perf_counter() - t0) * 1000
                if not rows:
                    rec["status"] = "WARN"
                    rec["error"] = "returned 0 rows"
                elif verbose:
                    cols = [d[0] for d in cur.description]
                    print(f"      {cols}")
                    for r in rows[:PREVIEW_ROWS]:
                        print(f"      {r}")
            except Exception as exc:  # noqa: BLE001 - collect, don't abort the sweep
                rec["ms"] = (time.perf_counter() - t0) * 1000
                rec["status"] = "FAIL"
                rec["error"] = f"{type(exc).__name__}: {exc}"
            results.append(rec)
            mark = {"OK": "ok  ", "WARN": "warn", "FAIL": "FAIL"}[rec["status"]]
            print(f"    [{mark}] {rec['label']:>4s} {rec['title'][:52]:52s} "
                  f"{rec['rows']:>8,d} rows {rec['ms']:8.1f} ms")
            if rec["status"] == "FAIL":
                print(f"           -> {rec['error']}")
    finally:
        conn.close()
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="run only this project key")
    ap.add_argument("--verbose", action="store_true", help="print result previews")
    args = ap.parse_args()

    files = sorted(QUERY_DIR.glob("*.sql"))
    if not files:
        print(f"No .sql files in {QUERY_DIR}")
        return 1

    print("=" * 78)
    print("PHASE F: QUERY EXECUTION")
    print("=" * 78)

    all_results: dict[str, list[dict]] = {}
    for f in files:
        project = project_for(f)
        if project is None:
            print(f"[skip] {f.name}: cannot map to a project")
            continue
        if args.project and project != args.project:
            continue
        print(f"\n[{project}]  {f.name}")
        all_results[project] = run_file(f, project, args.verbose)

    total = sum(len(v) for v in all_results.values())
    ok = sum(1 for v in all_results.values() for r in v if r["status"] == "OK")
    warn = sum(1 for v in all_results.values() for r in v if r["status"] == "WARN")
    fail = sum(1 for v in all_results.values() for r in v if r["status"] == "FAIL")

    lines = ["# Query Execution Results", "",
             f"**{ok} passed, {warn} returned no rows, {fail} failed, {total} total.**", ""]
    for project, res in all_results.items():
        p_ok = sum(1 for r in res if r["status"] == "OK")
        lines += [f"## {project} - {p_ok}/{len(res)} returning rows", "",
                  "| Q | title | status | rows | ms | error |", "|---|---|---|---|---|---|"]
        for r in res:
            lines.append(
                f"| {r['label']} | {r['title'][:60]} | {r['status']} | {r['rows']:,} "
                f"| {r['ms']:.1f} | {r['error'][:80]} |"
            )
        lines.append("")

    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    out = DOCS_DIR / "RESULTS.md"
    out.write_text("\n".join(lines), encoding="utf-8")

    print("\n" + "=" * 78)
    print(f"TOTAL: {ok} ok / {warn} empty / {fail} failed  (of {total})")
    try:
        shown = out.relative_to(PROJECT_ROOT)
    except ValueError:  # DOCS_DIR redirected (tests) - fall back to the absolute path
        shown = out
    print(f"Report: {shown}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
