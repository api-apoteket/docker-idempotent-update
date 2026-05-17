# docker-idempotent-update

[![Build](https://github.com/blixten85/docker-idempotent-update/actions/workflows/build.yml/badge.svg)](https://github.com/blixten85/docker-idempotent-update/actions/workflows/build.yml)
[![CodeQL](https://github.com/blixten85/docker-idempotent-update/actions/workflows/codeql.yml/badge.svg)](https://github.com/blixten85/docker-idempotent-update/actions/workflows/codeql.yml)
[![Release](https://img.shields.io/github/v/release/blixten85/docker-idempotent-update)](https://github.com/blixten85/docker-idempotent-update/releases)
[![Image](https://ghcr-badge.egpl.dev/blixten85/docker-idempotent-update/size?color=blue&label=image)](https://github.com/blixten85/docker-idempotent-update/pkgs/container/docker-idempotent-update)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CodeRabbit](https://img.shields.io/coderabbit/prs/github/blixten85/docker-idempotent-update)](https://coderabbit.ai)
![Downloads](https://img.shields.io/github/downloads/blixten85/docker-idempotent-update/total)

Daily Docker host maintenance in a single container. Run **either or both** of:

1. **Update** — pull new images and recreate any containers that changed
2. **Backup** — sync app data to an rclone remote
3. **Email** — one combined summary, only when something actually happened

Runs on a schedule via an internal cron daemon. No systemd, no host dependencies beyond Docker itself.

---

## How it works

```
entrypoint.sh  (validates config based on MODE, starts crond)
└── run.sh     (runs daily at 03:00 by default)
      ├── update step    (if MODE = update | both)
      │     └── docker compose pull + up   (or socket-only — see Options)
      ├── backup step    (if MODE = backup | both)
      │     └── rclone sync per backup directory
      └── send_report.sh
            └── one combined mail if something changed or failed
```

Mail is only sent when containers were updated or a backup failed.

---

## Modes

Set `MODE` to choose which steps run:

| MODE       | Update | Backup | Required config                             |
|------------|--------|--------|---------------------------------------------|
| `update`   | ✅     | ❌     | docker socket mount                         |
| `backup`   | ❌     | ✅     | `rclone.conf`, `backup.conf`                |
| `both` *(default)* | ✅ | ✅ | docker socket + rclone config               |

`EMAIL_TO` is optional in every mode — without it nothing is mailed but the run still produces a `status.json`.

---

## Setup

### 1. Add the service to your docker-compose.yml

Copy the contents of [`docker-compose.yml`](docker-compose.yml) into your own compose file. Variables in your `.env`:

```env
DOCKER=/path/to/your/docker/data    # e.g. /home/user/.docker
CONFIG=/path/to/your/compose/dir    # e.g. /home/user/.config/docker (Option B only)
EMAIL_TO=you@example.com            # optional
```

### 2. Start the container

```bash
docker compose up -d docker-maintenance
```

On first start the container will:
- Create `$DOCKER/docker-maintenance/config/backup.conf` from template (if MODE includes backup)
- Create `$DOCKER/docker-maintenance/config/msmtprc` from template (if `EMAIL_TO` is set)
- Wait for rclone config (see step 3) — backup modes only

### 3. Configure rclone (backup modes only)

```bash
docker exec -it docker-maintenance rclone config
docker restart docker-maintenance
```

The config is written to `$DOCKER/docker-maintenance/config/rclone.conf`.

### 4. Edit config files

All config lives in `$DOCKER/docker-maintenance/config/`:

| File          | Purpose                                       | Created when            |
|---------------|-----------------------------------------------|-------------------------|
| `rclone.conf` | rclone remote configuration                   | manually via `rclone config` |
| `msmtprc`     | Mail server settings                          | when `EMAIL_TO` is set  |
| `backup.conf` | Backup source, destination and folder names  | when MODE includes backup |

After editing, apply changes with:

```bash
docker restart docker-maintenance
```

---

## Examples

### Update only (no backup, no rclone needed)

```yaml
environment:
  MODE: update
  COMPOSE_FILE: /compose/docker-compose.yml   # optional, see Options
volumes:
  - ${DOCKER}/docker-maintenance/config:/config
  - /var/run/docker.sock:/var/run/docker.sock
  - ${CONFIG}:/compose:ro                     # only with COMPOSE_FILE
```

### Backup only (no docker socket needed)

```yaml
environment:
  MODE: backup
  EMAIL_TO: ${EMAIL_TO}
volumes:
  - ${DOCKER}/docker-maintenance/config:/config
  - ${DOCKER}:/data:ro                        # the directory to back up
```

### Both (default)

See the top-level [`docker-compose.yml`](docker-compose.yml).

---

## Options (update step)

### Option A — Docker socket (no compose file needed)

Pulls images for all running containers and restarts any that were updated. Leave `COMPOSE_FILE` unset.

### Option B — Compose file (recommended)

Runs `docker compose pull` + `up -d --remove-orphans`. Set `COMPOSE_FILE` and mount your compose directory at `/compose:ro`.

---

## Backup folder structure

`backup.conf` controls which directory is scanned and which folder names are synced.
Default: scans `$DOCKER` for folders named `backup` or `backups` (case-insensitive) up to two levels deep.

```
$DOCKER/
  prowlarr/
    backups/      →  gdrive:backups/prowlarr/backups/
  sonarr/
    config/
      backup/     →  gdrive:backups/sonarr/backup/
```

---

## Environment variables

| Variable          | Default        | Description                                         |
|-------------------|----------------|-----------------------------------------------------|
| `MODE`            | `both`         | `update`, `backup`, or `both`                       |
| `EMAIL_TO`        | *(unset)*      | Mail recipient — no mail sent if empty              |
| `CRON_SCHEDULE`   | `0 3 * * *`    | When to run                                         |
| `DRY_RUN`         | `false`        | If `true`, log actions without making changes       |
| `RCLONE_CONFIG`   | `/config/rclone.conf` | rclone config path inside container          |
| `COMPOSE_FILE`    | *(unset)*      | Full path to compose file inside container (Option B) |
| `COMPOSE_ENV_FILE`| *(unset)*      | Path to .env file passed to `docker compose --env-file` |
