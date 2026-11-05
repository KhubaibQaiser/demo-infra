# Lumen demo hosting — overview

Goal: host the Lumen demo (React frontend + Laravel API) for free at
`https://lumen.khubaibqaiser.com`, with a repeatable pattern for more demo sites
(e.g. `stray.khubaibqaiser.com`). Demo only, not production. Email/password login only.

## Decisions (final, from the interview)

| # | Decision | Choice |
|---|---|---|
| D1 | Apex domain | `khubaibqaiser.com` |
| D2 | Hostnames | frontend `lumen.khubaibqaiser.com`; API `lumen-api.khubaibqaiser.com` (pattern `<name>-api` for future backends) |
| D3 | OpenTofu state | Cloudflare R2 via the S3 backend, **gated** by a lock test (Task 0); fallback = S3 + OIDC. Client-side state encryption in both cases |
| D4 | DNS tooling | CDK (matches portfolio-v2). Zone stays owned by `portfolio-v2`; referenced by zone ID |
| D5 | Zone extraction into a shared repo | **Deferred.** Not needed for the demo, risky for the live portfolio. Written up as ADR 0001 in `demo-infra`; revisit as its own migration |
| D6 | CI/CD | PR = plan/diff only; merge to `main` = auto apply (`cdk deploy`, `tofu apply`, `wrangler deploy`) then smoke test. No reviewer gate |
| D8 | Keep-alive implementation | Cloudflare Worker cron driven by `sites.json`. A Vercel/Supabase dashboard was considered and rejected: Vercel Hobby cron is once per day, and a DB-held target list would split the source of truth away from PR review |
| D7 | Render hours | Workspace has other free services → keep-alive is **opt-in per backend**, with an optional active-hours window, and a budget check in the generator |

## Architecture

```
Browser ──► lumen.khubaibqaiser.com
              │  Route 53 CNAME (CDK)
              ▼
        Cloudflare Pages  (static Lumen build; project + domain via OpenTofu)
              │  XHR with Bearer token + CORS   (cross-origin, no proxy)
              ▼
        https://lumen-api.khubaibqaiser.com
              │  Route 53 CNAME (CDK) → <renderService>.onrender.com
              ▼
        Render free web service  (Docker, Laravel; managed by OpenTofu, custom domain)
              │  MySQL over TLS
              ▼
        Aiven free MySQL  (OpenTofu)

Cloudflare Worker (cron, wrangler) ── pings the API health URL every N min (opt-in) to prevent spin-down
```

The API custom domain makes the Lumen build independent of Render's auto-generated `onrender.com` name
(which gets a suffix on collision). Only the CNAME *target* depends on it.

## Repos and what lands where

| Repo | Role | Spec |
|---|---|---|
| `stag-works` (`KhubaibQaiser/stagworks-backend`) | Laravel API: Render image, entrypoint, env-driven CORS (the service itself is OpenTofu-managed) | [01-stag-works.md](01-stag-works.md) |
| `custom-crm` / Lumen (local folder `stagworks-react`) | Frontend: env + build verification only | [02-custom-crm-lumen.md](02-custom-crm-lumen.md) |
| `demo-infra` (new) | All glue IaC: `sites.json`, CDK DNS, OpenTofu, keep-alive Worker, scripts | [03-demo-infra.md](03-demo-infra.md) |
| `portfolio-v2` | **No changes.** Owns the Route 53 zone; referenced by zone ID | — |

Manual steps and inputs needed from you: [04-manual-steps-and-inputs.md](04-manual-steps-and-inputs.md).

## What I found in the code that shaped this plan (corrections included)

1. **Auth is a Bearer token, not cookie auth.** `POST /auth/login` returns `token`; Lumen stores it in a
   cookie and sends `Authorization: Bearer …` (`api-client.ts`, `credential-api.ts`).
   **I previously said login would break cross-site and proposed a Cloudflare proxy. That was wrong
   for this codebase; the proxy is dropped.** CORS (`supports_credentials: true`) is enough, and the
   backend already supports a cross-site SPA (`EnsureFrontendRequestsAreStateful`).
2. Backend CORS already allows `*.pages.dev` (demo commit `a6b9347`) but **not** a custom domain →
   make allowed origins env-driven.
3. `docker/8.2-nginx/Dockerfile` is only a *runtime base* (no app code). `docker/fargate/Dockerfile`
   needs a private AWS ECR image. → A new self-contained `docker/render/Dockerfile` is required.
