#!/usr/bin/env bash
# Checks tools and that required env vars are SET (values are never printed).
set -u
fail=0
for t in node npm tofu aws gh; do command -v "$t" >/dev/null || { echo "missing tool: $t"; fail=1; }; done
for v in CLOUDFLARE_API_TOKEN AIVEN_TOKEN RENDER_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_STATE_PASSPHRASE \
         TF_VAR_cloudflare_account_id TF_VAR_aiven_project TF_VAR_render_owner_id TF_VAR_demo_password; do
  [ -n "${!v:-}" ] || { echo "unset: $v"; fail=1; }
done
[ "$fail" = 0 ] && echo "preflight OK" || exit 1
