#!/usr/bin/env bash
# Proves the R2 state backend locks: a second tofu run must fail while the first holds the lock.
# env: CLOUDFLARE_ACCOUNT_ID, AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (the R2 key pair). Nothing is printed from them.
set -uo pipefail
: "${CLOUDFLARE_ACCOUNT_ID:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}"
cd "$(dirname "$0")/../tofu-lock-test"
printf 'endpoints = { s3 = "https://%s.r2.cloudflarestorage.com" }\n' "$CLOUDFLARE_ACCOUNT_ID" > backend.hcl
trap 'rm -f backend.hcl' EXIT
tofu init -input=false -backend-config=backend.hcl >/dev/null || { echo "FAIL: cannot init against R2 (bucket/keys/endpoint?)"; exit 2; }

tofu apply -auto-approve -input=false -lock-timeout=0 >/tmp/lock-a.log 2>&1 &
holder=$!
sleep 15
out=$(tofu plan -input=false -lock-timeout=0 2>&1); rc=$?
wait "$holder"; holder_rc=$?

if [ "$rc" -ne 0 ] && grep -qi "lock" <<<"$out"; then
  echo "PASS: second run was refused while the first held the lock (holder exit $holder_rc)"
  tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
else
  echo "FAIL: second run was NOT blocked (exit $rc). R2 locking is not reliable: switch the backend to S3."
  exit 1
fi
