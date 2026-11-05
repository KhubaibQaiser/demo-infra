# demo-infra

IaC for free demo sites on `khubaibqaiser.com`. `sites.json` is the single source of truth.

| Layer | Tool | Where |
|---|---|---|
| DNS CNAMEs (Route 53) | AWS CDK | `cdk/` |
| Pages project + domain, Aiven MySQL, Render API service | OpenTofu | `tofu/` |
| Keep-alive poller (Cloudflare Worker cron) | wrangler | `keepalive/` |

CI: PR runs checks and a read-only plan; merge to `main` applies (tofu, cdk, wrangler) and smoke-tests.
Specs: `docs/specs/`. Zone ownership: `docs/adr/0001-zone-ownership.md`.

## Local checks (no cloud credentials)
```bash
npm ci
npm run check          # typecheck, unit tests, sites.json validation, cdk synth
npm run gen:wrangler   # writes keepalive/wrangler.generated.jsonc
tofu -chdir=tofu init -backend=false && tofu -chdir=tofu validate
```

## Add a site
1. Add an entry to `sites.json` (omit `backend` for a static page; set `backend.keepalive` deliberately).
2. Open a PR and review the checks and plan.
3. Merge. CI applies and runs the smoke test.

## Teardown
`aiven_mysql` has `prevent_destroy`. To remove a site: delete its entry, remove `prevent_destroy` in a separate PR first.

## Demo data
The Laravel seeders need Google geocoding, so the demo database is loaded from a scrubbed copy of a local database instead
(`data/demo.sql.gz`, gitignored; scrub rules in `scripts/scrub-demo-db.sql`; load with `scripts/import-demo-db.sh <site>`).
Never commit an unscrubbed dump.
