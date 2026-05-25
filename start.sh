#!/bin/sh
set -e

cd "$(dirname "$0")"

PORT="${PORT:-9292}"

echo "Starting OctoBankX on port $PORT..."
bundle exec puma config.ru -p "$PORT"
