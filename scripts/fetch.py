"""
Phase B - acquire the five real Kaggle datasets into data/raw/<project>/.

Two acquisition paths, tried in order:

  1. Kaggle API. The kaggle 2.x client accepts OAuth (`kaggle auth login`),
     KAGGLE_API_TOKEN, ~/.kaggle/access_token, or a legacy ~/.kaggle/kaggle.json.
  2. Manual ZIPs dropped in data/_incoming/ - matched to a project by filename.

A dataset either lands complete or is reported missing; we never leave a project
half-populated, because a partially loaded table silently produces wrong answers
in every downstream query.
"""

from __future__ import annotations

import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sqlutil import DATA_INCOMING, DATA_RAW, PROJECTS  # noqa: E402


def detect_credentials() -> str:
    """Best-effort description of how the Kaggle client is likely to authenticate.

    Advisory only. We never gate the download on this: the client supports OAuth
    (which caches to ~/.kaggle/credentials.json), token files, and env vars, and
    the exact set of locations changes between releases. Guessing wrong here once
    caused a fully logged-in user to be told they had no credentials, so the API
    is now always attempted and this string is for the log line only.
    """
    home = Path.home()
    if os.environ.get("KAGGLE_API_TOKEN"):
        return "KAGGLE_API_TOKEN environment variable"
    if os.environ.get("KAGGLE_USERNAME") and os.environ.get("KAGGLE_KEY"):
        return "KAGGLE_USERNAME/KAGGLE_KEY environment variables"
    for candidate, desc in [
        (home / ".kaggle" / "credentials.json", "~/.kaggle/credentials.json (OAuth)"),
        (home / ".kaggle" / "access_token", "~/.kaggle/access_token"),
        (home / ".kaggle" / "kaggle.json", "~/.kaggle/kaggle.json (legacy)"),
        (home / ".config" / "kaggle" / "access_token", "~/.config/kaggle/access_token"),
    ]:
        if candidate.exists():
            return desc
    return "none detected (the API will still be attempted)"


def try_api(project: str, dataset_id: str, target: Path) -> bool:
    try:
        import kaggle  # noqa: PLC0415  (import is deliberately lazy: it authenticates on import)

        kaggle.api.dataset_download_files(dataset_id, path=str(target), unzip=True, quiet=False)
        return any(target.iterdir())
    except Exception as exc:  # noqa: BLE001 - report and fall through to the zip path
        print(f"    ! Kaggle API failed for {project}: {type(exc).__name__}: {exc}")
        return False


def try_incoming_zip(project: str, dataset_id: str, target: Path) -> bool:
    """Match a manually downloaded zip to this project.

    Kaggle names downloads after the dataset slug, so we match on that first,
    then fall back to any zip whose name shares a distinctive token.
    """
    if not DATA_INCOMING.exists():
        return False
    slug = dataset_id.split("/")[-1].lower()
    zips = list(DATA_INCOMING.glob("*.zip"))
    tokens = [t for t in slug.replace("-", " ").split() if len(t) > 4]

    def score(z: Path) -> int:
        name = z.stem.lower()
        if name == slug:
            return 100
        return sum(1 for t in tokens if t in name)

    ranked = sorted(((score(z), z) for z in zips), key=lambda p: -p[0])
    if not ranked or ranked[0][0] == 0:
        return False
    chosen = ranked[0][1]
    print(f"    using manual zip: {chosen.name}")
    with zipfile.ZipFile(chosen) as zf:
        zf.extractall(target)
    return any(target.iterdir())


def main() -> int:
    DATA_RAW.mkdir(parents=True, exist_ok=True)
    DATA_INCOMING.mkdir(parents=True, exist_ok=True)

    print("=" * 78)
    print("PHASE B: DATASET ACQUISITION")
    print("=" * 78)
    print(f"Kaggle auth: {detect_credentials()}")
    print(f"Manual zips in data/_incoming: {len(list(DATA_INCOMING.glob('*.zip')))}")
    print()

    ok, failed = [], []
    for project, (dataset_id, label) in PROJECTS.items():
        target = DATA_RAW / project
        target.mkdir(parents=True, exist_ok=True)
        existing = [p for p in target.rglob("*") if p.is_file()]
        if existing:
            print(f"[skip] {project:22s} already populated ({len(existing)} files)")
            ok.append(project)
            continue

        print(f"[get ] {project:22s} {label}  <- {dataset_id}")
        # Always try the API; only fall back to a manual zip if it genuinely fails.
        done = try_api(project, dataset_id, target)
        if not done:
            done = try_incoming_zip(project, dataset_id, target)

        if done:
            files = [p for p in target.rglob("*") if p.is_file()]
            total = sum(p.stat().st_size for p in files)
            print(f"    OK  {len(files)} file(s), {total/1_048_576:.1f} MB")
            ok.append(project)
        else:
            # leave no partial directory behind
            for p in sorted(target.rglob("*"), reverse=True):
                p.unlink() if p.is_file() else p.rmdir()
            print("    MISSING")
            failed.append((project, dataset_id))

    print()
    print(f"Acquired {len(ok)}/{len(PROJECTS)} datasets.")
    if failed:
        print("\nStill needed:")
        for project, dataset_id in failed:
            print(f"  - {project}: https://www.kaggle.com/datasets/{dataset_id}")
        print(
            "\nTo proceed, either:\n"
            "  A) Authenticate the Kaggle client:\n"
            "       kaggle auth login              (browser OAuth, easiest)\n"
            "     or generate a token at https://www.kaggle.com/settings/api and save it\n"
            "     to C:\\Users\\<you>\\.kaggle\\access_token\n"
            "  B) Download each ZIP from the URLs above and drop them, unrenamed, into:\n"
            f"       {DATA_INCOMING}\n"
            "  Then re-run: python scripts/fetch.py"
        )
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
