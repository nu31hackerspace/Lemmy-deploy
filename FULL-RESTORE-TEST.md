# Full Restore Test Under the Original Hostname

This note describes how to run a full local restore test for this Lemmy deployment in a way that preserves the original hostname behavior.

This is different from a simple localhost restore:

- a localhost restore is enough to validate that backups can be restored
- a full browser restore test should run under `forum.nu31.space`

That matters because the restored instance data still contains the original site identity and URLs.

## Goal

Run a local restored copy of Lemmy so that:

- the browser opens `forum.nu31.space`
- the restored UI and API are both served under that hostname
- login and browser-side requests behave as closely to production as possible

## Important Warning

While this test is active, your local machine will resolve `forum.nu31.space` to `127.0.0.1`.

That means:

- on this machine, `forum.nu31.space` will point to the local restored copy
- not to the production server

Remove the hosts entry after the test.

## What You Need

- Docker and `docker compose`
- a local restore directory with:
  - `docker-compose.yml`
  - `.env`
  - `lemmy.generated.hjson`
  - `lemmy_db.sql.gz`
  - `lemmy_pictrs.tar.gz`
- a local reverse proxy
  - Caddy is the easiest option here

## Restore Strategy

Do not publish the restored stack on the production ports directly.

Instead:

- run the restored Lemmy UI and backend on alternate local ports
- route `forum.nu31.space` to those ports through a local reverse proxy
- make the browser access the restored copy through the original hostname

## 1. Prepare the Restore Directory

Example:

```bash
mkdir -p ~/lemmy-full-restore-test
cd ~/lemmy-full-restore-test
```

Place these files there:

- `docker-compose.yml`
- `.env`
- `lemmy.generated.hjson`
- `lemmy_db.sql.gz`
- `lemmy_pictrs.tar.gz`

## 2. Keep the Original Hostname in Config

For this test, the restored config should keep the real site hostname:

In `.env`:

```env
LEMMY_HOSTNAME=forum.nu31.space
```

In `lemmy.generated.hjson`:

```hjson
hostname: "forum.nu31.space"
```

You can keep `tls_enabled: false` if TLS is terminated by the local reverse proxy.

## 3. Use Alternate Local Ports

Create a compose override file so the restored stack does not clash with anything else:

`docker-compose.override.yml`

```yaml
services:
  lemmy:
    ports:
      - "127.0.0.1:18536:8536"

  lemmy-ui:
    ports:
      - "127.0.0.1:11234:1234"
    environment:
      LEMMY_UI_LEMMY_EXTERNAL_HOST: forum.nu31.space
      LEMMY_UI_HTTPS: "false"
```

This keeps the restored services local-only and moves them away from the default ports.

## 4. Restore the Database

Start only PostgreSQL first:

```bash
docker compose up -d postgres
```

Restore the SQL dump:

```bash
gunzip -c lemmy_db.sql.gz | docker compose exec -T postgres psql -U lemmy
```

## 5. Restore the `pictrs` Volume

Restore media into the compose volume:

```bash
docker run --rm \
  -v lemmy-full-restore-test_pictrs_data:/target \
  -v "$PWD:/backup" \
  alpine:3.20 \
  sh -c 'rm -rf /target/* && tar xzf /backup/lemmy_pictrs.tar.gz -C /target'
```

If your compose project name is different, use the actual volume name shown by:

```bash
docker volume ls
```

## 6. Start the Full Restore Stack

```bash
docker compose up -d
```

Verify the services:

```bash
docker compose ps
```

## 7. Map the Original Hostname Locally

Add this line to `/etc/hosts`:

```text
127.0.0.1 forum.nu31.space
```

Example:

```bash
echo '127.0.0.1 forum.nu31.space' | sudo tee -a /etc/hosts
```

## 8. Run a Local Reverse Proxy

Use a local Caddy config such as:

```caddy
forum.nu31.space {
    @lemmy_api path /api/* /pictrs/* /feeds/* /nodeinfo/* /.well-known/*
    @lemmy_activity header Accept *application/activity+json*
    @lemmy_ld header Accept *application/ld+json*
    @lemmy_post method POST

    handle @lemmy_api {
        reverse_proxy 127.0.0.1:18536
    }

    handle @lemmy_activity {
        reverse_proxy 127.0.0.1:18536
    }

    handle @lemmy_ld {
        reverse_proxy 127.0.0.1:18536
    }

    handle @lemmy_post {
        reverse_proxy 127.0.0.1:18536
    }

    handle {
        reverse_proxy 127.0.0.1:11234
    }
}
```

Start Caddy with that config.

If you prefer HTTPS, you can extend this setup with local certificates, but plain HTTP is enough for a browser-level restore test in most cases.

## 9. Open the Restored Instance

Open:

```text
http://forum.nu31.space
```

At this point, the browser is using the same hostname as the restored instance data.

This is the key difference from a localhost-only restore.

## 10. Validate the Restore

Recommended checks:

- the homepage opens
- the admin account can log in through the browser
- restored posts are visible
- restored comments are visible
- image posts and uploaded media load correctly
- `/api/v3/site` responds through the proxied hostname

Useful checks:

```bash
curl -I http://forum.nu31.space
curl -sS http://forum.nu31.space/api/v3/site
```

## Why This Works Better Than `localhost`

The restored database still contains the original site identity and URLs, for example:

- `https://forum.nu31.space/`
- `https://forum.nu31.space/post/...`
- `https://forum.nu31.space/pictrs/...`

Because of that:

- a direct localhost API restore can succeed
- but the browser UI can still behave incorrectly on `localhost`

Using the original hostname locally avoids that mismatch.

## Cleanup

When the test is finished:

1. Stop the local restore stack:

```bash
docker compose down
```

2. Stop the local reverse proxy.

3. Remove the `forum.nu31.space` line from `/etc/hosts`.

## Result

If this test succeeds, you have validated more than just raw restore:

- the backup can be restored
- the restored data is usable
- the browser UI works under the original site hostname
- the test is close to a real disaster-recovery scenario
