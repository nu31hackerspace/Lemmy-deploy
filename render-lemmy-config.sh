#!/bin/sh
set -eu

export POSTGRES_PASSWORD="$(cat /run/secrets/POSTGRES_PASSWORD)"
export PICTRS_API_KEY="$(cat /run/secrets/PICTRS_API_KEY)"
export LEMMY_ADMIN_USERNAME="$(cat /run/secrets/LEMMY_ADMIN_USERNAME)"
export LEMMY_ADMIN_PASSWORD="$(cat /run/secrets/LEMMY_ADMIN_PASSWORD)"
export LEMMY_ADMIN_EMAIL="$(cat /run/secrets/LEMMY_ADMIN_EMAIL)"

: "${LEMMY_HOSTNAME:?LEMMY_HOSTNAME is required}"

envsubst < /config/lemmy.hjson.template > /config/lemmy.hjson