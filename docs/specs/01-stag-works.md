# Spec: `stag-works` (backend)

Repo: `KhubaibQaiser/stagworks-backend` · local: `/Users/khubaib-work/Documents/PowerfulWeb/stag-works`

## Branching

- Create `demo/render` from the current `demo/local-laptop-tunnel` (docs/DEMO_SETUP.md says demo
  branches must **not** merge to `main`; `config/cors.php` there already allows `*.pages.dev`).
- Commit only the files listed below. Leave `public/demo-s3` (untracked) and `.DS_Store` alone.
- Render deploys branch `demo/render`.

## Changes

### 1. `docker/render/Dockerfile` (new)

Self-contained app image (the existing 8.2-nginx file has no app code; fargate needs a private ECR image).

- `FROM webdevops/php-nginx:8.3-alpine` (pin the tag; consider digest).
- Reuse the PHP ini and `PHP_DISMOD` from `docker/8.2-nginx`.
- `apk add gettext jq`.
- `COPY` composer files → `composer install --no-dev --no-scripts --optimize-autoloader`
  (use `--ignore-platform-req=ext-ffi` only if the base image lacks FFI; `jcupitt/vips` is only
  needed for media helpers, which the demo does not exercise) → `COPY . .` → `chown application`.
- Copy `docker/render/vhost.conf.template` (copy of `docker/fargate/vhost.conf.template`; avoids cross-dir coupling) and `entrypoint.sh`.
- `HEALTHCHECK` → `/api/health/live` on `${APP_PORT}`.
- `ENTRYPOINT ["/usr/local/bin/render-entrypoint.sh"]`, `CMD ["supervisord"]`.
- `.dockerignore` already excludes `.env*`, `tests`, `terraform`, `vendor`; verify `docker/render/**` is not excluded.

### 2. `docker/render/entrypoint.sh` (new)

Order, `set -euo pipefail`:

1. `export APP_PORT="${PORT:-10000}"`; `envsubst '${APP_PORT}'` the vhost template into
   `/opt/docker/etc/nginx/vhost.conf`.
2. If `DB_SSL_CA_PEM` is set: write it to `/tmp/db-ca.pem`, export `MYSQL_ATTR_SSL_CA=/tmp/db-ca.pem`
   (config/database.php already reads this var).
3. `mkdir -p storage/app/demo-s3 && php artisan storage:link --force` (`DEMO_LOCAL_STORAGE=true`).
4. `php artisan migrate --force` — **fail the deploy on error** (unlike start.sh).
5. If `DEMO_AUTO_SEED=true` and the `users` table is empty: `php artisan db:seed --force`.
6. If `DEMO_PASSWORD` is set: `php artisan demo:set-password "$DEMO_PASSWORD"` (idempotent; keeps the
   password aligned with the env var, same as `scripts/demo-up.sh`). Never echo the value.
7. `exec /entrypoint "$@"` (webdevops entrypoint; confirm path in the image).

Risk to measure: seed duration (384 migrations + seeders) vs Render's start-up timeout. If it is too
long, run steps 4–6 in the background after the web server starts and gate `/api/health/ready`.

### 3. Render service: no `render.yaml` in this repo

The Render service (Docker, free plan, health check, custom domain `lumen-api.khubaibqaiser.com`, env vars)
is created by OpenTofu in `demo-infra` (`render_web_service`), built from branch `demo/render` with
`dockerfile_path ./docker/render/Dockerfile`. Env table (non-secret values live in `demo-infra/sites.json`
`backend.env`; secrets are injected by OpenTofu):

| Var | Value / source |
|---|---|
| `APP_ENV` | `staging` (must not be `production`, see `demo:set-password`; `sites.json` validation enforces it) |
| `APP_URL` | `https://lumen-api.khubaibqaiser.com` |
| `FRONTEND_URL`, `CORS_ALLOWED_ORIGINS` | `https://lumen.khubaibqaiser.com` |
| `SANCTUM_STATEFUL_DOMAINS` | `lumen.khubaibqaiser.com` |
| `SESSION_DRIVER` / `CACHE_DRIVER` / `QUEUE_CONNECTION` | `file` / `file` / `sync` |
| `SESSION_SECURE_COOKIE` / `SESSION_SAME_SITE` | `true` / `none` |
| `LOG_CHANNEL`, `TELESCOPE_ENABLED`, `MAIL_MAILER`, `BROADCAST_DRIVER` | `stderr`, `false`, `log`, `log` |
| `DEMO_LOCAL_STORAGE`, `DEMO_AUTO_SEED` | `true`, `true` |
| `APP_KEY`, `DB_HOST/PORT/DATABASE/USERNAME/PASSWORD`, `DB_SSL_CA_PEM`, `DEMO_PASSWORD` | generated/injected by OpenTofu |

CAA: if the zone has CAA records they must allow `letsencrypt.org` and `pki.goog`.
No AWS, Sentry, Gusto, Microsoft, Sparkpost or Google Maps values are set.

### 4. `config/cors.php` (edit) + `tests/Feature/Auth/CorsTest.php` (edit)

- Merge env-driven origins into `allowed_origins`:
  `array_values(array_filter(explode(',', (string) env('CORS_ALLOWED_ORIGINS', ''))))`.
  Keep existing entries and the `*.pages.dev` pattern; keep `supports_credentials => true`; no wildcard.
- Test: with `CORS_ALLOWED_ORIGINS` set (config override), `Access-Control-Allow-Origin` echoes the exact
  origin, `Allow-Credentials: true`, and a non-listed origin gets no ACAO header.
- Run the test inside Docker (no local PHP): `docker run` a `composer:2` / `php:8.3-cli` container, or Lando.

### 5. `docs/DEMO_RENDER.md` (new)

What is deployed, redeploy, reset the DB, rotate the demo password, known limits. Env values are NOT mirrored in this repo
(no `.env.render.example`): `demo-infra/sites.json` `backend.env` plus OpenTofu are the only source.

## Explicitly not changed

Fargate files, Terraform in this repo, `start.sh`, Horizon/scheduler, Sidecar, S3, SSO, Telescope code.

## Acceptance criteria

1. `docker build -f docker/render/Dockerfile .` succeeds.
2. Run the image against a local MySQL container (TLS optional locally): boots, migrates,
   `GET /api/health/live` → 200 on `$PORT`.
3. `POST /auth/login` with a seeded user + demo password → 200 with `token`.
4. `OPTIONS /api/v1/...` with `Origin: https://lumen.khubaibqaiser.com` → exact ACAO + credentials true.
5. CorsTest passes; no secrets or `.env` in the image (`docker run … ls /app/.env` fails).
6. Seed duration recorded and compared with the Render start-up timeout.

## Security notes

- `demo:set-password` sets **one password for all users**; the demo is public → seed data must be fake
  and no real credentials may exist in the Render environment.
- `routes/temporary.php` is auth-protected and not env-gated (has an `exec()` route). Out of scope, but
  flag it before any non-demo use.
- Login is already throttled (`throttle:5,1`).
