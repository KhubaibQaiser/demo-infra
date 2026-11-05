# Spec: `demo-infra` (new repo)

Shared IaC for all demo sites. Create as `KhubaibQaiser/demo-infra` (private), local
`/Users/khubaib-work/Documents/PowerfulWeb/demo-infra`. Nothing here contains secrets.

## Layout

```
demo-infra/
  sites.json                 # single source of truth
  README.md                  # how to add a site, deploy order, teardown
  .gitignore                 # *.tfstate*, .terraform/, *.tfvars, cdk.out/, node_modules/, .dev.vars
  .github/workflows/plan.yml       # PR: validate, cdk synth/diff, tofu plan, wrangler dry-run (no write creds)
  .github/workflows/deploy.yml     # push to main: OIDC, cdk deploy, tofu apply, wrangler deploy, smoke
  docs/adr/0001-zone-ownership.md  # zone stays in portfolio-v2; extraction deferred
  cdk/                       # Route 53 CNAMEs + DemoCiStack (GitHub OIDC role)
  tofu/                      # OpenTofu: Cloudflare Pages + domains, Aiven MySQL
  keepalive/                 # Cloudflare Worker (scheduled) + config generator + tests
  scripts/                   # preflight.sh, tf-env.sh, smoke.sh
  docs/specs/
```

## `sites.json`

```json
{
  "apex": "khubaibqaiser.com",
  "zone": { "id": "<Route53 hosted zone id>" },
  "sites": [
    {
      "name": "lumen",
      "subdomain": "lumen",
      "pages": {
        "project": "lumen-demo",
        "repo": "KhubaibQaiser/custom-crm",
        "branch": "main",
        "buildCommand": "npm run build",
        "outputDir": "build",
        "env": { "NODE_VERSION": "22", "HUSKY": "0", "VITE_ENV": "demo" }
      },
      "backend": {
        "subdomain": "lumen-api",
        "renderService": "lumen-demo-api-kq",
        "healthPath": "/api/health/live",
        "keepalive": true
      }
    }
  ],
  "keepalive": { "intervalMinutes": 10, "activeHoursUtc": "0-23" }
}
```

- `pages.project` is the `<project>.pages.dev` name, which is global and independent of the public hostname
  (`lumen.khubaibqaiser.com`). Verify availability at apply time; add a suffix if taken.
- `backend` is optional (a static landing page like Stray omits it → no API record, no keep-alive, no Aiven).
- Derived values: Pages CNAME target `<pages.project>.pages.dev`; API CNAME target
  `<renderService>.onrender.com` (verify the real name after first sync; Render may add a suffix); API URL
  `https://<backend.subdomain>.<apex>`; frontend URL `https://<subdomain>.<apex>`.
- `backend.keepalive` is opt-in (default `false`). The generator **fails** if more than one
  keepalive-enabled backend would exceed the Render 750 h/workspace budget, using
  `targets × hours/day × 31`, with the workspace's other free services assumed to need ~0 h (you said
  others exist, so set `activeHoursUtc` to a window, e.g. `"6-20"` ≈ 14 h/day ≈ 434 h, to leave headroom).
- A JSON-schema file validates it; CDK, tofu (`jsondecode(file())`) and the Worker generator all read it.

## Component: `cdk/` — DNS

- `DemoDnsStack` (one stack for all sites), env `{account, region: "us-east-1"}` (matches `Portfolio-Dns`).
- `HostedZone.fromHostedZoneAttributes({ hostedZoneId: zone.id, zoneName: apex })` — **no CloudFormation
  export/import** with the portfolio stacks (consistent with portfolio ADR 0001).
- For each site: `CnameRecord` (`recordName=subdomain`, `domainName=<project>.pages.dev`, TTL 5 min), plus,
  if `backend` exists, a second `CnameRecord` (`recordName=backend.subdomain`, `domainName=<renderService>.onrender.com`).
- Synth-time validation: DNS-label regex, unique subdomains across frontends **and** APIs, no collision with `www`/apex.
- `terminationProtection: true`; tags `project=demo-infra`, `managed-by=cdk`.
- Tests (jest): records created per site (and per backend); invalid/duplicate subdomain throws; static site without backend gets only one record.
- `DemoCiStack` (second stack): reuses the existing GitHub OIDC provider via `githubOidcProviderArn` (same as
  portfolio `OidcStack`), role trusted to `repo:KhubaibQaiser/demo-infra:ref:refs/heads/main` and
  `environment:production`, allowed to assume the `cdk-*` bootstrap roles only. Bootstrapped once, locally.
- Known trade-off: CDK deploys through the bootstrap CloudFormation execution role, which is broad
  (typically AdministratorAccess). Mitigated by the narrow trust policy (main + environment) and
  required PR review via branch protection. Revisit only if the account hosts more than low-value workloads.
