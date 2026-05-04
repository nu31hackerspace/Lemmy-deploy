# Local Restore Test Using the Original Hostname

This note explains how to run a local Lemmy restore test under the original hostname instead of `localhost`.

This is useful when:

- the backup has already been restored locally
- API-level checks pass
- but you want a more realistic browser test

The key idea is:

- make your local machine resolve `forum.nu31.space` to `127.0.0.1`
- run a local reverse proxy
- route `forum.nu31.space` traffic to the restored local Lemmy services

## Why This Is Needed

A localhost restore is enough to validate:

- the database backup
- the `pictrs` media backup
- the basic Lemmy startup

But the browser UI can still behave differently on `localhost`.

That happens because the restored instance data still identifies the site as:

```text
forum.nu31.space
```

So for a more realistic browser test, the browser should also access the restored instance through:

```text
forum.nu31.space
```

## High-Level Flow

```text
Browser
  -> forum.nu31.space
  -> /etc/hosts resolves it to 127.0.0.1
  -> local reverse proxy receives the request
  -> reverse proxy sends UI requests to lemmy-ui
  -> reverse proxy sends API/federation/media requests to lemmy
```

## What You Need

- a local restored Lemmy stack
- Docker and `docker compose`
- `/etc/hosts` access
- a local reverse proxy, preferably Caddy

## 1. Keep the Original Hostname in the Restored Config

The restored local copy should keep the real instance hostname.

In `.env`:

```env
LEMMY_HOSTNAME=forum.nu31.space
```

In `lemmy.generated.hjson`:

```hjson
hostname: "forum.nu31.space"
```

If you terminate TLS in the local reverse proxy, you can keep:

```hjson
tls_enabled: false
```

## 2. Publish the Restored Services on Alternate Local Ports

Do not bind the restored instance directly to production-like ports.

Use a compose override file instead.

Example `docker-compose.override.yml`:

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

This gives you:

- backend on `127.0.0.1:18536`
- UI on `127.0.0.1:11234`

## 3. Add the Hostname to `/etc/hosts`

Append this line:

```text
127.0.0.1 forum.nu31.space
```

Example:

```bash
echo '127.0.0.1 forum.nu31.space' | sudo tee -a /etc/hosts
```

After this, your machine will resolve `forum.nu31.space` to your own local machine.

## 4. Run a Local Reverse Proxy

Caddy is a good fit because the production setup already uses Caddy.

Example `Caddyfile`:

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

This matches the Lemmy routing model:

- UI requests go to `lemmy-ui`
- API, federation, and media requests go to `lemmy`

## 5. Open the Restored Instance in the Browser

Open:

```text
http://forum.nu31.space
```

At this point:

- the browser uses the original hostname
- the hostname resolves locally
- the reverse proxy sends requests to the restored stack

## 6. Validate the Restore

Recommended checks:

- the homepage opens
- the admin login works in the browser
- restored posts are visible
- restored comments are visible
- image posts and media load correctly

Useful API checks:

```bash
curl -I http://forum.nu31.space
curl -sS http://forum.nu31.space/api/v3/site
curl -sS 'http://forum.nu31.space/api/v3/post/list?type_=Local&sort=New&limit=10'
curl -sS 'http://forum.nu31.space/api/v3/comment/list?type_=All&limit=10'
```

## Why `/etc/hosts` Alone Is Not Enough

`/etc/hosts` only changes where the hostname points.

It does **not**:

- split UI requests from API requests
- route `/api/*` to the backend
- route `/` to the frontend

That is why a reverse proxy is still needed.

## Cleanup

When the test is finished:

1. Stop the local restore stack:

```bash
docker compose down
```

2. Stop the local reverse proxy.

3. Remove the `forum.nu31.space` entry from `/etc/hosts`.

## Result

This gives you a browser-level restore test that is much closer to production than a plain localhost restore.

It is still local, but from the browser's point of view the restored instance is being opened under its real hostname.
