# Backup Testing

This note describes how to verify that Lemmy backups are actually restorable.

Creating backup files is not enough. The only reliable proof is a full restore test on a separate machine.

## Goal

A backup process should be considered valid only if you can:

- restore the database
- restore `pictrs` media
- start the full application
- confirm that the restored instance behaves correctly

## What Must Be Tested

At minimum, test these items together:

- PostgreSQL dump restore
- `lemmy_pictrs_data` restore
- deploy file restore
- full application startup
- basic UI and API functionality

## Recommended Test Environment

Use a separate VM, not production.

It should be as close as possible to production:

- same OS family
- same Docker / Compose setup
- same Lemmy version

Do not use the production host for restore testing.

## Full Restore Drill

### 1. Create A Fresh Backup

Create a real backup from production:

- PostgreSQL dump
- `pictrs` archive
- deploy files from `/opt/lemmy`

Use the commands from [BACKUP.md](./BACKUP.md).

### 2. Prepare A Clean Restore Target

On the test VM:

- install Docker and Docker Compose
- create the target directory, for example `/opt/lemmy`
- copy in:
  - `docker-compose.yml`
  - `.env`
  - `lemmy.generated.hjson`

### 3. Restore The Database

Start only PostgreSQL:

```bash
docker compose up -d postgres
```

Restore the SQL dump:

```bash
gunzip < lemmy_db_YYYY-MM-DD_HH-MM-SS.sql.gz | docker compose exec -T postgres psql -U lemmy
```

### 4. Restore `pictrs`

Extract the archived media into the `lemmy_pictrs_data` volume.

### 5. Start The Full Stack

```bash
docker compose up -d
```

## Validation Checklist

The restore test is only successful if all of the following are true:

- all containers are running
- `postgres` is healthy
- `lemmy` starts without restart loops
- `lemmy-ui` serves the site
- `/api/v3/site` returns `200`
- existing posts are visible
- existing comments are visible
- uploaded images are accessible
- admin login works

## Example Validation Commands

Check containers:

```bash
docker compose ps
```

Check backend API:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8536/api/v3/site
```

Check UI:

```bash
curl -sS -I http://127.0.0.1:1234
```

Check logs:

```bash
docker compose logs --tail=100 postgres lemmy pictrs lemmy-ui
```

## What To Verify Manually

Also verify these in a browser:

- the front page loads
- posts render normally
- comments render normally
- images load
- the instance hostname is correct
- the admin account can sign in

## Ongoing Confidence

To stay confident over time, do not stop after one successful test.

Recommended practice:

- run backups on a schedule
- verify that backup files are created and non-empty
- store backups outside the production VM
- run a full restore drill regularly
- repeat the restore drill after major upgrades

## Suggested Cadence

- database backup: daily
- media backup: daily or according to acceptable data loss
- restore drill: monthly
- extra restore drill: after Lemmy, PostgreSQL, or deployment changes

## Recovery Targets

Define these explicitly:

- `RPO`: how much data loss is acceptable
- `RTO`: how quickly the service must be restorable

Without those numbers, it is hard to judge whether the backup schedule is good enough.

## Failure Cases To Simulate

At least once, test these scenarios:

- restore to a completely clean VM
- restore after deleting all Docker volumes
- restore after changing secrets and config files
- restore after upgrading Lemmy

## Operational Requirement

Treat backup testing as an operational procedure, not a one-time setup task.

If you change:

- Lemmy version
- PostgreSQL version
- Docker / Compose behavior
- config structure
- media settings

then repeat the restore drill.
