import json
import logging
import sys
from datetime import datetime, timezone

from .backup import run_backup
from .config import Config
from .docker_update import run_update
from .report import send_report

logging.basicConfig(
    format="[%(asctime)s] %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
    stream=sys.stdout,
)
log = logging.getLogger(__name__)


def main() -> None:
    cfg = Config()

    if cfg.dry_run:
        log.info("=== DRY RUN MODE — no changes will be made ===")
    log.info("=== mode: %s ===", cfg.mode)

    docker_changes = ""
    containers_updated: list[str] = []
    backup_failures: list[str] = []

    if cfg.needs_update:
        log.info("=== docker update ===")
        docker_changes, containers_updated = run_update(cfg)

    if cfg.needs_backup:
        log.info("=== rclone backup ===")
        backup_failures = run_backup(cfg)

    log.info("=== send report ===")
    send_report(cfg.email_to, docker_changes, backup_failures)

    log.info("=== writing status ===")
    _write_status(cfg, docker_changes, containers_updated, backup_failures)


def _write_status(
    cfg: Config,
    docker_changes: str,
    containers_updated: list[str],
    backup_failures: list[str],
) -> None:
    status = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": cfg.mode,
        "dry_run": cfg.dry_run,
        "containers_updated": containers_updated,
        "backup_failures": backup_failures,
        "docker_changes": docker_changes,
    }
    cfg.status_file.write_text(json.dumps(status, indent=2))
    log.info("Status written to %s", cfg.status_file)


if __name__ == "__main__":
    main()