4. `demo:set-password` refuses to run when `APP_ENV=production` → Render runs with `APP_ENV=staging`.
5. There are **no** `sessions`/`cache`/`jobs` migrations. I earlier suggested `database` drivers; that
   would need new migrations. Instead use `SESSION_DRIVER=file`, `CACHE_DRIVER=file` (this app reads
   `CACHE_DRIVER`, not `CACHE_STORE`), `QUEUE_CONNECTION=sync`. Fine because auth is Bearer.
6. `TrustProxies` already has `$proxies = '*'` — no change needed behind Render.
7. Health endpoints exist: `/api/health/live`, `/api/health/simple`.
8. Frontend endpoints are `/api/v1/...` and `/auth/login` → `VITE_API_URL` is the **host root**
   (`https://<service>.onrender.com`), no `/api` suffix.
9. Local tooling: OpenTofu 1.12.5 ✔, aws cli ✔, docker ✔, gh (logged in as KhubaibQaiser) ✔.
   Missing: terraform (use OpenTofu), cdk and wrangler (use devDependencies / `npx`), php and composer
   (run PHP inside Docker).

## Single source of truth: `demo-infra/sites.json`

One entry per demo site drives CDK (DNS), OpenTofu (Pages + domains), the keep-alive Worker and the
smoke tests. Adding a site = add an entry + apply. Schema in [03-demo-infra.md](03-demo-infra.md).

## Rollout order

0. You: one-time bootstrap (spec 04 §B): accounts, R2 bucket, GitHub secrets, OIDC role (`DemoCiStack`).
1. Scaffold `demo-infra` (specs 03) → validate offline (cdk test/synth, `tofu validate`); run the R2 lock test.
2. Backend branch + image (spec 01) → build and boot locally against a MySQL container.
3. Frontend verification (spec 02).
4. You: create accounts/tokens (spec 04). Then `tofu apply` (Aiven + Pages).
5. `tofu apply` creates the Render service → backend live → first boot migrates/seeds.
6. Fill/verify Render URL in `sites.json`, apply Pages env, `cdk deploy` CNAME, deploy Worker.
7. `scripts/smoke.sh`.

## Cost

All free-tier except Route 53 queries (cents/yr; the hosted zone is already paid by the portfolio).
Render free: 750 instance hours/workspace/month; with keep-alive one service uses ~744 h.

## Verified since the last draft (Render docs read)

- Custom domains are listed as supported on **free** web services (render.com/docs/free).
- Custom domains are attached through the provider (`custom_domains`); TLS is automatic.
- `render-oss/render` provider exists (v1.9.x) with `render_web_service`: resolves the Render decision gate, so no `render.yaml`.
- Render adds a `www.` redirect for root domains; irrelevant to subdomains.
- If the zone has CAA records, they must allow `letsencrypt.org` and `pki.goog`. Check before deploy.

## Unverified items (verify at implementation, do not assume)

- R2 as an OpenTofu S3-backend with `use_lockfile` (conditional writes): blogs report it works but locking is
  "best-effort"; no official statement found. Gated by Task 0 lock test.
- Whether R2 requires a payment method on file to enable (check at account setup).
- Cloudflare provider major version (v4 vs v5 `pages_project` schema).
- Aiven free plan string, region behaviour, and user/database resources in the Aiven provider.
- Whether Render has a usable Terraform provider for free Docker web services (decision gate in spec 03).
- That the Render API accepts `plan = "free"` for a Docker service via the provider; and the service URL (name collision adds a suffix).
- Aiven free plan string `free-1-1gb` and whether a region can be chosen.
- Cloudflare Workers Free: cron trigger limits (docs: 5/account) and Pages build limits.
- Seed duration on a fresh DB (migrate + seed) vs Render start-up timeout.

## Best practices applied

- No secrets in git; `sync: false` / sensitive tofu vars / env-only tokens; `.gitignore` for state,
  `.terraform`, `cdk.out`, `.dev.vars`.
- Pinned provider and tool versions; `tofu fmt -check` + `validate`; CDK unit tests + `cdk diff` before deploy.
- Least-privilege API tokens; `prevent_destroy` on the database; stack termination protection.
- Worker has no public endpoint (`workers_dev = false`).
- CI: PR workflow has no write credentials; deploy workflow uses GitHub OIDC for AWS, `environment: production`,
  a concurrency group (one apply at a time), and `prevent_destroy` on databases.
- State is remote, locked, and encrypted client-side (OpenTofu `encryption` block); the passphrase is a GitHub secret.
