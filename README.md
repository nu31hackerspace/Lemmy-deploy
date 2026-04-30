# Lemmy Deploy

Deploys a Lemmy instance to a single VM with `docker compose`.

This repo is built for the current `nu31forum` setup:

- Lemmy runs on its own VM
- deployment happens through GitHub Actions
- external routing and TLS are handled by a separate `infra` project with Caddy
- no local `nginx` is used in this repo

## Services

The stack includes:

- `postgres`
- `pictrs`
- `lemmy`
- `lemmy-ui`

Current versions:

- `dessalines/lemmy:0.19.18`
- `dessalines/lemmy-ui:0.19.18`

## Repository Files

- [docker-compose.yml](./docker-compose.yml): runtime stack for the forum VM
- [lemmy.hjson.template](./lemmy.hjson.template): template for the Lemmy backend config
- [render-lemmy-config.sh](./render-lemmy-config.sh): renders `lemmy.generated.hjson` from environment variables
- [BACKUP.md](./BACKUP.md): backup and restore instructions
- [ops/backup](./ops/backup): tested backup automation files for the VM

## Deployment Model

GitHub Actions deploys to the VM over SSH.

The workflow:

1. builds `.env` from GitHub secrets
2. renders `lemmy.generated.hjson`
3. ensures Docker and Compose are installed on the target VM
4. uploads deploy files to `/opt/lemmy`
5. runs `docker compose pull`
6. runs `docker compose up -d --remove-orphans`

The workflow file is [publish.yml](./.github/workflows/publish.yml).

## Required GitHub Secrets

The deploy workflow expects these repository secrets:

- `HOST`
- `FORUM_SSH_PRIVATE_KEY`
- `LEMMY_HOSTNAME`
- `POSTGRES_PASSWORD`
- `PICTRS_API_KEY`
- `LEMMY_ADMIN_USERNAME`
- `LEMMY_ADMIN_PASSWORD`
- `LEMMY_ADMIN_EMAIL`

Expected values for the current production setup:

- `HOST`: the public SSH host of the forum VM
- `LEMMY_HOSTNAME`: the public forum domain, for example `forum.nu31.space`
- `FORUM_SSH_PRIVATE_KEY`: private SSH key used by GitHub Actions to access the VM

## Remote Host Assumptions

The current workflow assumes:

- SSH port `2222`
- SSH user `root`
- deploy path `/opt/lemmy`

Those values are defined in [publish.yml](./.github/workflows/publish.yml).

## Local Usage

To render the Lemmy config locally:

```bash
export POSTGRES_PASSWORD=...
export PICTRS_API_KEY=...
export LEMMY_ADMIN_USERNAME=...
export LEMMY_ADMIN_PASSWORD=...
export LEMMY_ADMIN_EMAIL=...
export LEMMY_HOSTNAME=forum.example.com
sh ./render-lemmy-config.sh
```

To start the stack locally:

```bash
docker compose up -d
```

To stop it:

```bash
docker compose down
```

## Reverse Proxy

This repo does not manage the public reverse proxy.

The VM exposes:

- `8536` for Lemmy backend
- `1234` for Lemmy UI

Your external proxy must route:

- `/api/*`
- `/pictrs/*`
- `/feeds/*`
- `/nodeinfo/*`
- `/.well-known/*`
- ActivityPub `Accept` requests
- `POST` requests

to the backend service, and route normal web traffic to `lemmy-ui`.

## Backups

See [BACKUP.md](./BACKUP.md).

At minimum, back up:

- PostgreSQL data
- `pictrs` media data

## Notes

- `pictrs` storage can grow quickly, so monitor media volume size.
- This repo is intentionally Compose-based, not Swarm-based.
- If you change deploy secrets, make sure the rendered config and remote `.env` stay in sync.
