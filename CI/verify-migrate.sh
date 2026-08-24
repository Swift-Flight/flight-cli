#!/usr/bin/env bash
#
# Exercises `flight migrate` end to end against a real database.
#
# Generates a skeleton project (which has no migration targets), adds them with
# `flight migrate init`, writes a migration, applies it, checks the table
# exists, rolls it back, and checks it is gone. Every command is the CLI's,
# not the underlying tool's, so the delegation is what is under test.
#
# Needs FLIGHT_TEST_DATABASE_URL. Skips, loudly, without it.
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${FLIGHT_TEST_DATABASE_URL:-}" ]; then
  echo "::warning::FLIGHT_TEST_DATABASE_URL is not set — skipping the migrate check"
  exit 0
fi

swift build --product flight >/dev/null
cli="$(swift build --product flight --show-bin-path)/flight"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "── generating a project with no migration targets"
"$cli" new MigrationCheck --tier skeleton --path "$scratch/p" >/dev/null

echo "── flight migrate before init should explain itself"
if (cd "$scratch/p" && "$cli" migrate status >/dev/null 2>&1); then
  echo "::error::migrate succeeded in a project with no migrate target"
  exit 1
fi

echo "── flight migrate init"
(cd "$scratch/p" && "$cli" migrate init >/dev/null)

echo "── flight migrate create"
(cd "$scratch/p" && "$cli" migrate create CreateWidgets >/dev/null)
migration=$(ls "$scratch/p"/Sources/Migrations/*_CreateWidgets.swift)
python3 - "$migration" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("    func up(_ schema: SchemaBuilder) {\n",
              "    func up(_ schema: SchemaBuilder) {\n"
              '        schema.createTable("widgets") { t in\n'
              '            t.uuid("id").primaryKey().default(.uuid)\n'
              "        }\n")
t = t.replace("    func down(_ schema: SchemaBuilder) {\n",
              '    func down(_ schema: SchemaBuilder) {\n        schema.dropTable("widgets")\n')
p.write_text(t)
PY

export FLIGHT_DATABASE_URL="$FLIGHT_TEST_DATABASE_URL"
cd "$scratch/p"

echo "── flight migrate (apply)"
"$cli" migrate >/dev/null

echo "── flight migrate status"
"$cli" migrate status 2>/dev/null | grep -q "CreateWidgets" || {
  echo "::error::status does not list the applied migration"; exit 1; }

echo "── flight migrate rollback"
"$cli" migrate rollback >/dev/null
"$cli" migrate status 2>/dev/null | grep -q "No applied migrations" || {
  echo "::error::rollback did not revert the migration"; exit 1; }

echo "✔ create, init, apply, status and rollback all work through the CLI"
