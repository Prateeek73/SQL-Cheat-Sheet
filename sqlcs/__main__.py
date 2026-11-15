"""sqlcs - run the SQL practice pipeline, and keep its databases and site in an S3 bucket.

Commands (run from a checkout or the image, which is a checkout at /app):

  fetch | build | run | site   the existing scripts, unchanged (extra arguments pass through)
  push                         upload db/*.db and docs/ (the site) to the bucket
  pull                         download db/*.db from the bucket
  load                         fetch, build, drop the downloads, run, site, push   (a one-off job)
  refresh                      pull, run, site, push                 (a scheduled job)
  serve                        serve docs/ on $PORT; re-pull the site's data from the bucket
                               every $SQLCS_SYNC_SECONDS (default 300), so a refresh shows
                               up without a redeploy                 (an app)

The bucket comes from S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY and
S3_REGION (optional), under the prefix SQLCS_PREFIX (default "sql-cheat-sheet/").
"""

from __future__ import annotations

import http.server
import os
import runpy
import shutil
import sys
import threading
import time
from pathlib import Path

# The first of: SQLCS_ROOT, the checkout the package sits in (pip install -e .), the
# working directory, /app (the image; a job may start in / rather than the image's WORKDIR).
_CANDIDATES = [os.environ.get("SQLCS_ROOT"), Path(__file__).resolve().parent.parent, Path.cwd(), "/app"]
ROOT = next((Path(c) for c in _CANDIDATES if c and (Path(c) / "scripts").is_dir()), Path.cwd())
os.chdir(ROOT)  # the scripts write relative paths too (docs/RESULTS.md)
SCRIPTS = ROOT / "scripts"
DB_DIR = ROOT / "db"
DOCS_DIR = ROOT / "docs"
PREFIX = os.environ.get("SQLCS_PREFIX", "sql-cheat-sheet/")


def use_scratch() -> None:
    """Put data/ and db/ under $SQLCS_SCRATCH (e.g. a RAM-backed /tmp) when it is set.

    A platform job's disk may be far smaller than the ~1 GB of downloads and databases;
    its /tmp is RAM (half the job's memory). The scripts keep their paths: data/ and db/
    become links into the scratch directory.
    """
    scratch = os.environ.get("SQLCS_SCRATCH")
    if not scratch:
        return
    for name in ("data", "db"):
        target = Path(scratch) / name
        target.mkdir(parents=True, exist_ok=True)
        link = ROOT / name
        if link.is_symlink() and link.resolve() == target.resolve():
            continue
        if link.is_dir() and not any(link.iterdir()):
            link.rmdir()
        elif link.exists() or link.is_symlink():
            sys.exit(f"sqlcs: {link} holds files; move them before using SQLCS_SCRATCH")
        link.symlink_to(target, target_is_directory=True)
    # SQLite's own temporary files (a big sort, an index build) default to /var/tmp, on the
    # small disk: send them to the scratch directory as well.
    tmp = Path(scratch) / "sqlite-tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    os.environ["SQLITE_TMPDIR"] = str(tmp)
    usage = shutil.disk_usage(scratch)
    print(f"sqlcs: data/, db/ and SQLite's temp files in {scratch} ({usage.free / 2**30:.1f} GiB free)", flush=True)


def drop_downloads() -> int:
    """Free the downloads once the databases are built: nothing after build reads data/."""
    raw = ROOT / "data"
    for child in raw.iterdir() if raw.is_dir() else []:
        shutil.rmtree(child) if child.is_dir() else child.unlink()
    print("dropped data/ (the databases are built)", flush=True)
    return 0


def script(name: str, args: list[str] | None = None) -> int:
    """Run scripts/<name>.py as if from the command line; return its exit code."""
    sys.argv = [f"{name}.py", *(args or [])]
    sys.path.insert(0, str(SCRIPTS))
    try:
        runpy.run_path(str(SCRIPTS / f"{name}.py"), run_name="__main__")
    except SystemExit as exit_:
        code = exit_.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    return 0


