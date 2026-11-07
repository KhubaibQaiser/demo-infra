#!/usr/bin/env bash
# One-shot seed for a site's demo database: prompts for the secrets (nothing is echoed or stored), loads data/demo.sql.gz,
# then redeploys the Render service so `demo:set-password` runs against the imported users.
#   usage: scripts/seed-lumen.sh [site-name]     needs: docker, jq, tofu, curl, data/demo.sql.gz
set -euo pipefail
cd "$(dirname "$0")/.."
site="${1:-lumen}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-2111342ca0f6b71a27e691aaa3ef8c68}"

ask() { local v; read -rsp "$1: " v; echo >&2; printf '%s' "$v"; }
export AWS_ACCESS_KEY_ID;      AWS_ACCESS_KEY_ID="$(ask 'R2 access key id')"
export AWS_SECRET_ACCESS_KEY;  AWS_SECRET_ACCESS_KEY="$(ask 'R2 secret access key')"
export TF_STATE_PASSPHRASE;    TF_STATE_PASSPHRASE="$(ask 'State passphrase (TF_STATE_PASSPHRASE)')"
render_key="$(ask 'Render API key')"

. scripts/tf-env.sh
printf 'endpoints = { s3 = "https://%s.r2.cloudflarestorage.com" }\n' "$CLOUDFLARE_ACCOUNT_ID" > tofu/backend.hcl
trap 'rm -f tofu/backend.hcl' EXIT
tofu -chdir=tofu init -input=false -backend-config=backend.hcl >/dev/null

# The dump drops and recreates every table, so it may overwrite the schema Render's first boot migrated.
FORCE=1 scripts/import-demo-db.sh "$site"

name="$(jq -r --arg s "$site" '.sites[] | select(.name==$s) | .backend.renderService' sites.json)"
id="$(curl -fsS -H "Authorization: Bearer $render_key" "https://api.render.com/v1/services?name=$name&limit=1" | jq -r '.[0].service.id // empty')"
if [ -n "$id" ] && curl -fsS -o /dev/null -X POST -H "Authorization: Bearer $render_key" "https://api.render.com/v1/services/$id/deploys"; then
  echo "Render redeploy started for $name; give it ~3 minutes, then log in."
else
  echo "Could not start the Render redeploy: in Render open $name > Manual Deploy > Deploy latest commit."
fi
