# Lemmy Backup and Restore

This deployment runs on a single VM with `docker compose` in `/opt/lemmy`.

The important data is:

- PostgreSQL data
- `pictrs` media files
- deploy files: `docker-compose.yml`, `.env`, `lemmy.generated.hjson`

This note follows the official Lemmy backup guidance, adapted to this repo's current setup:

- https://join-lemmy.org/docs/administration/backup_and_restore.html
- https://join-lemmy.org/docs/administration/install_docker.html

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

## Notes

- The database backup is the most important part.
- `pictrs` media can grow quickly, so monitor volume size and retention.
- Do not rely only on raw PostgreSQL volume copies while the database is running.
- If you rotate GitHub secrets, make sure `/opt/lemmy/.env` and the running deployment stay in sync.
- Store backups outside the VM.
