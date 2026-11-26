# Luft server

Headless server at `https://luft.work` for Luft's native clients. It brokers Tuist OpenID Connect sign-in, issues Luft credentials and owns threads, lounges, DMs, runners, execution journals and conversation realtime in its own PostgreSQL database. Tuist owns accounts, organizations, provider credentials and sandbox infrastructure, exposed through scoped capabilities. Its only frontend is the GPUI web edge (`../luft/gpui-web/`) under `/app/`; the root and every other path stay headless, for server-rendered pages later. The standalone sources in `../luft/web/` remain outside this release and deployment.

## The contract

Standard protocols only, so either side can change implementation without the other:

| Step | Standard | Endpoint (on the Tuist server) |
| --- | --- | --- |
| Provider discovery | OpenID Connect Discovery 1.0 | `GET /.well-known/openid-configuration` |
| Sign in | OAuth 2.0 authorization code (RFC 6749) + PKCE S256 (RFC 7636), OpenID Connect Core 1.0 with `nonce` | `GET /oauth2/authorize` with the server's requested scopes |
| Sign up | Initiating User Registration via OpenID Connect 1.0 (`prompt=create`) | same |
| Code exchange | Confidential client, `client_secret_basic` | `POST /oauth2/token` |
| ID token | JWT signed RS256, keys as a JWK Set (RFC 7517) | `GET /oauth2/jwks` |
| Profile | OpenID Connect UserInfo | `GET /oauth2/userinfo` |
| Refresh / sign out | RFC 6749 section 6 (rotating) / RFC 7009 | `POST /oauth2/token`, `POST /oauth2/revoke` |
| Accounts and organizations | Bearer tokens (RFC 6750) on the Tuist REST API | `GET`/`POST /api/organizations` |

The ID token's `sub` is the Tuist user ID (stable); `preferred_username` is the personal account handle and `email`/`email_verified` the address. The Luft server's confidential client holds scoped Tuist credentials, encrypted in PostgreSQL sessions; it never returns those credentials to a native client or browser. Tuist's `Tuist.OAuth.Clients.luft_server_scopes/0` allows `openid profile email`, `account:organizations:write`, `luft:app`, `mcp`, `account:delete`, `account:members:read`, `account:sandboxes:write`, `account:repositories:read`/`account:repositories:write`, `project:admin:read` and `project:previews:read`/`project:previews:write`. Keep the requested scopes in `LuftServer.Tuist.OIDC` aligned with capabilities it needs. Existing sessions need another sign-in to obtain newly requested scopes.

### Native clients

Native clients default to `https://luft.work`. Desktop `LUFT_URL` overrides the saved startup origin; `TUIST_URL` does not configure native clients. A custom origin must be a Luft server exposing `GET /.well-known/luft.json` with `luft_oauth_client_id` equal to the fixed public native client ID `6653b77b-b787-4eb2-b955-8380ea5f1478`.

Boruta owns the downstream authorization-code, PKCE, access-grant and refresh lifecycle. Tuist authenticates the person; Luft creates its own 30-day session to hold encrypted upstream credentials. Boruta grants reference that session's UUID as their resource-owner subject, so separate sign-ins for the same person remain independent. The JWT serializer retains the user identity and account claims native clients display. Bearer authentication checks Boruta's stored grant and the live session; logout removes both the session and its grants and revokes its upstream refresh token, without clearing the person's Tuist browser session.

