#!/bin/sh
set -eu

. /etc/default/lemmy-backup

: "${APP_DIR:?APP_DIR is required}"
: "${BACKUP_ROOT:?BACKUP_ROOT is required}"
: "${RETENTION_DAYS:?RETENTION_DAYS is required}"

export APP_DIR BACKUP_ROOT RETENTION_DAYS

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
TIMESTAMP="$(date -u +%Y-%m-%d_%H-%M-%S)"
TMP_DIR="${BACKUP_ROOT}/.incomplete-${TIMESTAMP}-$$"
FINAL_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
LOCK_DIR="${BACKUP_ROOT}/.lock"

cleanup() {
  rm -rf "$TMP_DIR"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another backup is already running" >&2
  exit 1
fi

trap cleanup INT TERM HUP EXIT

mkdir -p "$TMP_DIR"

cd "$APP_DIR"

echo "Creating PostgreSQL dump..."
docker compose exec -T postgres pg_dumpall -c -U lemmy | gzip >"$TMP_DIR/lemmy_db.sql.gz"

echo "Archiving pictrs volume..."
docker run --rm \
  -v lemmy_pictrs_data:/source \
  -v "$TMP_DIR":/backup \
  alpine:3.20 \
  sh -c "tar czf /backup/lemmy_pictrs.tar.gz -C /source ."

echo "Archiving deploy files..."
tar czf "$TMP_DIR/deploy_files.tar.gz" \
  -C "$APP_DIR" \
  docker-compose.yml .env lemmy.generated.hjson

{
  echo "timestamp_utc=${TIMESTAMP}"
  echo "hostname=$(hostname)"
  echo "app_dir=${APP_DIR}"
  echo "retention_days=${RETENTION_DAYS}"
  echo "docker_compose_services=$(docker compose ps --services | tr "\n" " ")"
} >"$TMP_DIR/manifest.txt"

(
  cd "$TMP_DIR"
  sha256sum lemmy_db.sql.gz lemmy_pictrs.tar.gz deploy_files.tar.gz manifest.txt >SHA256SUMS
)

mv "$TMP_DIR" "$FINAL_DIR"
ln -sfn "$FINAL_DIR" "${BACKUP_ROOT}/latest"
TMP_DIR=

echo "Pruning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  ! -name .lock ! -name .incomplete-* ! -name latest \
  -mtime +"$RETENTION_DAYS" -exec rm -rf {} +

rmdir "$LOCK_DIR" 2>/dev/null || true
trap - INT TERM HUP EXIT

echo "Backup completed: $FINAL_DIR"
