import logging
import socket
import subprocess
from datetime import date
from pathlib import Path

log = logging.getLogger(__name__)


def send_report(
    email_to: str, docker_changes: str, backup_failures: list[str]
) -> None:
    if not email_to or not Path("/etc/msmtprc").exists():
        return
    if not docker_changes and not backup_failures:
        return

    host = socket.gethostname()
    today = date.today().strftime("%Y-%m-%d")

    body_parts = []
    if docker_changes:
        body_parts.append(f"=== Container updates ===\n{docker_changes}")
    if backup_failures:
        lines = "\n".join(f"  ✗ {f}" for f in backup_failures)
        body_parts.append(f"=== Backup failures ===\n{lines}")
    body = "\n\n".join(body_parts)

    if backup_failures and docker_changes:
        subject = f"\U0001f433 Docker updated + ⚠️ backup failed – {host} {today}"
    elif backup_failures:
        subject = f"⚠️ Backup failed – {host} {today}"
    else:
        subject = f"\U0001f433 Docker updated – {host} {today}"

    try:
        subprocess.run(
            ["msmtp", email_to],
            input=f"Subject: {subject}\n\n{body}",
            text=True,
            check=True,
        )
        log.info("Mail sent: %s", subject)
    except subprocess.CalledProcessError:
        log.warning("Failed to send mail")
