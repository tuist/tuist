# Luft server

Serves all of `luft.work`: the Luft web app (`../luft/web/`), whose build the release carries, and its backend for frontend (OAuth 2.0 for Browser-Based Applications, RFC 10017) under `/api` and `/auth`, on one origin. Tuist is the identity provider and keeps owning accounts, organizations, sandboxes and everything else Luft builds on; this server signs people in with Tuist and acts for them.

## The contract

Standard protocols only, so either side can change implementation without the other:

| Step | Standard | Endpoint (on the Tuist server) |
| --- | --- | --- |
| Provider discovery | OpenID Connect Discovery 1.0 | `GET /.well-known/openid-configuration` |
| Sign in | OAuth 2.0 authorization code (RFC 6749) + PKCE S256 (RFC 7636), OpenID Connect Core 1.0 with `nonce` | `GET /oauth2/authorize?scope=openid profile email account:organizations:write` |
| Sign up | Initiating User Registration via OpenID Connect 1.0 (`prompt=create`) | same |
| Code exchange | Confidential client, `client_secret_basic` | `POST /oauth2/token` |
| ID token | JWT signed RS256, keys as a JWK Set (RFC 7517) | `GET /oauth2/jwks` |
| Profile | OpenID Connect UserInfo | `GET /oauth2/userinfo` |
| Refresh / sign out | RFC 6749 section 6 (rotating) / RFC 7009 | `POST /oauth2/token`, `POST /oauth2/revoke` |
| Accounts and organizations | Bearer tokens (RFC 6750) on the Tuist REST API | `GET`/`POST /api/organizations` |

The ID token's `sub` is the Tuist user ID (stable); `preferred_username` is the personal account handle and `email`/`email_verified` the address. Unlike the Tuist and Luft apps, the Luft server's client is not first-party: it keeps refresh tokens for everyone who signs in, so its access tokens do only what their scopes grant (RFC 9700 2.3). Listing the person's organizations needs no scope; creating one needs `account:organizations:write`. New Luft features that call Tuist add a scope to `Tuist.OAuth.Clients.luft_server_scopes/0` and request it here.

What this server exposes to the Luft web app, same-origin with a session cookie (`__Host-Http-luft_session`, `HttpOnly`, `Secure`, `SameSite=Strict`):

- `GET /auth/login?return_to=<path>[&signup=1]`: starts signing in (or up) with Tuist, then lands on `return_to` (a local path, default `/`).
- `GET /auth/callback`: the OAuth redirect URI.
- `POST /auth/logout`: ends the session and revokes Tuist's refresh token.
- `GET /api/me`: `{id, handle, email}`.
- `GET /api/organizations`: the person's Tuist organizations; `POST /api/organizations` `{name}` creates one in Tuist.

Writes must carry this origin's `Origin` header, which browsers add to every same-origin `fetch` POST.

Unauthenticated API calls answer `401 {"error": "unauthenticated", "login_url": ...}`.

## Configuration

Tuist server (the deployment Luft signs in to), all required for it to act as the OpenID Provider. In production the Tuist chart's `server.config.luftServerOidc` syncs them: the signing key from the `OIDC_PROVIDER` 1Password item (`signing-key.pem`), the client ID and secret from the `LUFT_SERVER` item this server's chart also reads, and the redirect URIs from the chart's values.

- `TUIST_OIDC_SIGNING_KEY`: RSA private key (PEM) that signs ID tokens.
- `TUIST_LUFT_SERVER_OAUTH_CLIENT_ID` (a UUID) and `TUIST_LUFT_SERVER_OAUTH_CLIENT_SECRET`.
- `TUIST_LUFT_SERVER_OAUTH_REDIRECT_URIS`: `https://luft.work/auth/callback` (comma-separated, exact).

This server (`config/runtime.exs`): `DATABASE_URL`, `SECRET_KEY_BASE`, `LUFT_SERVER_OAUTH_CLIENT_ID`, `LUFT_SERVER_OAUTH_CLIENT_SECRET`, and optionally `TUIST_URL` (default `https://tuist.dev`) and `PUBLIC_URL` (default `https://luft.work`), the origin people see.

## Local development

```sh
# Tuist server with the Luft server client (from server/)
openssl genrsa -out /tmp/oidc.pem 2048
TUIST_OIDC_SIGNING_KEY="$(cat /tmp/oidc.pem)" \
TUIST_LUFT_SERVER_OAUTH_CLIENT_ID=0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37 \
TUIST_LUFT_SERVER_OAUTH_CLIENT_SECRET=local-dev-secret \
TUIST_LUFT_SERVER_OAUTH_REDIRECT_URIS=http://localhost:4200/auth/callback \
mise run dev

# This server and the web app (from luft-server/), on http://localhost:4200
mise install && mix setup
TUIST_URL=http://localhost:8080 \
LUFT_SERVER_OAUTH_CLIENT_ID=0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37 \
LUFT_SERVER_OAUTH_CLIENT_SECRET=local-dev-secret \
mix phx.server
```

`mix phx.server` also starts the web app as a watcher: `mise run dev:web` in `../luft` builds the core's wasm bindings with Struo and runs Vite on `127.0.0.1:5173`. Phoenix proxies every path it does not route itself to Vite (`LuftServerWeb.WebController`), so the browser sees one origin, as in production; only Vite's HMR WebSocket connects to 5173. Restart after changing the Rust core. Open `http://localhost:4200/auth/login` and sign in with `tuistrocks@tuist.dev` / `tuistrocks`.

## Serving the web app

In production the image carries Struo's build of the web app (`luft/.struo/out/LuftWeb/dist`, the Docker `site` build context) in `priv/static`. `Plug.Static` serves its content-hashed `/assets` as immutable, every other path that is not an API or sign-in route gets the HTML shell with `Cache-Control: no-cache`, and misses under `/api`, `/auth` and `/assets` are JSON 404s. `LuftServerWeb.Plugs.SecurityHeaders` sets the content security policy (with `'wasm-unsafe-eval'` for the core), HSTS, `nosniff` and the referrer policy on every response. To build the image locally, from the repository root after `mise run build:web` in `luft/`:

```sh
docker build -f luft-server/Dockerfile --build-context site=luft/.struo/out/LuftWeb/dist .
```
