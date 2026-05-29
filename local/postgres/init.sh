#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    CREATE DATABASE ngo_db;
    CREATE DATABASE donation_db;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname ngo_db -f /sql/ngo-init.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname donation_db -f /sql/donation-init.sql

echo "[postgres-init] ngo_db e donation_db criados e populados."