- Deploy: CI (`deploy.yml`); local `npx cdk diff` for previews.

## Component: `tofu/` — Cloudflare Pages + Aiven (OpenTofu 1.12.5, already installed)

- `versions.tf`: pin `required_version` and providers with `~>` (cloudflare, aiven, random). **Task 0:**
  check the Cloudflare provider v4 vs v5 `pages_project` / `pages_domain` schema and pick one; check the
  Aiven provider for the free plan string, the `aiven_mysql` user/database resources, and region rules.
- `sites.tf`: `locals { cfg = jsondecode(file("../sites.json")) }`, `for_each` over sites.
- Per site: `cloudflare_pages_project` (GitHub source, build config from `sites.json`, production env vars incl.
  `VITE_API_URL`) and `cloudflare_pages_domain` (`<subdomain>.<apex>`).
- Per site with a backend: `aiven_mysql` (free plan; `lifecycle { prevent_destroy = true }`), database, user;
  `random_bytes` → `APP_KEY` (`base64:` + 32 bytes). The Aiven CA cert is output for `DB_SSL_CA_PEM`.
- `outputs.tf`: DB host/port/name/user/password/CA and `app_key` — all `sensitive = true`.
- Provider auth from env only: `CLOUDFLARE_API_TOKEN`, `AIVEN_TOKEN`; non-secret `TF_VAR_cloudflare_account_id`,
  `TF_VAR_aiven_project`.
- **State (D3):** `backend "s3"` pointed at an R2 bucket (`demo-infra-tfstate`): `region="auto"`,
  `use_path_style=true`, `endpoints.s3="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"`, `use_lockfile=true`,
  `skip_s3_checksum=true`, `skip_credentials_validation`, `skip_region_validation`,
  `skip_requesting_account_id`, `skip_metadata_api_check`. R2 keys come from env
  (`AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY`), never committed. State is encrypted client-side with OpenTofu's
  `encryption` block (passphrase from `TF_ENCRYPTION` env / GitHub secret), because it holds DB credentials.
  - **Task 0 (gate): lock test.** Two simultaneous `tofu plan -lock-timeout=0` against the bucket; the
    second must fail with a lock error. Also check R2 account enablement needs (card on file?).
    If the test fails or R2 is not free-usable → switch the backend block to S3 (OIDC role, no stored keys)
    and add the bucket to `DemoCiStack`. Everything else is unchanged.
  - Regardless of lock quality: CI `concurrency: group: demo-infra-apply, cancel-in-progress: false`.
  - The R2 bucket is created once manually (bootstrap), not by the config that stores its state.
- Checks: `tofu fmt -check`, `tofu init -backend=false && tofu validate` (offline); `tofu plan` before every apply.

### Render: decision gate resolved (provider route)

The `render-oss/render` provider (v1.9.x on the OpenTofu registry) has `render_web_service` with Docker
`runtime_source`, `custom_domains`, `env_vars`, `health_check_path` and `plan`. The service is therefore managed in
`tofu/main.tf`, and DB credentials, `APP_KEY` and `DEMO_PASSWORD` flow from Aiven/`random_bytes`/CI secrets straight
into Render env vars. **No `render.yaml`, no Blueprint click, no `render-env.sh`.** Non-secret env lives in
`sites.json` under `backend.env`. Still to confirm at first apply: that the API accepts `plan = "free"`.
Render must be able to read the private backend repo (GitHub app consent, manual).

## Demo data (decision: anonymized copy of the local DB)

The backend seeders need Google geocoding, so Render cannot seed itself (`DEMO_AUTO_SEED=false`). Instead:
- `scripts/scrub-demo-db.sql` documents the scrub applied to a throwaway copy of the Lando database: all users/contacts/team
  members/clients/domains/addresses/phones/brands/competitors/partners replaced with generic values; registrar credentials,
  tokens, audits and emergency contacts removed; real password hashes locked; contract/price/salary amounts perturbed (0.6-1.4x).
- The result is `data/demo.sql.gz` (about 0.5 MB; gitignored, local only). Verified by scanning the dump for staff names/domains
  and for 8,400 original names/emails/titles/addresses: no verbatim leftovers except generic job titles and coincidental
  name overlaps; public magazine/registrar websites remain by design.
- `scripts/import-demo-db.sh <site>` loads it once into the empty Aiven database over TLS (refuses a non-empty DB). Run after the
  first `tofu apply`, before the first successful backend boot, or just redeploy afterwards. The boot-time `demo:set-password` then
  sets the one shared demo password. Login: `khubaib@test.com` (display name "Demo Admin").