- `GET /oauth2/authorize`, `/oauth2/apple`, `/oauth2/google` and `/oauth2/github` start authorization-code sign-in with state and PKCE S256. Luft redirects through Tuist OIDC, where every sign-in requires explicit, CSRF-protected consent even when the person is already signed in to Tuist. Luft then returns a single-use code to exactly `luft://oauth-callback` or the desktop loopback URL `http://127.0.0.1:<port>/callback`.
- `POST /oauth2/token` exchanges that code and verifier, or rotates a refresh token. Luft issues a signed access JWT (`iss=luft`, native client audience), valid for up to one hour, and an opaque rotating `luft_refresh_…` token backed by a 30-day session. Clients send the access JWT as a bearer token; encrypted Tuist tokens stay on the server.
- Request objects (`request` and `request_uri`) are unsupported on native authorization and token endpoints and are rejected before Boruta parses them or makes HTTP requests. Both query and body parameter sources are checked.
- Retrying the immediately previous refresh credential within 60 seconds returns the same replacement token pair, including across replicas, so losing the first response does not sign the client out. A later rotation or logout ends that recovery window. Authorization codes remain strictly single-use.
- Each sign-in, sign-out, code exchange, refresh (including retries and reuse of a spent code or refresh token) and session revocation logs one line through `LuftServer.AuthEvents`: `auth_event`, `auth_outcome`, `auth_client`, `user_sub`, `session_id`, and the request's `client_address` (Cloudflare's `CF-Connecting-IP`, else the peer), `forwarded_for` and `user_agent`. Lines go to stdout, which the cluster's log collector ships to Pulse; they never carry tokens, codes or verifiers. Find a session's history with `auth_event=` and its `session_id`.
- The API serves `/api/accounts/:account_handle/threads` and `/lounges` locally. `/threads/socket/websocket` terminates in Luft, including inbox and presence channels. `/api/me/ai-subscriptions` (list, `PUT /claude`, `POST /chatgpt/login`, `POST /chatgpt/login/poll`, `DELETE /chatgpt/login`, `DELETE /:provider`) forwards to Tuist's endpoints of the same shape, adding `runs_threads` to each subscription; Tuist keeps the credentials. Each change that succeeds is broadcast to the person's `ai_subscriptions` channel on the same socket, which also reads Tuist every 15 seconds so changes made on Tuist itself show up live. Only identity/organization, preview/project, account deletion and generic device-transport requests go upstream.
- Local runner registration returns a `luft_runner_local_…` credential once, stores only its SHA-256 hash, and binds it to the exact Luft session. Logout, expiry and revocation invalidate it. Legacy encrypted upstream wrappers remain recognizable but are not newly issued. Preview links and media use the Luft origin; object-storage URLs remain unchanged.

### Conversation authority and cutover

Threads persist the exact owner's session for subscription-backed inference and the originating author's session for personal tools. Execution reloads Tuist authorization; it never chooses another sign-in for the same person. Tuist's generic inference, MCP, workspace/repository and notification APIs retain upstream secrets without owning conversations. Shipping persists reviewed consent before dispatch; an uncertain publication is reconciled by observation, never retried as a new write.

Luft supervises its durable agent hosts and uses Oban for recovery, shipping, timed snooze and notification jobs. Production replicas require the chart's dedicated distribution cookie and DNS clustering configuration. Keep `SECRET_KEY_BASE` stable and identical across replicas: it protects sessions, checkpoints, results and journal objects. The image includes the trusted native card kit, checksum-pinned NSH compiler and muontrap; it contains no browser frontend.

Follow [the offline cutover runbook](docs/conversation-cutover.md) before switching historical traffic. The import preserves IDs/history, re-encrypts private state and deliberately clears historical execution delegation. An owner can explicitly bind an idle thread to the current sign-in with `POST /api/accounts/:account_handle/threads/:id/reauthorize`. Imported unfinished work must first be archived/cancelled and restored; reauthorization never revives old commands or shipping consent. Historical source tables and objects remain retained until separately approved retirement. Tuist account/user deletion does not cascade into this separate database; operators must coordinate erasure and legal exports across both stores before production cutover.

