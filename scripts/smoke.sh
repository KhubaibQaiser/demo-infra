#!/usr/bin/env bash
# smoke.sh <site-name>  - env: DEMO_EMAIL, DEMO_PASSWORD (never printed). Retries cover DNS/cert propagation.
set -euo pipefail
site="${1:?usage: smoke.sh <site-name>}"
cd "$(dirname "$0")/.."
read -r FRONT API HEALTH < <(node -e '
  const c=require("./sites.json"); const s=c.sites.find(x=>x.name===process.argv[1]);
  if(!s||!s.backend){console.error("no such site with backend");process.exit(2)}
  console.log(`https://${s.subdomain}.${c.apex} https://${s.backend.subdomain}.${c.apex} ${s.backend.healthPath}`)' "$site")

retry() { for i in $(seq 1 "${TRIES:-30}"); do "$@" && return 0; sleep "${DELAY:-10}"; done; return 1; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$@"; }

echo "1/4 API health";      retry bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 $API$HEALTH)\" = 200 ]"
echo "2/4 frontend";        retry bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 $FRONT)\" = 200 ]"
echo "3/4 CORS preflight"
hdrs=$(curl -s -D - -o /dev/null -X OPTIONS "$API/auth/login" -H "Origin: $FRONT" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization")
echo "$hdrs" | grep -qi "^access-control-allow-origin: $FRONT\r\?$" || { echo "CORS: ACAO != $FRONT"; exit 1; }
echo "$hdrs" | grep -qi "^access-control-allow-credentials: true" || { echo "CORS: credentials header missing"; exit 1; }
echo "4/4 login"
: "${DEMO_EMAIL:?}" "${DEMO_PASSWORD:?}"
body=$(jq -n --arg e "$DEMO_EMAIL" --arg p "$DEMO_PASSWORD" '{email:$e,password:$p}')
curl -s --max-time 60 -X POST "$API/auth/login" -H 'content-type: application/json' -H "Origin: $FRONT" -d "$body" | jq -e '.token | length > 10' >/dev/null \
  || { echo "login failed"; exit 1; }
echo "smoke OK: $site"
