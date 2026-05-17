import os
from pathlib import Path


class Config:
    def __init__(self) -> None:
        self.mode = os.environ.get("MODE", "both")
        if self.mode not in ("update", "backup", "both"):
            raise ValueError(
                f"Invalid MODE={self.mode!r} — must be one of: update, backup, both"
            )

        self.dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"
        self.email_to = os.environ.get("EMAIL_TO", "")
        self.cron_schedule = os.environ.get("CRON_SCHEDULE", "0 3 * * *")
        self.compose_file = os.environ.get("COMPOSE_FILE", "")
        self.compose_env_file = os.environ.get("COMPOSE_ENV_FILE", "")
        self.status_file = Path("/config/status.json")

        self.rclone_src = "/data"
        self.rclone_dst = "gdrive:backups"
        self.backup_dirs: set[str] = {"backup", "backups"}

        backup_conf = Path("/config/backup.conf")
        if backup_conf.exists():
            self._load_backup_conf(backup_conf)

    def _load_backup_conf(self, path: Path) -> None:
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"')
            if key == "RCLONE_SRC":
                self.rclone_src = value
            elif key == "RCLONE_DST":
                self.rclone_dst = value
            elif key == "BACKUP_DIRS":
                self.backup_dirs = set(value.lower().split())

    @property
    def needs_update(self) -> bool:
        return self.mode in ("update", "both")

    @property
    def needs_backup(self) -> bool:
        return self.mode in ("backup", "both")
