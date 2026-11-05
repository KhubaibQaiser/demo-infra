# Spec: `custom-crm` / Lumen (frontend)

Repo: `KhubaibQaiser/custom-crm` · local: `/Users/khubaib-work/Documents/PowerfulWeb/stagworks-react`

The frontend needs almost no code change. Hosting is configured by `demo-infra` (OpenTofu creates the
Cloudflare Pages project and sets build env vars). The Cloudflare proxy function from the earlier plan
is **dropped** (auth is a Bearer token; see 00-overview).

## Facts that matter

- Build: `npm run build` (`tsc -b && vite build`) → output `./build`. Node 22 (`.nvmrc`).
- API base: `import.meta.env.VITE_API_URL` → axios `baseURL`. Endpoints are `/api/v1/...` and
  `/auth/login`, so `VITE_API_URL` is the **backend host root**, e.g. `https://lumen-api.khubaibqaiser.com`.
- Login: `POST /auth/login` → `{ token, user }`; token stored via `CookieManager`, sent as
  `Authorization: Bearer`. Authed calls use `withCredentials: true` (needs backend CORS credentials; done in spec 01).
- SPA fallback already exists: `public/_redirects` → `/* /index.html 200`.
- `prepare: husky` and `postinstall: chmod +x .husky/pre-push` run on `npm ci` → set `HUSKY=0` in CI/Pages.
- `VITE_AUTH_URL` is only used by `src/_pages/auth/microsoft-sso.ts`; I found no UI importing it.

## Changes

1. **`.env.example`**: document the demo/production values (names + example host), with a comment that
   `VITE_AUTH_URL` is not needed for the demo. No real values.
2. **SSO guard (only if needed)**: while implementing, confirm the login screen shows only
   email/password with `VITE_AUTH_URL` unset. If a Microsoft button exists, render it only when
   `VITE_AUTH_URL` is set. Otherwise no code change.
3. **Build verification**: `HUSKY=0 npm ci && npm run build` on Node 22; record output size and file
   count (Pages limits: verify current numbers; third-party sources say ~20k files, 25 MiB/file).
4. No Pages Function, no `wrangler.toml` in this repo (project settings live in `demo-infra/tofu`).

## Build-time environment (set by OpenTofu on the Pages project, not committed)

| Var | Value |
|---|---|
| `NODE_VERSION` | `22` |
| `HUSKY` | `0` |
| `VITE_API_URL` | `https://lumen-api.khubaibqaiser.com` (derived from `sites.json` `backend.subdomain`) |
| `VITE_ENV` | `demo` |
| `VITE_SENTRY_DSN`, `VITE_TINY_MCE_KEY`, `VITE_GOOGLE_MAPS_API_KEY` | unset (optional features off) |

## Acceptance criteria

1. Clean `npm ci && npm run build` passes with the env above; `build/index.html` exists.
2. `npm run preview` (or a static server) + `VITE_API_URL` pointing at the local backend container:
   email/password login succeeds and the dashboard loads.
3. Deep link reload (e.g. `/clients`) works via `_redirects`.
4. No SSO control visible on the login page.
5. Browser console shows no CORS errors against the deployed API after DNS is live.

## Out of scope

Microsoft SSO, Sentry, Google Maps, TinyMCE, PDF-dependent screens (backend limitation).
