#!/bin/sh
set -e

cd "$(dirname "$0")"

echo "Dropping database..."
rm -f octobankx.db

echo "Running migrations..."
bundle exec ruby -e "require_relative 'db/database'; OctoBankX.migrate!"

echo "Seeding database..."
bundle exec ruby db/seeds.rb

echo "Done!"