Boruta uses its upstream Ecto adapters with PostgreSQL-authoritative reads. `NativeAuth.exchange/1` locks the owning session and commits Boruta's writes with the encrypted retry response in one transaction. Keep those locks: the adapters' check-then-revoke flow alone does not serialize concurrent code redemption or refresh rotation. New Boruta releases may require more generated migrations (`mix boruta.gen.migration`). Apply the generated migrations and `20261119190200_configure_luft_oauth_grants` before starting this version. The former custom native credentials do not have Boruta grants and require a fresh sign-in; browser-cookie sessions remain valid.

Take a database backup before this schema upgrade. A full schema downgrade is not supported by the upstream migration chain: `ClientsSignaturesAdapters`, for example, cannot reverse its column alterations. Prefer a forward fix or restore a pre-upgrade backup with writers stopped. The Luft-specific grant migration does have a rollback, which deletes native grants rather than truncating JWTs and therefore requires another sign-in; it does not make the upstream migrations reversible.

### Retained browser cookie flow

The existing browser flow remains available without a deployed frontend. It uses the same-origin session cookie (`__Host-Http-luft_session`, `HttpOnly`, `Secure`, `SameSite=Strict`):

- `GET /auth/login?return_to=<path>[&signup=1]`: starts signing in (or up) with Tuist, then lands on `return_to` (a local path, default `/`).
- `GET /auth/callback`: the OAuth redirect URI.
- `POST /auth/logout`: ends the session and revokes Tuist's refresh token.
- `GET /api/me`: `{id, handle, email}`.
- `GET /api/organizations`: the person's Tuist organizations; `POST /api/organizations` `{name}` creates one in Tuist.

Cookie-authenticated writes must carry this origin's `Origin` header. Native bearer requests use Luft access JWTs.

Unauthenticated API calls answer `401 {"error": "unauthenticated", "login_url": ...}`.

## Configuration

Tuist server (the deployment Luft signs in to), all required for it to act as the OpenID Provider. In production the Tuist chart's `server.config.luftServerOidc` syncs them: the signing key from the `OIDC_PROVIDER` 1Password item (`signing-key.pem`), the client ID and secret from the `LUFT_SERVER` item this server's chart also reads, and the redirect URIs from the chart's values.

- `TUIST_OIDC_SIGNING_KEY`: RSA private key (PEM) that signs ID tokens. It may hold several concatenated PEM blocks: the first signs, and `/oauth2/jwks` publishes all of them, so a key can be published before it signs and kept while its tokens are live. `Tuist.Environment.oidc_signing_keys/1` has the rotation steps.
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

# This headless server (from luft-server/), on http://localhost:4200
mise install && mix setup
TUIST_URL=http://localhost:8080 \
LUFT_SERVER_OAUTH_CLIENT_ID=0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37 \
LUFT_SERVER_OAUTH_CLIENT_SECRET=local-dev-secret \
mix phx.server
```

`mix phx.server` starts only Phoenix, with no web watcher. Use `http://localhost:4200` as a native development origin (desktop: `LUFT_URL=http://localhost:4200`); HTTP is for loopback development only. The Tuist seed login is `tuistrocks@tuist.dev` / `tuistrocks`. The retained `/auth/login` flow ends at a JSON 404 if its `return_to` has no API route; there is no landing page.

## Release image

The image contains the Elixir release, database migrations, the native card compiler/kit and the GPUI web edge. A `luft-web` stage compiles `luft-gpui-web` to wasm with Luft's pinned Rust and wasm-bindgen, without Struo or Node, and the release serves the output from `priv/static/app`: `/app` redirects to `/app/`, `/app/` and its client-side paths return the page, and only `main.js`, `luft_gpui_web.js` and `luft_gpui_web_bg.wasm` (gzip-compressed when accepted) are served as files, under a content security policy for that app alone. Unmatched paths return JSON 404s, including `/`, `/index.html`, `/assets/*` and other files under `/app/`. `.github/workflows/luft-server-deployment.yml` also redeploys when the Luft sources this build reads change. Build from the repository root:

```sh
docker build -f luft-server/Dockerfile .
```
