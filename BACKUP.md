# Lemmy Backup and Restore

This deployment runs on a single VM with `docker compose` in `/opt/lemmy`.

The important data is:

- PostgreSQL data
- `pictrs` media files
- deploy files: `docker-compose.yml`, `.env`, `lemmy.generated.hjson`

This note follows the official Lemmy backup guidance, adapted to this repo's current setup:

- https://join-lemmy.org/docs/administration/backup_and_restore.html
- https://join-lemmy.org/docs/administration/install_docker.html

The tested VM automation files for this backup flow are stored in:

- [ops/backup/lemmy-backup.sh](/home/denchik/projects/Lemmy-deploy/ops/backup/lemmy-backup.sh)
- [ops/backup/lemmy-backup.env](/home/denchik/projects/Lemmy-deploy/ops/backup/lemmy-backup.env)
- [ops/backup/lemmy-backup.service](/home/denchik/projects/Lemmy-deploy/ops/backup/lemmy-backup.service)
- [ops/backup/lemmy-backup.timer](/home/denchik/projects/Lemmy-deploy/ops/backup/lemmy-backup.timer)

## What To Back Up

At minimum, back up:

- a PostgreSQL dump
- the `lemmy_pictrs_data` Docker volume

Also keep a copy of:

- `/opt/lemmy/docker-compose.yml`
- `/opt/lemmy/.env`
- `/opt/lemmy/lemmy.generated.hjson`

## Storage Growth

In practice, `pictrs` storage can grow faster than expected.

Two things matter here:

- user-uploaded media
- locally stored image derivatives such as thumbnails / previews

This means the `lemmy_pictrs_data` volume can become the largest part of the backup set.

You should monitor its size regularly:

```bash
ssh nu31forum 'docker system df -v'
```

If storage growth becomes a problem, review your Lemmy media settings in `lemmy.generated.hjson` / `lemmy.hjson.template`.

One commonly suggested option is setting `image_mode = None`, which reduces locally stored image data and keeps only actively uploaded media.

Use that only if it matches the behavior you want for the instance.

## Database Backup

Run from your local machine:

```bash
ssh nu31forum 'cd /opt/lemmy && docker compose exec -T postgres pg_dumpall -c -U lemmy' | gzip > lemmy_db_$(date +%F_%H-%M-%S).sql.gz
```

This creates a logical PostgreSQL backup.

## Media Backup

Create a tarball of the `pictrs` volume on the VM:

```bash
ssh nu31forum 'docker run --rm -v lemmy_pictrs_data:/source -v /root:/backup alpine sh -c "tar czf /backup/lemmy_pictrs_$(date +%F_%H-%M-%S).tar.gz -C /source ."'
```

Copy the archive to your local machine:

```bash
scp nu31forum:/root/lemmy_pictrs_*.tar.gz .
```

## Deploy File Backup

Copy the current deploy files from the VM:

```bash
scp nu31forum:/opt/lemmy/docker-compose.yml .
scp nu31forum:/opt/lemmy/.env .
scp nu31forum:/opt/lemmy/lemmy.generated.hjson .
```

## Restore

Restore order:

1. Put `docker-compose.yml`, `.env`, and `lemmy.generated.hjson` back into `/opt/lemmy`.
2. Start only PostgreSQL.
3. Restore the database dump.
4. Restore the `pictrs` volume.
5. Start the full stack.

### 1. Start PostgreSQL

```bash
ssh nu31forum 'cd /opt/lemmy && docker compose up -d postgres'
```

### 2. Restore Database

```bash
gunzip < lemmy_db_YYYY-MM-DD_HH-MM-SS.sql.gz | ssh nu31forum 'cd /opt/lemmy && docker compose exec -T postgres psql -U lemmy'
```

### 3. Restore Media

Copy the archive to the VM:

```bash
scp lemmy_pictrs_YYYY-MM-DD_HH-MM-SS.tar.gz nu31forum:/root/
```

Extract it into the Docker volume:

```bash
ssh nu31forum 'docker run --rm -v lemmy_pictrs_data:/target -v /root:/backup alpine sh -c "rm -rf /target/* && tar xzf /backup/lemmy_pictrs_YYYY-MM-DD_HH-MM-SS.tar.gz -C /target"'
```

### 4. Start The Full Stack

```bash
ssh nu31forum 'cd /opt/lemmy && docker compose up -d'
```

## Validated Local Restore Drill

This backup flow was validated on a separate local machine with `docker compose`.

Validated local restore order:

1. Copy `docker-compose.yml`, `.env`, `lemmy.generated.hjson`, `lemmy_db.sql.gz`, and `lemmy_pictrs.tar.gz` into a separate local test directory.
2. For local-only testing, change `LEMMY_HOSTNAME` to `localhost`.
3. For local-only testing, set `hostname: "localhost"` and `tls_enabled: false` in `lemmy.generated.hjson`.
4. Start only `postgres`.
5. Restore the SQL dump.
6. Restore the `pictrs` volume.
7. Start the full stack.

Example local restore sequence:

```bash
docker compose up -d postgres
gunzip -c lemmy_db.sql.gz | docker compose exec -T postgres psql -U lemmy
docker run --rm -v lemmy_pictrs_data:/target -v "$PWD:/backup" alpine:3.20 sh -c 'rm -rf /target/* && tar xzf /backup/lemmy_pictrs.tar.gz -C /target'
docker compose up -d
```

## Restore Validation Checks

A restore should be considered successful only after checking both the stack state and the restored data.

Recommended checks:

```bash
docker compose ps
curl -I http://127.0.0.1:1234
curl -sS http://127.0.0.1:8536/api/v3/site
curl -sS 'http://127.0.0.1:8536/api/v3/post/list?type_=Local&sort=New&limit=10'
curl -sS 'http://127.0.0.1:8536/api/v3/comment/list?type_=All&limit=10'
```

Expected outcome:

- `lemmy`, `lemmy-ui`, and `postgres` are healthy
- the UI returns `200`
- the API returns `200`
- restored posts and comments are present
- `pictrs` media files are present

## Localhost Limitation

API-level restore validation is sufficient to confirm that the backup mechanism works.

However, a localhost restore can still have browser-side issues because the restored data keeps the original site origin, for example `https://forum.nu31.space`.

In practice this means:

- direct API login can work
- the browser UI on `http://localhost:1234` can still fail for some actions, including login, because of origin / hostname mismatch

For a fully realistic browser test, restore under the original hostname or use local host mapping plus a local reverse proxy.

## Notes

- The database backup is the most important part.
- `pictrs` media can grow quickly, so monitor volume size and retention.
- A successful API-level restore is enough to validate the backup mechanism even if a localhost browser session is not fully identical to production.
- Do not rely only on raw PostgreSQL volume copies while the database is running.
- If you rotate GitHub secrets, make sure `/opt/lemmy/.env` and the running deployment stay in sync.
- Store backups outside the VM.

## Tested VM Automation

The current tested automation on `nu31forum` uses:

- `/usr/local/bin/lemmy-backup.sh`
- `/etc/default/lemmy-backup`
- `/etc/systemd/system/lemmy-backup.service`
- `/etc/systemd/system/lemmy-backup.timer`

The checked-in equivalents are under [ops/backup](/home/denchik/projects/Lemmy-deploy/ops/backup).
