#!/usr/bin/env bash
# One-time load of the scrubbed demo data into the Aiven database of a site.
#   usage: scripts/import-demo-db.sh <site-name> [dump.sql.gz]
# Needs: docker, jq, and tofu state access (run `. scripts/tf-env.sh` and init tofu first). Secrets are never printed.
# Safe to re-run only on an EMPTY database: it refuses if the target already has tables.
set -euo pipefail
site="${1:?usage: import-demo-db.sh <site-name> [dump.sql.gz]}"
dump="${2:-$(dirname "$0")/../data/demo.sql.gz}"
[ -f "$dump" ] || { echo "missing $dump (build it with scripts/scrub-demo-db.sql, see README)"; exit 1; }

conn="$(tofu -chdir="$(dirname "$0")/../tofu" output -json db_connection | jq -c --arg s "$site" '.[$s]')"
[ "$conn" != "null" ] || { echo "no db_connection for site $site"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -r .ca_cert <<<"$conn" > "$tmp/ca.crt"
host="$(jq -r .host <<<"$conn")"; port="$(jq -r .port <<<"$conn")"
user="$(jq -r .user <<<"$conn")"; db="$(jq -r .database <<<"$conn")"
export MYSQL_PWD; MYSQL_PWD="$(jq -r .password <<<"$conn")"

client() { docker run --rm -i -e MYSQL_PWD -v "$tmp:/tls:ro" mysql:8.0 mysql -h "$host" -P "$port" -u "$user" --ssl-mode=VERIFY_CA --ssl-ca=/tls/ca.crt "$@"; }

tables="$(client -N -e "select count(*) from information_schema.tables where table_schema='$db'" )"
[ "$tables" = "0" ] || { echo "database $db already has $tables tables; refusing to import"; exit 1; }
echo "importing into $host:$port/$db ..."
gzip -dc "$dump" | client "$db"
echo "done: $(client -N -e "select count(*) from users" "$db") users"