def bucket():
    import boto3  # noqa: PLC0415 - only the bucket commands need it

    missing = [k for k in ("S3_ENDPOINT", "S3_BUCKET", "S3_ACCESS_KEY_ID", "S3_SECRET_ACCESS_KEY") if not os.environ.get(k)]
    if missing:
        sys.exit(f"sqlcs: set {', '.join(missing)} for the bucket")
    client = boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"],
        region_name=os.environ.get("S3_REGION") or "garage",
    )
    return client, os.environ["S3_BUCKET"]


def push(databases: bool = True) -> int:
    client, name = bucket()
    files = sorted(DB_DIR.glob("*.db")) if databases else []
    files += [p for p in sorted(DOCS_DIR.rglob("*")) if p.is_file()]
    for path in files:
        key = PREFIX + path.relative_to(ROOT).as_posix()
        client.upload_file(str(path), name, key)
        print(f"  up   {key} ({path.stat().st_size:,} B)")
    print(f"pushed {len(files)} files to s3://{name}/{PREFIX}")
    return 0


def pull(subdir: str = "db/") -> int:
    client, name = bucket()
    paginator = client.get_paginator("list_objects_v2")
    count = 0
    for page in paginator.paginate(Bucket=name, Prefix=PREFIX + subdir):
        for obj in page.get("Contents", []):
            target = ROOT / obj["Key"][len(PREFIX):]
            target.parent.mkdir(parents=True, exist_ok=True)
            client.download_file(name, obj["Key"], str(target))
            count += 1
    print(f"pulled {count} files from s3://{name}/{PREFIX}{subdir}")
    return 0 if count or subdir != "db/" else 1


def steps(*names: str) -> int:
    for step in names:
        print(f"\n=== sqlcs {step} ===", flush=True)
        code = {
            "fetch": lambda: script("fetch"),
            "build": lambda: script("build"),
            "run": lambda: script("run"),
            "site": lambda: script("build_site"),
            "push": push,
            "push-site": lambda: push(databases=False),
            "pull": pull,
            "drop-downloads": drop_downloads,
        }[step]()
        if code:
            print(f"sqlcs: {step} failed ({code})", file=sys.stderr)
            return code
    return 0


def serve() -> int:
    port = int(os.environ.get("PORT", "8080"))
    every = int(os.environ.get("SQLCS_SYNC_SECONDS", "300"))
    synced = bool(os.environ.get("S3_BUCKET"))

    def sync_forever() -> None:
        while True:
            try:
                pull("docs/")
            except Exception as exc:  # noqa: BLE001 - keep serving the last good copy
                print(f"sqlcs serve: sync failed: {exc}", file=sys.stderr, flush=True)
            time.sleep(every)

    if synced:
        threading.Thread(target=sync_forever, daemon=True).start()
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(DOCS_DIR), **kw)

        def do_GET(self):  # noqa: N802 - http.server's name
            if self.path in ("/", ""):
                self.send_response(302)
                self.send_header("Location", "/QUESTIONS.html")
                self.end_headers()
                return
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
                return
            super().do_GET()

    print(f"sqlcs serve: docs/ on :{port}" + (f", synced from the bucket every {every}s" if synced else ""), flush=True)
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["sqlcs"]:  # a platform that passes the job's whole command as arguments to the entrypoint
        args = args[1:]
    command = args[0] if args else "help"
    if command in ("fetch", "build", "run", "site", "push", "pull", "load", "refresh"):
        use_scratch()
    if command in ("fetch", "build", "run", "site"):
        return script({"site": "build_site"}.get(command, command), args[1:])
    if command in ("push", "pull"):
        return steps(command)
    if command == "load":
        return steps("fetch", "build", "drop-downloads", "run", "site", "push")
    if command == "refresh":
        return steps("pull", "run", "site", "push-site")
    if command == "serve":
        return serve()
    print(__doc__)
    return 0 if command in ("help", "-h", "--help") else 2


if __name__ == "__main__":
    sys.exit(main())
