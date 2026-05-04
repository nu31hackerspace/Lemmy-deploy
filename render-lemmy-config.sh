#!/bin/sh
set -eu

: "${TEMPLATE_PATH:=./lemmy.hjson.template}"
: "${OUTPUT_PATH:=./lemmy.generated.hjson}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${PICTRS_API_KEY:?PICTRS_API_KEY is required}"
: "${LEMMY_ADMIN_USERNAME:?LEMMY_ADMIN_USERNAME is required}"
: "${LEMMY_ADMIN_PASSWORD:?LEMMY_ADMIN_PASSWORD is required}"
: "${LEMMY_ADMIN_EMAIL:?LEMMY_ADMIN_EMAIL is required}"
: "${LEMMY_HOSTNAME:?LEMMY_HOSTNAME is required}"
: "${LEMMY_SMTP_SERVER:?LEMMY_SMTP_SERVER is required}"
: "${LEMMY_SMTP_LOGIN:?LEMMY_SMTP_LOGIN is required}"
: "${LEMMY_SMTP_PASSWORD:?LEMMY_SMTP_PASSWORD is required}"
: "${LEMMY_SMTP_FROM:?LEMMY_SMTP_FROM is required}"
: "${LEMMY_SMTP_TLS:?LEMMY_SMTP_TLS is required}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"
perl -pe 's/\$\{(\w+)\}/exists $ENV{$1} ? $ENV{$1} : $&/ge' "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"