- Verified locally: import takes ~6 s; backend boots, `migrate` is a no-op, login works, `/api/v1/clients` and `/api/v1/contacts` return scrubbed data.
- To refresh the data: re-copy Lando into a scratch MySQL, rerun the scrub SQL, re-dump, empty the Aiven DB, import again.

## Component: `keepalive/` — Worker

- Module Worker, TypeScript, `scheduled()` handler only; `workers_dev = false` (no public URL).
- `scripts/gen-wrangler` builds `wrangler.jsonc` from `sites.json`: `TARGETS` = every backend with
  `keepalive: true`, as `https://<backend.subdomain>.<apex><healthPath>`; cron =
  `*/<intervalMinutes> <activeHoursUtc> * * *` (default all hours). Hits the custom domain so it
  also exercises DNS + TLS.
- Rate control: the single knob is `keepalive.intervalMinutes`; the generator rejects values outside
  **5–14** (Render sleeps after 15 min idle; <5 wastes requests) and prints hits/hour per target
  (`60/interval`). This is the "N hits per T" control.
- Handler: `fetch` each target with a 10 s timeout, log `target status ms`; a failure on one target never
  stops the others; no retries (next tick is the retry).
- Tests (vitest): handler hits every target, survives timeouts/errors; generator rejects bad intervals.
- Deploy: CI (`deploy.yml`) runs `npx wrangler deploy` when `sites.json` or `keepalive/**` changes.
- Free-tier limits to confirm: 5 cron triggers/account (docs); Render 750 h/month → keep-alive is only
  safe if this is the only free web service in the Render workspace.

## Component: `scripts/`

- `preflight.sh`: checks tools (tofu, node, docker, aws, gh) and that required env vars are *set*
  (never prints values).
- `tf-env.sh`: builds `TF_ENCRYPTION` from `TF_STATE_PASSPHRASE` (never printed).
- `smoke.sh <site>`: `GET <api>/api/health/live` = 200; CORS preflight from the site origin returns the
  exact ACAO + credentials; `POST /auth/login` with `DEMO_EMAIL`/`DEMO_PASSWORD` from env returns a
  token (token and password never printed); `GET https://<site>` = 200.

## CI/CD (D6)

**`plan.yml` (pull_request):** jest + `cdk synth` + JSON-schema check of `sites.json`; `tofu fmt -check`,
`validate`, `plan` (read-only R2 key; plan output posted without sensitive values); `wrangler deploy --dry-run`.
Fork PRs get no secrets (repo is private; keep it that way).

**`deploy.yml` (push to `main`, `environment: production`, `permissions: id-token: write, contents: read`):**
1. OIDC → assume `DemoCiStack` role (AWS, for CDK).
2. `cdk deploy DemoDns --require-approval never` (diff printed first).
3. `tofu init && tofu apply -auto-approve` (providers authenticated from secrets).
5. `wrangler deploy` only if `sites.json` or `keepalive/**` changed.
6. `scripts/smoke.sh <each site>` with retries (DNS/cert propagation); a failure marks the run red.
Concurrency group `demo-infra-apply` (no cancel). Branch protection: PR + passing `plan.yml` required.
Actions pinned by commit SHA. The app repos get **no** new CI (Render `autoDeploy` and Pages Git integration already deploy them).

Secrets (GitHub, environment `production`): `CLOUDFLARE_API_TOKEN` (Pages + Workers + R2 edit),
`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`, `TF_ENCRYPTION` passphrase, `AIVEN_TOKEN`, `RENDER_API_KEY`
(if used), `DEMO_PASSWORD`. Variables (non-secret): zone id, account ids, AWS role ARN.

## Adding a site (the recipe documented in README)

1. Add an entry to `sites.json` (omit `backend` for static pages; set `backend.keepalive` deliberately).
2. Open a PR → review the plan/diff comments.
3. Merge → CI creates Pages project + domain, Aiven (if backend), both CNAMEs, and refreshes keep-alive.
4. If it has a backend: nothing manual; the Render service is created by `tofu apply`.
5. CI smoke test passes, or run `scripts/smoke.sh <name>` locally.

## Acceptance criteria

1. `cdk test`, `cdk synth`, `tofu validate`, worker tests all pass offline.
2. `cdk diff` shows only the expected CNAME(s) in the zone.
3. `tofu plan` shows Pages project/domain and Aiven service with no secrets in plain output.
4. Adding a dummy second site to `sites.json` changes only DNS/Pages resources (verified in plan/diff), then reverted.
5. `git grep` finds no tokens, passwords or state files in the repo.
6. R2 lock test passes (or the backend is switched to S3 and re-tested).
7. A PR changing only `sites.json` produces a plan/diff and no apply; merging it applies and smoke-passes.
8. `activeHoursUtc` + target count that would exceed 750 h makes the generator fail.
