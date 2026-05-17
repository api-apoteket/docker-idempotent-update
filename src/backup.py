import logging
import subprocess
import time
from pathlib import Path

from .config import Config

log = logging.getLogger(__name__)

_RCLONE_FLAGS = [
    "--fast-list",
    "--transfers", "4",
    "--checkers", "6",
    "--tpslimit", "5",
    "--retries", "5",
    "--low-level-retries", "10",
    "--timeout", "15m",
    "--contimeout", "30s",
    "--stats-one-line",
    "--checksum",
    "--delete-during",
]


def run_backup(cfg: Config) -> list[str]:
    base_src = Path(cfg.rclone_src)
    failures: list[str] = []

    log.info("=== backup start: %s -> %s ===", cfg.rclone_src, cfg.rclone_dst)

    for app_dir in sorted(base_src.iterdir()):
        if not app_dir.is_dir():
            continue
        app = app_dir.name.lower()

        for candidate in _find_backup_dirs(app_dir):
            if candidate.name.lower() not in cfg.backup_dirs:
                continue

            dest = f"{cfg.rclone_dst}/{app}/{candidate.name}"

            if cfg.dry_run:
                log.info("[dry-run] would sync: %s -> %s", candidate, dest)
                continue

            synced = False
            for attempt in range(1, 4):
                try:
                    subprocess.run(
                        ["rclone", "sync", str(candidate), dest] + _RCLONE_FLAGS,
                        check=True,
                    )
                    synced = True
                    break
                except subprocess.CalledProcessError:
                    log.info("retry %d: %s/%s", attempt, app, candidate.name)
                    time.sleep(15)

            if synced:
                log.info("ok: %s/%s", app, candidate.name)
            else:
                log.info("FAILED: %s/%s", app, candidate.name)
                failures.append(f"{app}/{candidate.name}")

    log.info("=== backup complete ===")
    return failures


def _find_backup_dirs(app_dir: Path):
    for item in app_dir.iterdir():
        if item.is_dir():
            yield item
            for sub in item.iterdir():
                if sub.is_dir():
                    yield sub
