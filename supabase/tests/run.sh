#!/usr/bin/env bash
# Runs the row level security tests against a scratch database on a local PostgreSQL (15 or newer).
# Uses the usual libpq settings (PGHOST, PGPORT, PGUSER); the user must be a superuser.
#   PGHOST=/path/to/socket PGPORT=5432 PGUSER=postgres ./supabase/tests/run.sh
# Or let it start (and afterwards stop) a throwaway PostgreSQL server of its own:
#   ./supabase/tests/run.sh --temp-cluster        (needs the PostgreSQL server package, e.g. apt-get install postgresql)
# Creates the database ridgeline_rls_test, loads a stub of Supabase's auth/storage schemas, runs the migration,
# runs the checks, prints PASS/FAIL per check and drops the database again. Exit code 0 = all passed.
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
here="$(cd "$(dirname "$0")" && pwd)"
db="${RLS_TEST_DB:-ridgeline_rls_test}"

if [ "${1:-}" = "--temp-cluster" ]; then
  bindir="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
  [ -x "$bindir/initdb" ] || bindir="$(dirname "$(command -v initdb)")"
  tmp="$(mktemp -d)"; chmod 755 "$tmp"
  as=""; if [ "$(id -u)" = 0 ]; then chown postgres "$tmp"; as="su postgres -c"; fi
  run() { if [ -n "$as" ]; then $as "$*"; else sh -c "$*"; fi; }
  run "$bindir/initdb -D $tmp/data -A trust -U postgres >/dev/null"
  run "$bindir/pg_ctl -D $tmp/data -o '-p 54329 -k $tmp -c listen_addresses=' -l $tmp/log -w start >/dev/null"
  stop_cluster() { run "$bindir/pg_ctl -D $tmp/data -m fast stop >/dev/null" || true; rm -rf "$tmp"; }
  export PGHOST="$tmp" PGPORT=54329 PGUSER=postgres
else
  stop_cluster() { :; }
fi

psql -X -q -d postgres -c "drop database if exists $db" >/dev/null
psql -X -q -d postgres -c "create database $db" >/dev/null
trap 'psql -X -q -d postgres -c "drop database if exists $db" >/dev/null 2>&1 || true; stop_cluster' EXIT

psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$here/supabase_stub.sql" >/dev/null
echo "Loading migration..."
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$here/../migrations/0001_team_sync.sql" >/dev/null
echo "Running the migration a second time (it must be re-runnable)..."
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$here/../migrations/0001_team_sync.sql" >/dev/null

out="$(psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$here/rls_test.sql" 2>&1)" || { echo "$out"; echo "TEST SCRIPT ERROR"; exit 2; }
echo "$out" | grep -E '^(PASS|FAIL|---|SUMMARY)' || true
if echo "$out" | grep -q '^FAIL'; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
